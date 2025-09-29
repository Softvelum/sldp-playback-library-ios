#import "SldpBaseMediaPlayer.h"
#import "SldpVideoDecoderExternal.h"

#define TICK   startTime = [NSDate date]
#define TOCK   NSLog(@"Video: %f", -[startTime timeIntervalSinceNow])

static const int MAX_SPS_PPS_COUNT = 10;
static const int NAL_LENGTH_PREFIX_SIZE = 4;

@implementation SldpBaseMediaPlayer {
    NSMutableArray<NSNumber*>* _relativeTime;
    NSMutableArray<NSDate*>* _absoluteTime;
    int64_t _adjustTimestamp;
}

@synthesize displayLayer = _displayLayer;

- (id)initWithBuffer:(uint32_t)bufferMs andThreshold:(uint32_t)thresholdMs externalDecoding:(BOOL) externalDecoding {
    self = [super init];
    if (self) {
        _videoZeroPtsMs = -1;
        _audioZeroPtsMs = -1;
        _videoZeroBiasTs = -1;
        _bufferMs = bufferMs;
        _thresholdMs = thresholdMs;
        _playbackType = kPlaybackTypeVideoAudio;
        _lastVolume = 1.0;
        _relativeTime = [[NSMutableArray alloc]init];
        _absoluteTime = [[NSMutableArray alloc]init];
        _adjustTimestamp = -1;
        _steadyMode = false;
        _videoDecoder = externalDecoding ? [[SldpVideoDecoderExternal alloc] init] : [[SldpVideoDecoderBase alloc] init];
        _videoDecoder.delegate = self;
        _videoChatMode = false;
    }
    return self;
}


-(AVSampleBufferDisplayLayer*) displayLayer {
    return _displayLayer;
}

-(void) setDisplayLayer: (AVSampleBufferDisplayLayer*) displayLayer {
    _videoDecoder.displayLayer = displayLayer;
    _displayLayer = displayLayer;
}

- (void)stop: (bool)removeImage {
    _stopped = true;
    [_starvationTimer invalidate];
    [_videoDecoder stop];
    if (removeImage) {
        [_displayLayer flushAndRemoveImage];
    } else {
        [_displayLayer flush];
    }
    
    if (_videoDesc) {
        CFRelease(_videoDesc);
        _videoDesc = NULL;
    }
}

- (bool)setVideoCodecAvcWithTimescale:(int)timescale buffer:(uint8_t *)buffer len:(const uint32_t)len {
    
    _timescaleVideo = timescale;
    
    int params_count = 0;
    const uint8_t* params_ptr[MAX_SPS_PPS_COUNT]  = { };
    size_t         params_size[MAX_SPS_PPS_COUNT] = { };
    
    if(len < 6) {
        NSLog(@"failed to read sps num");
        return false;
    }
    int32_t remain_len = (int32_t)len;
    int nalHeaderLength = NAL_LENGTH_PREFIX_SIZE;
    if (buffer[4] != 0){
        nalHeaderLength = (buffer[4] & 0b11) + 1;
    }
    uint8_t sps_num = buffer[5] & 0x1F;
    buffer += 6; remain_len -= 6;
    
    for(uint8_t i = 0; i < sps_num; ++i) {
        
        if(remain_len < 2) {
            NSLog(@"failed to read sps length");
            return false;
        }
        
        uint32_t sps_len = (buffer[0] << 8) | buffer[1];
        buffer += 2; remain_len -= 2;
        
        if(remain_len < sps_len) {
            NSLog(@"failed to read sps");
            return false;
        }
        
        if(params_count >= MAX_SPS_PPS_COUNT) {
            NSLog(@"too many sps/pps");
            return false;
        }
        
        params_ptr[params_count]  = buffer;
        params_size[params_count] = sps_len;
        params_count++;
        
        buffer += sps_len; remain_len -= sps_len;
    }
    
    if(remain_len < 1) {
        NSLog(@"failed to read pps num");
        return false;
    }
    
    uint8_t pps_num = buffer[0];
    buffer += 1; remain_len -= 1;
    
    for(uint8_t i = 0; i < pps_num; ++i) {
        
        if(remain_len < 2) {
            NSLog(@"failed to read pps length");
            return false;
        }
        
        uint32_t pps_len = (buffer[0] << 8) | buffer[1];
        buffer += 2; remain_len -= 2;
        
        if(remain_len < pps_len) {
            NSLog(@"failed to read pps");
            return false;
        }
        
        if(params_count >= MAX_SPS_PPS_COUNT) {
            NSLog(@"too many sps/pps");
            return false;
        }
        
        params_ptr[params_count]  = buffer;
        params_size[params_count] = pps_len;
        params_count++;
        
        buffer += pps_len; remain_len -= pps_len;
    }
    
    if (_videoDesc) {
        NSLog(@"replace the old video format with the new one");
        CFRelease(_videoDesc);
        _videoDesc = NULL;
    }

    OSStatus status = CMVideoFormatDescriptionCreateFromH264ParameterSets(kCFAllocatorDefault,
                                                                          params_count,
                                                                          params_ptr,
                                                                          params_size,
                                                                          nalHeaderLength,
                                                                          &_videoDesc);
    if(status != noErr) {
        NSLog(@"failed to create avc format descriptor, status=%d", (int)status);
        return false;
    }
    
    CMVideoDimensions dimensions = CMVideoFormatDescriptionGetDimensions(_videoDesc);
    NSLog(@"avc [%dx%d]", dimensions.width, dimensions.height);
    return [_videoDecoder setVideoCodec:_videoDesc];
    
}

-(bool)setVideoCodecHevcWithTimescale:(int)timescale buffer:(uint8_t *)buffer len:(const uint32_t)len {
    
    _timescaleVideo = timescale;
    
    int params_count = 0;
    const uint8_t* params_ptr[MAX_SPS_PPS_COUNT]  = { };
    size_t         params_size[MAX_SPS_PPS_COUNT] = { };
    
    if (len < 22) {
        NSLog(@"failed to read sps num");
        return false;
    }
    // configurationVersion
    if (1 != buffer[0]) {
        NSLog(@"unsupported hevc configurationVersion=%d", buffer[0]);
        return false;
    }
    int32_t remain_len = (int32_t)len;
    uint8_t numOfArrays = buffer[22];
    buffer += 23; remain_len -= 23;
    for (int i = 0; i < numOfArrays; i++) {
        if (len < 1) {
            NSLog(@"failed to read NAL unit array header, i=%d", i);
            return false;
        }
        uint8_t NAL_unit_type = buffer[0] & 0b00111111;
        uint32_t numNalus = ((uint32_t)(buffer[1] << 8)) | buffer[2];
        buffer += 3; remain_len -= 3;
        for (uint32_t j = 0; j < numNalus; j++) {
            size_t nalUnitLength = ((size_t)(buffer[0] << 8)) | (size_t)buffer[1];
            buffer += 2; remain_len -= 2;
            if (remain_len < nalUnitLength) {
                NSLog(@"failed to read NAL unit, NAL_unit_type=%d", NAL_unit_type);
                return false;
            }
            
            if(params_count >= MAX_SPS_PPS_COUNT) {
                NSLog(@"too many sps/pps");
                return false;
            }
            switch (NAL_unit_type) {
                case 32: // vps
                case 33: // sps
                case 34: // pps
                    params_ptr[params_count]  = buffer;
                    params_size[params_count] = nalUnitLength;
                    params_count++;
                    break;
                default:
                    break;
            }
            buffer += nalUnitLength; remain_len -= nalUnitLength;
        }
    }
    
    if (_videoDesc) {
        NSLog(@"replace the old video format with the new one");
        CFRelease(_videoDesc);
        _videoDesc = NULL;
    }
    
    OSStatus status = CMVideoFormatDescriptionCreateFromHEVCParameterSets(kCFAllocatorDefault,
                                                                          params_count,
                                                                          params_ptr,
                                                                          params_size,
                                                                          NAL_LENGTH_PREFIX_SIZE,
                                                                          nil,
                                                                          &_videoDesc);
    if (status != noErr) {
        NSLog(@"failed to create hevc format descriptor, status=%d", (int)status);
        return false;
    }
    
    CMVideoDimensions dimensions = CMVideoFormatDescriptionGetDimensions(_videoDesc);
    NSLog(@"hevc [%dx%d]", dimensions.width, dimensions.height);
    [_videoDecoder setVideoCodec:_videoDesc];

    return true;
}

- (bool)writeVideoFrameWithTimestamp:(uint64_t)timestamp composition_time_offset:(uint32_t)composition_time_offset buffer:(const uint8_t *)buffer len:(int)len key_frame:(bool) key_frame {
    
    //NSLog(@"Player::writeVideoFrameWithTimestamp %llu", timestamp);
    
    CMBlockBufferRef blockBuffer = NULL;
    OSStatus status = CMBlockBufferCreateWithMemoryBlock(NULL,
                                                         (void*)buffer, // memoryBlock to hold buffered data
                                                         len, // block length of the mem block in bytes.
                                                         kCFAllocatorNull,
                                                         NULL,
                                                         0, // offsetToData
                                                         len, // dataLength of relevant bytes, starting at offsetToData
                                                         0,
                                                         &blockBuffer);
    if (status != noErr) {
        NSLog(@"failed to create block buffer, status=%d", (int)status);
        return false;
    }
    
    CMSampleBufferRef sampleBuffer = NULL;
    const size_t sampleSize = len;
    
    [self updateVideoStreamPositionWithTimestamp:timestamp];
    
    if (@available(iOS 13.0, *)) {
        
    } else if (!self.steadyMode){
        timestamp = [self rebaseVideo:timestamp];
    }
    
    uint64_t presentationTimeStamp = timestamp + composition_time_offset;
    CMSampleTimingInfo timingInfo = {
        .duration = kCMTimeIndefinite,
        .presentationTimeStamp = CMTimeMake(presentationTimeStamp, _timescaleVideo),
        .decodeTimeStamp = CMTimeMake(timestamp, _timescaleVideo)
    };
    
    //NSLog(@"timestampIn=%lld, %@", timingInfo.presentationTimeStamp.value, (key_frame == true ? @"KEY_FRAME" : @"FRAME"));
    
    status = CMSampleBufferCreate(kCFAllocatorDefault,
                                  blockBuffer,
                                  true, NULL, NULL,
                                  _videoDesc,
                                  1,
                                  1, &timingInfo,
                                  1, &sampleSize,
                                  &sampleBuffer);
    
    if(status != noErr) {
        NSLog(@"failed to create sample buffer, status=%d", (int)status);
        return false;
    }
    [_videoDecoder decodeVideoSampleBuffer:sampleBuffer];
    
    CFRelease(blockBuffer);
    CFRelease(sampleBuffer);
    return true;
}

-(bool)updateStreamPosition:(CMSampleBufferRef)sampleBuffer {
    if (_displayLayer.status == AVQueuedSampleBufferRenderingStatusFailed) {
        [self printDisplayLayerError];
        [_delegate playbackDidFail];
        return false;
    }
    if (_numVideoFrames == 0) {
        _zeroTime = CMSampleBufferGetPresentationTimeStamp(sampleBuffer);
        _streamZeroPtsMs = _videoZeroPtsMs;
    }
    _numVideoFrames++;
    return true;
}

-(void)onEqueueVideoSampleBuffer:(CMSampleBufferRef)sampleBuffer {
    if ([_delegate respondsToSelector: @selector(videoFrameDecoded:)]) {
        [_delegate videoFrameDecoded:sampleBuffer];
    }
}

-(void)onDecodingFailed {
    [_delegate playbackDidFail];
}


- (void)printAudioStreamBasicDescription:(AudioStreamBasicDescription)asbd {
    char formatID[5];
    UInt32 mFormatID = CFSwapInt32HostToBig(asbd.mFormatID);
    bcopy (&mFormatID, formatID, 4);
    formatID[4] = '\0';
    printf("Sample Rate:         %10.0f\n",  asbd.mSampleRate);
    printf("Format ID:           %10s\n",    formatID);
    printf("Format Flags:        %10X\n",    (unsigned int)asbd.mFormatFlags);
    printf("Bytes per Packet:    %10d\n",    (unsigned int)asbd.mBytesPerPacket);
    printf("Frames per Packet:   %10d\n",    (unsigned int)asbd.mFramesPerPacket);
    printf("Bytes per Frame:     %10d\n",    (unsigned int)asbd.mBytesPerFrame);
    printf("Channels per Frame:  %10d\n",    (unsigned int)asbd.mChannelsPerFrame);
    printf("Bits per Channel:    %10d\n",    (unsigned int)asbd.mBitsPerChannel);
    printf("\n");
}

-(bool)setAudioCodecAacWithTimescale:(int)timescale buffer:(const uint8_t*)buffer len:(size_t)len {
    // https://wiki.multimedia.cx/index.php/Understanding_AAC
    
    const NSDictionary* objects = @{
                                    @(1): @(kMPEG4Object_AAC_Main),
                                    @(2): @(kMPEG4Object_AAC_LC),
                                    @(3): @(kMPEG4Object_AAC_SSR),
                                    @(4): @(kMPEG4Object_AAC_LTP),
                                    @(5): @(kMPEG4Object_AAC_SBR),
                                    @(6): @(kMPEG4Object_AAC_Scalable)
                                    };
    
    const NSDictionary* frequencies = @{
                                        @(0): @(96000),
                                        @(1): @(88200),
                                        @(2): @(64000),
                                        @(3): @(48000),
                                        @(4): @(44100),
                                        @(5): @(32000),
                                        @(6): @(24000),
                                        @(7): @(22050),
                                        @(8): @(16000),
                                        @(9): @(12000),
                                        @(10): @(11025),
                                        @(11): @(8000),
                                        @(12): @(7350)
                                        };
    
    AudioStreamBasicDescription audioFormat = { };
    audioFormat.mFormatID = kAudioFormatMPEG4AAC;
    
    if (len < 2) {
        NSLog(@"can't parse aac header, length=%zu", len);
        return false;
    }
    
    // 5 bit: object type
    uint8_t object_type = (buffer[0] & 0xF8) >> 3;
    if(nil == objects[@(object_type)]) {
        NSLog(@"unsupported object_type=%d", object_type);
        return false;
    }
    NSLog(@"object_type=%d", object_type);
    audioFormat.mFormatFlags = (AudioFormatFlags)[objects[@(object_type)] integerValue];
    
    // 4 bit: frequency index
    uint8_t frequency_index = ((buffer[0] & 0x7) << 1) | ((buffer[1] & 0x80) >> 7);
    if(nil == frequencies[@(frequency_index)]) {
        NSLog(@"unsupported frequency_index=%d", frequency_index);
        return false;
    }
    NSLog(@"frequency_index=%d", frequency_index);
    audioFormat.mSampleRate = (Float64)[frequencies[@(frequency_index)] integerValue];
    
    // 4 bit: channel configuration
    uint8_t channel_configuration = (buffer[1] & 0x78) >> 3;
    if(channel_configuration > 8) {
        NSLog(@"unsupported channel_configuration=%d", channel_configuration);
        return false;
    } else if (channel_configuration == 0) {
        //TODO: Read and setup advanced channel configuration from PCE
        channel_configuration = 2   ;

    }
    NSLog(@"channel_configuration=%d", channel_configuration);
    audioFormat.mChannelsPerFrame = channel_configuration;
    
    // 1 bit: frame length flag
    if(buffer[1] & 0x04) {
        audioFormat.mFramesPerPacket = 960;
    } else {
        audioFormat.mFramesPerPacket = 1024;
    }
    
    return [self startAudioDecodeWithTimescale:timescale format:audioFormat packetCapacity:4];
}

-(bool)setAudioCodecMp3WithTimescale:(int)timescale buffer:(const uint8_t*)buffer len:(size_t)len {
    
    if (len < 4) {
        NSLog(@"can't parse mp3 header, length=%zu", len);
        return false;
    }
    
    NSMutableArray *sampleRates = [[NSMutableArray alloc] initWithCapacity: 4];
    [sampleRates insertObject:[NSMutableArray arrayWithObjects:@"11025",@"12000",@"8000",nil] atIndex:0]; //mpeg 2.5
    [sampleRates insertObject:[NSMutableArray arrayWithObjects:@"0",@"0",@"0",nil] atIndex:1];
    [sampleRates insertObject:[NSMutableArray arrayWithObjects:@"22050",@"24000",@"16000",nil] atIndex:2]; //mpeg 2
    [sampleRates insertObject:[NSMutableArray arrayWithObjects:@"44100",@"48000",@"32000",nil] atIndex:3]; //mpeg 1
    
    if ((buffer[0] & 255) == 255 && (buffer[1] & 224) == 224) {
        // AAAAAAAA   AAABBCCD   EEEEFFGH   IIJJKLMM
        uint8_t version = (buffer[1] & 24) >> 3; //get BB (0 -> 3)
        uint8_t layer = abs(((buffer[1] & 6) >> 1) - 4); //get CC (1 -> 3), then invert
        uint8_t srIndex = (buffer[2] & 12) >> 2; //get FF (0 -> 3)
        uint8_t channels  = (buffer[3] & 192) >> 6; //get II (0 -> 3)
        if ((version != 1 && version < 4) && srIndex < 3) {
            AudioStreamBasicDescription audioFormat = { };
            audioFormat.mFormatID = kAudioFormatMPEGLayer3;
            audioFormat.mFramesPerPacket = 1152;
            audioFormat.mSampleRate = [[[sampleRates objectAtIndex:version] objectAtIndex:srIndex] floatValue];
            audioFormat.mChannelsPerFrame = (channels == 3) ? 1 : 2; // 11 - Single channel (Mono)
            return [self startAudioDecodeWithTimescale:timescale format:audioFormat packetCapacity:1];
        } else {
            NSLog(@"unsupported mp3 header version=%d, layer=%d, srIndex=%d", version, layer, srIndex);
            return false;
        }
    } else {
        NSLog(@"can't parse mp3 header");
        return false;
    }
}

-(bool)setAudioCodecOpusWithTimescale:(int)timescale buffer:(const uint8_t*)buffer len:(size_t)len {
    AudioStreamBasicDescription audioFormat = { };
    audioFormat.mFormatID = kAudioFormatOpus;
    audioFormat.mFramesPerPacket = 48000 / 50; //20 ms packet
    audioFormat.mSampleRate = 48000;
    audioFormat.mChannelsPerFrame = 2;
    return [self startAudioDecodeWithTimescale:timescale format:audioFormat packetCapacity:1];

}

-(bool)setAudioCodecAc3WithTimescale:(int)timescale sample_rate: (const int) ac3_sample_rate
                            channels: (const uint8_t) ac3_channel_count layout: (AudioChannelLayoutTag) layout {
    AudioStreamBasicDescription audioFormat = {
        .mFormatID = kAudioFormatAC3,
        .mSampleRate = (double)ac3_sample_rate,
        .mChannelsPerFrame = ac3_channel_count,
        .mFramesPerPacket = 1536
    };
    return [self startAudioDecodeWithTimescale:timescale format:audioFormat channelLayout:layout packetCapacity:1];
}

-(bool)setAudioCodecEac3WithTimescale:(int)timescale sample_rate: (const int) ac3_sample_rate
                             channels: (const uint8_t) ac3_channel_count layout: (AudioChannelLayoutTag) layout {
    AudioStreamBasicDescription audioFormat = {
        .mFormatID = kAudioFormatEnhancedAC3,
        .mSampleRate = (double)ac3_sample_rate,
        .mChannelsPerFrame = ac3_channel_count,
        .mFramesPerPacket = 1536
    };
    return [self startAudioDecodeWithTimescale:timescale format:audioFormat channelLayout:layout packetCapacity:1];
}

-(uint64_t)rebaseVideo:(uint64_t)timestamp {
    if (_videoZeroBiasTs == -1) {
        _videoZeroBiasTs = timestamp;
    }
    uint64_t rebased_timestamp = 0;
    if (timestamp > _videoZeroBiasTs) {
        rebased_timestamp = timestamp - _videoZeroBiasTs;
    }
    return rebased_timestamp;
}

-(void)updateVideoStreamPositionWithTimestamp:(uint64_t)timestamp {
    if (_timescaleVideo > 0) {
        if (_timescaleVideo == 1000) {
            _videoPtsMs = timestamp;
        } else if (_timescaleVideo == 1000000) {
            _videoPtsMs = timestamp/1000;
        } else {
            _videoPtsMs = (uint64_t)((timestamp / (double)_timescaleVideo) * 1000);
        }
        if (_videoZeroPtsMs == -1) {
            _videoZeroPtsMs = _videoPtsMs;
        }
    }
}

-(void)updateAudioStreamPositionWithTimestamp:(uint64_t)timestamp {
    if (_timescaleAudio > 0) {
        if (_timescaleAudio == 1000) {
            _audioPtsMs = timestamp;
        } else if (_timescaleAudio == 1000000) {
            _audioPtsMs = timestamp/1000;
        } else {
            _audioPtsMs = (uint64_t)((timestamp / (double)_timescaleAudio) * 1000);
        }
        if (_audioZeroPtsMs == -1) {
            _audioZeroPtsMs = _audioPtsMs;
        }
    }
}

-(uint64_t)getMsFromTimestamp:(uint64_t)timestamp withTimescale:(int)timescale {
    if (timescale == 0) {
        return 0;
    }
    if (timescale == 1000) {
        return timestamp;
    }
    if (timescale == 1000000) {
        return timestamp/1000;
    }
    return (uint64_t)((timestamp / (double)timescale) * 1000);
}

-(void)startStarvationTimer {
    dispatch_async(dispatch_get_main_queue(), ^{
        self.starvationTimer = [NSTimer scheduledTimerWithTimeInterval:0.3f target:self selector:@selector(verifyStarvation) userInfo:nil repeats:YES];
    });
    self.renderStartRealTime = [NSDate date];
}

-(void)verifyStarvation {
    NSTimeInterval executionTime = [[NSDate date] timeIntervalSinceDate:_renderStartRealTime];
    uint64_t executionTimeMs = (uint64_t)(executionTime * 1000.0);
    
    uint64_t videoReadFromStreamMs = 0;
    uint64_t audioReadFromStreamMs = 0;
    
    if (_videoPtsMs > _streamZeroPtsMs) {
        videoReadFromStreamMs = _videoPtsMs - _streamZeroPtsMs;
    }
    
    if (_audioPtsMs > _streamZeroPtsMs) {
        audioReadFromStreamMs = _audioPtsMs - _streamZeroPtsMs;
    }
    int starvationEndThreshold = _thresholdMs * 8 / 10;
    
    //NSLog(@"real time=%llu ms.", executionTimeMs);
    
    if (_playbackType == kPlaybackTypeAudioOnly) {
        //NSLog(@"read from stream audio=%llums", audioReadFromStreamMs);
        _audioLevelMs = (int)(audioReadFromStreamMs - executionTimeMs);
        //NSLog(@"has audio %dms", _audioLevelMs);

        if (executionTimeMs > audioReadFromStreamMs + _thresholdMs) {
            NSLog(@"no audio data %dms", _audioLevelMs);
            [self notifyStarvation];
        } else if (_isStarvation && executionTimeMs < audioReadFromStreamMs + starvationEndThreshold) {
            [self notifyStarvationEnd];
        }
    } else if (_playbackType == kPlaybackTypeVideoOnly) {
        //NSLog(@"read from stream video=%llums", videoReadFromStreamMs);
        _videoLevelMs = (int)(videoReadFromStreamMs - executionTimeMs);
        //NSLog(@"has video %dms", _videoLevelMs);

        if (executionTimeMs > videoReadFromStreamMs + _thresholdMs) {
            NSLog(@"no video data %dms", _videoLevelMs);
            [self notifyStarvation];
        } else if (_isStarvation && executionTimeMs < videoReadFromStreamMs + starvationEndThreshold) {
            [self notifyStarvationEnd];
        }
    } else {
        //NSLog(@"read from stream audio=%llums", audioReadFromStreamMs);
        //NSLog(@"read from stream video=%llums", videoReadFromStreamMs);
        _audioLevelMs = (int)(audioReadFromStreamMs - executionTimeMs);
        _videoLevelMs = (int)(videoReadFromStreamMs - executionTimeMs);
        //NSLog(@"has audio %dms", _audioLevelMs);
        //NSLog(@"has video %dms", _videoLevelMs);

        if (executionTimeMs > audioReadFromStreamMs + _thresholdMs) {
            NSLog(@"no audio data %dms", _audioLevelMs);
            [self notifyStarvation];
        } else if (executionTimeMs > videoReadFromStreamMs + _thresholdMs) {
            NSLog(@"no video data %dms", _videoLevelMs);
            [self notifyStarvation];
        } else if (_isStarvation && executionTimeMs < audioReadFromStreamMs + _thresholdMs && executionTimeMs < videoReadFromStreamMs + starvationEndThreshold) {
            [self notifyStarvationEnd];
        }
        [_delegate videoBufferLevelDidChangeSeconds:_videoLevelMs / 1000.0 Frames:0 PlaybackRate:_rate];
    }
}

-(void)notifyStarvation {
    if (!_isStarvation) {
        _isStarvation = true;
        [_delegate starvationStateChanged: true];
    }
}

-(void)notifyStarvationEnd {
    if (_isStarvation) {
        _isStarvation = false;
        [_delegate starvationStateChanged: false];
    }
}


-(void)mute:(bool)muted {
    [NSException raise:NSInternalInconsistencyException
                format:@"You must override %@ in a subclass", NSStringFromSelector(_cmd)];
}

-(bool)isMuted {
    @throw [NSException exceptionWithName:NSInternalInconsistencyException
                                   reason:[NSString stringWithFormat:@"You must override %@ in a subclass", NSStringFromSelector(_cmd)]
                                 userInfo:nil];
}

-(void)setVolume:(float)volume {
    [NSException raise:NSInternalInconsistencyException
                format:@"You must override %@ in a subclass", NSStringFromSelector(_cmd)];
}

-(float)getVolume {
    @throw [NSException exceptionWithName:NSInternalInconsistencyException
                                   reason:[NSString stringWithFormat:@"You must override %@ in a subclass", NSStringFromSelector(_cmd)]
                                 userInfo:nil];
}

-(bool)writeAudioFrameWithTimestamp:(uint64_t)timestamp
                         numSamples:(uint32_t)numSamples
                             buffer:(const uint8_t *)buffer len:(int)len {
    @throw [NSException exceptionWithName:NSInternalInconsistencyException
                                   reason:[NSString stringWithFormat:@"You must override %@ in a subclass", NSStringFromSelector(_cmd)]
                                 userInfo:nil];
}

-(bool)startAudioDecodeWithTimescale:(int)timescale
                              format:(AudioStreamBasicDescription)audioFormat
                      packetCapacity:(AVAudioFrameCount)packetCapacity {
    return [self startAudioDecodeWithTimescale:timescale format:audioFormat
                                 channelLayout:kAudioChannelLayoutTag_Unknown
                                packetCapacity:packetCapacity];
}

-(bool)startAudioDecodeWithTimescale:(int)timescale
                              format:(AudioStreamBasicDescription)audioFormat channelLayout:(AudioChannelLayoutTag) channelLayout
                      packetCapacity:(AVAudioFrameCount)packetCapacity {
    @throw [NSException exceptionWithName:NSInternalInconsistencyException
                                   reason:[NSString stringWithFormat:@"You must override %@ in a subclass", NSStringFromSelector(_cmd)]
                                 userInfo:nil];
}

-(void)printDisplayLayerError {
    if (_displayLayer != nil && _displayLayer.error != nil) {
        [self printError:_displayLayer.error];
    }
}

-(void)printError:(NSError*)error {
    NSLog(@"%@", error.localizedDescription);
    NSLog(@"%@", error.localizedFailureReason);
    NSLog(@"%@", error.localizedRecoveryOptions);
    NSLog(@"%@", error.localizedRecoverySuggestion);
}

-(void)mapAbsoluteTime: (NSDate*) time{

    double relTs = 0.0;
    if (_playbackType == kPlaybackTypeAudioOnly) {
        relTs = (_audioPtsMs - _audioZeroPtsMs)/1000.0;
    } else {
        relTs = (_videoPtsMs - _videoZeroPtsMs)/1000.0;
    }

//    NSLog(@"RelTs: %6.3f LastTs: %6.3f", relTs, _lastSteadyTs);
    double lastSteadyTs = _relativeTime.lastObject.doubleValue;
    if (_relativeTime.count > 0 && relTs - lastSteadyTs < 1.0) {
        return;
    }

//    NSDate* now = [[NSDate alloc]init];
//    NSDateFormatter *dateFormatter = [[NSDateFormatter alloc] init];
//    dateFormatter.locale = [[NSLocale alloc] initWithLocaleIdentifier:@"en_US"];
//    [dateFormatter setLocalizedDateFormatFromTemplate:@"yyyy-MM-dd'T'HH:mm:ss.SSS"];
//    NSLog(@"mapAbsoluteTime %@ (%6.3f) to %6.3f", [dateFormatter stringFromDate:time], [now timeIntervalSinceDate:time], relTs);
    
    NSNumber* ts = [NSNumber numberWithDouble:relTs];
    [_relativeTime addObject:ts];
    [_absoluteTime addObject:time];
}

-(double)getDeviationForPlayTime: (double) playtime {
    NSDate* now = [[NSDate alloc]init];
    __block NSUInteger i = NSNotFound;
    
    //Find last item prior to play time
    [_relativeTime enumerateObjectsUsingBlock:^(NSNumber * _Nonnull obj, NSUInteger idx, BOOL * _Nonnull stop) {
        double val = obj.doubleValue;
        if (val <= playtime) {
            i = idx;
        } else {
            *stop = true;
        }
    }];
    if (i == NSNotFound) {
        return 0.0;
    }
    NSNumber* pos = _relativeTime[i];
    NSDate* steady = _absoluteTime[i];
    if (i> 0) {
        NSRange r = NSMakeRange(0,i);
        [_relativeTime removeObjectsInRange:r];
        [_absoluteTime removeObjectsInRange:r];
    }
    NSTimeInterval elapsed = [now timeIntervalSinceDate:steady] + pos.doubleValue;
//    NSLog(@"map time: %6.3f elapsed %6.3f playtime %6.3f delta %6.3f", pos.doubleValue, [now timeIntervalSinceDate:steady], playtime, playtime - elapsed);
    return playtime - elapsed;
}

-(void)resetStreadyTime {
    [_relativeTime removeAllObjects];
    [_absoluteTime removeAllObjects];
}

@end
