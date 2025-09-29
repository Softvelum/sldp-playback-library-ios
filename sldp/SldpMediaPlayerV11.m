#import "SldpMediaPlayerV11.h"

@implementation SldpMediaPlayerV11
{
    double _lastSyncTime;
    uint64_t _stableСount;
    double _sumDeviation;
}

const double MIN_DEVIATION = 0.03;
const double SYNCTIME_NOT_INITED = -1e6;

-(id)initWithBuffer:(uint32_t)bufferMs andThreshold:(uint32_t)thresholdMs externalDecoding:(BOOL) externalDecoding {
    self = [super initWithBuffer:bufferMs andThreshold:thresholdMs externalDecoding:externalDecoding];
    if (self) {
        _audioZeroBiasTs = -1;
        _steadyWaitTimer = NULL;
        _lastSyncTime = SYNCTIME_NOT_INITED;
        [self resetStreadyTime];
        _renderSynchronizer = [[AVSampleBufferRenderSynchronizer alloc] init];
    }
    return self;
}

-(void)stop: (bool)removeImage {
    if (self.stopped) {
        return;
    }
    self.stopped = true;

    if (_steadyWaitTimer != NULL && _steadyWaitTimer.valid) {
        [_steadyWaitTimer invalidate];
        _steadyWaitTimer = NULL;
    }
    [_renderSynchronizer setRate:0.f time:kCMTimeInvalid];
    
    if (_audioRenderer != nil) {
        [_renderSynchronizer removeRenderer:_audioRenderer atTime:kCMTimeZero completionHandler:^(BOOL didRemoveRenderer) {
            //NSLog(@"Removed audio renderer: %@", didRemoveRenderer ? @"Yes" : @"No");
        }];
    }
    
    if (self.displayLayer != nil) {
        [_renderSynchronizer removeRenderer:self.displayLayer atTime:kCMTimeZero completionHandler:^(BOOL didRemoveRenderer) {
            //NSLog(@"Removed video renderer: %@", didRemoveRenderer ? @"Yes" : @"No");
        }];
    }
    
    if (_timeObserverToken != nil) {
        [_renderSynchronizer removeTimeObserver:_timeObserverToken];
    }
    [_audioRenderer flush];
    
    if (_audioDesc) {
        CFRelease(_audioDesc);
        _audioDesc = NULL;
    }

    [super stop: removeImage];
}

-(bool)startAudioDecodeWithTimescale:(int)timescale
                              format:(AudioStreamBasicDescription)audioFormat
                       channelLayout:(AudioChannelLayoutTag) channelLayout
                      packetCapacity:(AVAudioFrameCount)packetCapacity {
    
    NSLog(@"PlayerV11::startAudioDecodeWithTimescale %d", timescale);
    
    self.audioFormat = audioFormat;
    self.timescaleAudio = timescale;
    [self printAudioStreamBasicDescription:audioFormat];
    OSStatus status = noErr;
    if (channelLayout != kAudioChannelLayoutTag_Unknown) {
        AudioChannelLayout layout = {
            .mChannelLayoutTag = channelLayout};
        layout.mChannelLayoutTag = channelLayout;
        status = CMAudioFormatDescriptionCreate(kCFAllocatorDefault,
                                                         &audioFormat,
                                                         sizeof(layout), &layout,
                                                         0, NULL, NULL,
                                                         &_audioDesc);
    } else {
        status = CMAudioFormatDescriptionCreate(kCFAllocatorDefault,
                                                         &audioFormat,
                                                         0, NULL, 0, NULL, NULL,
                                                         &_audioDesc);

    }

    if (status != noErr) {
        NSLog(@"failed to create audio format descriptor, status=%d", (int)status);
        return false;
    }
    
    if (_numAudioFrames == 0) {
        _audioRenderer = [[AVSampleBufferAudioRenderer alloc] init];
        [self setVolume:self.lastVolume];
        [self mute:self.muted];
        [_renderSynchronizer addRenderer:_audioRenderer];
    }
    
    return true;
}

- (bool)writeAudioFrameWithTimestamp:(uint64_t)timestamp numSamples:(uint32_t)numSamples buffer:(const uint8_t *)buffer len:(int)len {
    
    //NSLog(@"PlayerV11::writeAudioFrameWithTimestamp %llu len=%d", timestamp, len);
    
    if (_audioRenderer.status == AVQueuedSampleBufferRenderingStatusFailed) {
        [self printDisplayLayerError];
        [self.delegate playbackDidFail];
        return false;
    }
    
    CMBlockBufferRef blockBuffer = NULL;
    OSStatus status = CMBlockBufferCreateWithMemoryBlock(kCFAllocatorDefault,
                                                         (void*)buffer, // memoryBlock to hold buffered data
                                                         len, // block length of the mem block in bytes.
                                                         kCFAllocatorNull,
                                                         NULL,
                                                         0, // offsetToData
                                                         len, // dataLength of relevant bytes, starting at offsetToData
                                                         0,
                                                         &blockBuffer);
    if(status != noErr) {
        NSLog(@"failed to create block buffer, status=%d", (int)status);
        return false;
    }
    
    CMSampleBufferRef sampleBuffer = NULL;
    const size_t sampleSize = len;
    
    [self updateAudioStreamPositionWithTimestamp:timestamp];
    
    if (@available(iOS 13.0, *)) {
        
    } else if (!self.steadyMode) {
        timestamp = [self rebaseAudio:timestamp];
    }
    
    CMSampleTimingInfo timingInfo = {
        .duration = kCMTimeInvalid,
        .presentationTimeStamp = CMTimeMake(timestamp, self.timescaleAudio),
        .decodeTimeStamp = kCMTimeInvalid
    };
    
    //NSLog(@"timestampIn=%lld", timingInfo.presentationTimeStamp.value);
    
    status = CMSampleBufferCreate(kCFAllocatorDefault,
                                  blockBuffer,
                                  true, NULL, NULL,
                                  _audioDesc,
                                  1,
                                  1, &timingInfo,
                                  1, &sampleSize,
                                  &sampleBuffer);
    
    if(status != noErr) {
        NSLog(@"failed to create sample buffer, status=%d", (int)status);
        return false;
    }
    
    if (self.playbackType == kPlaybackTypeAudioOnly) {
        if (_numAudioFrames == 0) {
            self.zeroTime = CMSampleBufferGetPresentationTimeStamp(sampleBuffer);
            self.streamZeroPtsMs = self.audioZeroPtsMs;
            self.rate = 0.f;
            [_renderSynchronizer setRate:self.rate time:self.zeroTime];
            NSLog(@"start audio at %f", CMTimeGetSeconds(self.zeroTime));
        } else if (self.steadyMode) {
            if (_lastSyncTime == SYNCTIME_NOT_INITED) {
                [self adjustPlaybackRate: self.zeroTime];
            }
        } else if (self.rate < 1.f && self.audioPtsMs - self.audioZeroPtsMs > self.bufferMs) {
            self.rate = 1.f;
            [_renderSynchronizer setRate:self.rate time:kCMTimeInvalid];
            NSLog(@"PLAY AUDIO ONLY");
            [self startStarvationTimer];
            [self.delegate playbackDidStart];
        }
    }
    
//    if (self.audioZeroPtsMs != -1 && self.audioPtsMs - self.audioZeroPtsMs > 10000) {
//        // TEST STARVATION
//        return true;
//    }
    
    _numAudioFrames++;
    [_audioRenderer enqueueSampleBuffer:sampleBuffer];
    CFRelease(blockBuffer);
    CFRelease(sampleBuffer);
    
    return true;
}

-(bool)updateStreamPosition:(CMSampleBufferRef)sampleBuffer {
//    if (self.videoZeroPtsMs != -1 && self.videoPtsMs - self.videoZeroPtsMs > 10000) {
//        // TEST STARVATION
//        return;
//    }
    
    bool result = [super updateStreamPosition:sampleBuffer];
    if (!result) {
        return false;
    }

    if (self.numVideoFrames == 1) {
        NSLog(@"start video at %f", CMTimeGetSeconds(self.zeroTime));
        [_renderSynchronizer addRenderer:self.displayLayer];
        self.rate = 0.0;
        [_renderSynchronizer setRate:self.rate time:self.zeroTime];
    } else if (self.steadyMode) {
        if (_lastSyncTime == SYNCTIME_NOT_INITED) {
            [self adjustPlaybackRate: self.zeroTime];
        }
    } else if (self.rate < 1.0
               && self.videoPtsMs > self.videoZeroPtsMs
               && self.videoPtsMs - self.videoZeroPtsMs > self.bufferMs) {
        
        NSLog(@"play video, buffering %dms, has video buffer %llu frames", self.bufferMs, self.numVideoFrames);
        self.rate = 1.0f;
        [_renderSynchronizer setRate:self.rate time:kCMTimeInvalid];
        [self startStarvationTimer];
        [self.delegate playbackDidStart];
    } else if (self.rate < 1.0) {
        uint64_t delta = self.videoPtsMs - self.videoZeroPtsMs;
        NSLog(@"Accumulated %lld ms", delta);
    }
    return true;
}

-(void)adjustPlaybackRate: (CMTime) time {
    double played = CMTimeGetSeconds(time) - CMTimeGetSeconds(self.zeroTime);
    double deviation = [self getDeviationForPlayTime: played];
    if (played < _lastSyncTime + 0.05 && _lastSyncTime > 0.001) {
        return;
    }
    _lastSyncTime = played;
    if (fabs(deviation) < MIN_DEVIATION && self.rate > 0.99 && self.rate < 1.01) {
        _stableСount++;
        _sumDeviation = 0.0;
        return;
    }
    NSLog(@"Time deviation %4.3f", deviation);
    if (_stableСount > 10) { //&& fabs(deviation) < 0.100 && fabs(_sumDeviation) < MIN_DEVIATION * 100) {
        //Allow some fluctuation after stablilization
        _sumDeviation += deviation + MIN_DEVIATION * (deviation < 0.0 ? 1.0 : -1.0);
        //NSLog(@"sum deviation %4.3f", _sumDeviation);
        return;
    }
    float newRate = self.rate;
    if (deviation > MIN_DEVIATION) {
        [self changePlaybackRate:0.0];
        __weak SldpMediaPlayerV11* player = self;
        double pauseTime = MAX(0.2, deviation);
        _steadyWaitTimer = [NSTimer timerWithTimeInterval: pauseTime repeats:NO block:^(NSTimer * _Nonnull timer) {
            [player changePlaybackRate:1.0];
        }];
        NSRunLoop *runLoop = [NSRunLoop mainRunLoop];
        [runLoop addTimer:_steadyWaitTimer forMode:NSDefaultRunLoopMode];
        NSLog(@"Pause for %3.3f s", pauseTime);

    } else if (deviation < -0.500) {
        newRate = 2.0;
    } else if (deviation < -0.010) {
        newRate = 1.5;
    } else {
        newRate = 1.0;
    }
    [self changePlaybackRate:newRate];
    _stableСount = 0;
    _sumDeviation = 0.0;
}

-(void)changePlaybackRate:(float) newRate {
    if (_timeObserverToken == NULL) {
        NSLog(@"init observation timer");
        CMTime timeInterval = CMTimeMakeWithSeconds(0.1, 1000);
        __weak SldpMediaPlayerV11 *player = self;
        _timeObserverToken = [_renderSynchronizer addPeriodicTimeObserverForInterval:timeInterval queue:dispatch_get_main_queue() usingBlock:^(CMTime time) {
            [player adjustPlaybackRate: time];
        }];
    }
    if (newRate != 0 && self.starvationTimer == NULL) {
        [self startStarvationTimer];
        [self.delegate playbackDidStart];
    }

    if (fabs(newRate-self.rate) < 0.01) {
        return;
    }

    NSLog(@"changePlaybackRate %1.3f -> %1.3f", self.rate, newRate);
    self.rate = newRate;
    [_renderSynchronizer setRate:newRate time:kCMTimeInvalid];
}
                              
-(void)resetStreadyTime {
    NSLog(@"resetStreadyTime ");

    [super resetStreadyTime];
    _stableСount = 0;
    _sumDeviation = 0.0;
    if (_steadyWaitTimer != NULL && _steadyWaitTimer.valid) {
        [_steadyWaitTimer invalidate];
        if (self.rate != 1.0) {
            self.rate = 1.0;
            [_renderSynchronizer setRate:1.0 time:kCMTimeInvalid];
        }
    }
}


-(void)mute:(bool)muted {
    [_audioRenderer setMuted:muted];
    self.muted = muted;
}

-(bool)isMuted {
    if (_audioRenderer != nil) {
        return _audioRenderer.isMuted;
    }
    return self.muted;
}

-(void)setVolume:(float)volume  {
    self.lastVolume = volume;
    [_audioRenderer setVolume:volume];
}

-(float)getVolume {
    if (_audioRenderer != nil) {
        return _audioRenderer.volume;
    }
    return self.lastVolume;
}

-(uint64_t)rebaseAudio:(uint64_t)timestamp {
    if (_audioZeroBiasTs == -1) {
        _audioZeroBiasTs = timestamp;
    }
    uint64_t rebased_timestamp = 0;
    if (timestamp > _audioZeroBiasTs) {
        rebased_timestamp = timestamp - _audioZeroBiasTs;
    }
    return rebased_timestamp;
}

@end
