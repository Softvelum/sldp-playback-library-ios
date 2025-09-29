#import "SldpMediaPlayer.h"

#define TICK   startTime = [NSDate date]
#define TOCK   NSLog(@"Video: %f", -[startTime timeIntervalSinceNow])

// mp3: 8064 = 144 * 448(max bitRate) * 1000 / 8000(min sampleRate) + padding
// aac: 8192 = 2^13, 13bit AAC frame size (in bytes)
#define MAX_PACKET_SIZE (9 * 1024)
static const size_t OPUS_HEADER_LEN = 19;

@implementation SldpMediaPlayer
{
    NSDate* _startAudioTime;
}

- (void)stop: (bool)removeImage {
    if (self.stopped) {
        return;
    }
    self.stopped = true;
    [_player stop];
    [_engine stop];
    [super stop: removeImage];
}

-(bool)updateStreamPosition:(CMSampleBufferRef)sampleBuffer {
    bool result = [super updateStreamPosition:sampleBuffer];
    if (result == false) {
        return false;
    }
    
    if (self.numVideoFrames == 1) {
        CMTime presentationTimeStamp = CMSampleBufferGetPresentationTimeStamp(sampleBuffer);
        //NSLog(@"cache=%lld", presentationTimeStamp.value);
        CMTimebaseRef controlTimebase;
        CMTimebaseCreateWithSourceClock(kCFAllocatorDefault, CMClockGetHostTimeClock(), &controlTimebase);
        CMTimebaseSetTime(controlTimebase, presentationTimeStamp);
        self.rate = 0.0; // zero rate means "stop playback
        CMTimebaseSetRate(controlTimebase, self.rate);
        self.displayLayer.controlTimebase = controlTimebase;

    } else if (self.rate < 1.f
               && self.videoPtsMs > self.videoZeroPtsMs
               && self.videoPtsMs - self.videoZeroPtsMs > self.bufferMs) {
        CMTimebaseRef controlTimebase = [self.displayLayer controlTimebase];
        self.rate = 1.f;
        CMTimebaseSetRate(controlTimebase, self.rate);
        NSLog(@"play video, buffering %dms, has video buffer %llu frames", self.bufferMs, self.numVideoFrames);
        if (self.playbackType == kPlaybackTypeVideoAudio) {
            [self playAudio];
        }
        [self startStarvationTimer];
        [self.delegate playbackDidStart];
    }
    return true;
}

-(bool)startAudioDecodeWithTimescale:(int)timescale
                              format:(AudioStreamBasicDescription)audioFormat
                       channelLayout:(AudioChannelLayoutTag) layoutTag
                      packetCapacity:(AVAudioFrameCount)packetCapacity {
    
    self.audioFormat = audioFormat;
    self.timescaleAudio = timescale;
    [self printAudioStreamBasicDescription:audioFormat];

    _offset = 0;
    _idx = 0;
    _packetCapacity = packetCapacity;
    _frameCapacity = audioFormat.mFramesPerPacket * packetCapacity;
    
//    AVAudioSession *session = [AVAudioSession sharedInstance];
//    [session setCategory:AVAudioSessionCategoryPlayback error:nil];
//    [session setMode:AVAudioSessionModeMoviePlayback error:nil];
//    [session setPreferredSampleRate:audioFormat.mSampleRate error:nil];
//    [session setActive:YES error:nil];
//    NSLog(@"%f, %f", audioFormat.mSampleRate, [session preferredSampleRate]);
    
    _engine = [[AVAudioEngine alloc] init];
    _player = [[AVAudioPlayerNode alloc] init];
    _mixer = [[AVAudioMixerNode alloc] init];
    [_engine attachNode:_player];
    [_engine attachNode:_mixer];
    
    if (layoutTag != kAudioChannelLayoutTag_Unknown) {
        AVAudioChannelLayout *channelLayout = [[AVAudioChannelLayout alloc] initWithLayoutTag:layoutTag];
        _compressedFormat = [[AVAudioFormat alloc] initWithStreamDescription:&audioFormat channelLayout:channelLayout];
        //_processingFormat = [[AVAudioFormat alloc] initStandardFormatWithSampleRate:_compressedFormat.sampleRate channelLayout:channelLayout];
        _processingFormat = [[AVAudioFormat alloc] initStandardFormatWithSampleRate:_compressedFormat.sampleRate channels: 2];
    } else if (audioFormat.mChannelsPerFrame > 2) { // Only formats with more than 2 channels are required to have channel layouts.
        AVAudioChannelLayout *channelLayout = [[AVAudioChannelLayout alloc] initWithLayoutTag:kAudioChannelLayoutTag_DiscreteInOrder | (UInt32)audioFormat.mChannelsPerFrame];
        
        _compressedFormat = [[AVAudioFormat alloc] initWithStreamDescription:&audioFormat channelLayout:channelLayout];
        _processingFormat = [[AVAudioFormat alloc] initStandardFormatWithSampleRate:_compressedFormat.sampleRate channels: 2];
        NSLog(@"Converting from %d ch to stereo", audioFormat.mChannelsPerFrame);
    } else {
        _compressedFormat = [[AVAudioFormat alloc] initWithStreamDescription:&audioFormat];
        
        _processingFormat = [[AVAudioFormat alloc] initStandardFormatWithSampleRate:_compressedFormat.sampleRate channels:_compressedFormat.channelCount];
    }
    
    _compressedBuffer = [[AVAudioCompressedBuffer alloc] initWithFormat:_compressedFormat packetCapacity:_packetCapacity maximumPacketSize:MAX_PACKET_SIZE];
    
    _decompress = [[AVAudioConverter alloc] initFromFormat:_compressedFormat toFormat:_processingFormat];
    
    if (_decompress == nil) {
        NSLog(@"Failed to create audio converter");
        return false;
    }
    
    if (audioFormat.mFormatID == kAudioFormatOpus) {
        [self putOpusHeader:audioFormat];
    }
    if (self.videoChatMode) {
        NSError* err = nil;
        if (@available(iOS 13.0, *)) {
            [_engine.outputNode setVoiceProcessingEnabled: YES error: &err];
            if (err != nil) {
                NSLog(@"Failed to enable voice processing: %@", err.localizedDescription);
            }
        }
        [_engine connect:_player to:_engine.outputNode format:_processingFormat];
    } else {
        [_engine connect:_player to:_mixer format:_processingFormat];
        [_engine connect:_mixer to:_engine.outputNode format:_processingFormat];
    }
    
    NSError *error;
    BOOL status = [_engine startAndReturnError:&error];
    NSLog(@"startAndReturnError: %@", [error localizedDescription]);
    
    self.timescaleAudio = timescale;
    
    [self setVolume:self.lastVolume];
    [self mute:self.muted];

    return (status == NO) ? false : true;
}

-(void)putOpusHeader:(AudioStreamBasicDescription)audioFormat {
    uint32_t sample_rate = (uint32_t)audioFormat.mSampleRate;
    uint8_t channels = (uint8_t)audioFormat.mChannelsPerFrame;
    uint8_t opusHeader[OPUS_HEADER_LEN] = {0};
    memcpy(&opusHeader[0], (const uint8_t*)"OpusHead", 8);
    opusHeader[8] = 0x1;
    opusHeader[9] = channels;
    memcpy(opusHeader + 12, &sample_rate, sizeof(sample_rate));
    memcpy(_compressedBuffer.audioBufferList->mBuffers[0].mData + _offset, opusHeader, OPUS_HEADER_LEN);
    _offset += OPUS_HEADER_LEN;
}

- (bool)writeAudioFrameWithTimestamp:(uint64_t)timestamp numSamples:(uint32_t)numSamples buffer:(const uint8_t *)buffer len:(int)len {

    //NSLog(@"Player::writeAudioFrameWithTimestamp %llu, length=%d num = %d", timestamp, len, numSamples);
    if (_compressedBuffer == nil) {
        NSLog(@"Audio format did not initialized");
        return false;
    }
    
    UInt32 size = (UInt32)len;
    UInt32 total = _offset + size;
    
    memcpy(_compressedBuffer.mutableAudioBufferList->mBuffers[0].mData + _offset, buffer, size);
    //memcpy(&_compressedBuffer.audioBufferList->mBuffers[0].mDataByteSize, &total, sizeof(UInt32));
    _compressedBuffer.byteLength = total;
    
    _compressedBuffer.packetDescriptions[_idx].mDataByteSize = size;
    _compressedBuffer.packetDescriptions[_idx].mStartOffset = _offset;
    _compressedBuffer.packetDescriptions[_idx].mVariableFramesInPacket = numSamples;
    _compressedBuffer.packetCount = _idx + 1;
    
    _idx++;
    _offset += size;

    if (_idx < _packetCapacity) {
        //NSLog(@"skip %d", _idx);
        return true;
    }
    AVAudioFrameCount frameCapacity = numSamples == 0 ? _frameCapacity : numSamples;
    AVAudioPCMBuffer *outBuffer = [[AVAudioPCMBuffer alloc] initWithPCMFormat:_processingFormat frameCapacity:frameCapacity];
    outBuffer.frameLength = frameCapacity;

    NSError *error;
    __block int inputNum = 1;
    [_decompress convertToBuffer:outBuffer error:&error withInputFromBlock:^(AVAudioPacketCount inNumberOfPackets, AVAudioConverterInputStatus* outStatus) {
        if (inputNum > 0) {
            *outStatus = AVAudioConverterInputStatus_HaveData;
            inputNum--;
        } else {
            *outStatus = AVAudioConverterInputStatus_NoDataNow;
        }
        return self->_compressedBuffer;
    }];

    [_player scheduleBuffer:outBuffer completionHandler:nil];

    _offset = 0;
    _idx = 0;

    [self updateAudioStreamPositionWithTimestamp:timestamp];
    
    if (self.playbackType == kPlaybackTypeAudioOnly) {
        if (!_isAudioPlaybackStarted && self.audioPtsMs - self.audioZeroPtsMs > self.bufferMs) {
            if (_startAudioTime != nil && [_startAudioTime timeIntervalSinceNow] < 5.0) {
                //Start is already queued
                return true;
            }
            _startAudioTime = [NSDate date];
            self.streamZeroPtsMs = self.audioZeroPtsMs;
            dispatch_queue_global_t queue = dispatch_get_global_queue(QOS_CLASS_UTILITY, 0);
            dispatch_async(queue, ^{
                [self playAudio];
            });
            NSLog(@"PLAY AUDIO ONLY");
            [self startStarvationTimer];
            [self.delegate playbackDidStart];
        }
    }
    
    return true;
}

-(void)playAudio {
    if (_engine == nil) {
        NSLog(@"no audio engine");
        return;
    }
    if (self.stopped) {
        NSLog(@"Stop was called");
        return;
    }
    if (_engine.isRunning) {
        @try {
            [_player play];
            _isAudioPlaybackStarted = true;
            NSLog(@"play audio");
        }
        @catch(NSException *exception) {
            NSLog(@"Play audio failed: %@", exception.description);
        }
    } else {
        NSLog(@"try restart audio engine");
        NSError *error;
        AVAudioSession *session = [AVAudioSession sharedInstance];
        BOOL activated = [session setActive:YES error:&error];
        NSLog(@"setActive: %@", [error localizedDescription]);
        if (activated) {
            BOOL status = [_engine startAndReturnError:&error];
            NSLog(@"startAndReturnError: %@", [error localizedDescription]);
            if (status == YES && _engine.isRunning) {
                [_player play];
                _isAudioPlaybackStarted = true;
                NSLog(@"play audio");
            }
        }
    }
}

-(void)verifyStarvation {
    if (self.playbackType != kPlaybackTypeVideoOnly && !_player.isPlaying) {
        // audio-only playback not started yet
        return;
    }
    [super verifyStarvation];
}

-(void)mute:(bool)muted {
    if (_player != nil) {
        if (muted) {
            self.lastVolume = _player.volume;
        }
        [_player setVolume:muted ? 0.0 : self.lastVolume];
    }
    self.muted = muted;
}

-(bool)isMuted {
    if (_player != nil) {
        return _player.volume == 0.0;
    }
    return self.muted;
}

-(void)setVolume:(float)volume  {
    self.lastVolume = volume;
    [_player setVolume:self.lastVolume];
}

-(float)getVolume {
    if (_player != nil) {
        return _player.volume;
    }
    return 0.0;
}

@end
