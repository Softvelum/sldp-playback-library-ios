#import "SldpStreamer.h"
#import "SldpBufferItem.h"
#import "SldpConnection.h"
#import "SldpMediaPlayer.h"
#import "SldpMediaPlayerV11.h"

@interface SldpStreamer() {
    int _lastConnectionID;
    NSMutableDictionary* _connectionMap;
    SldpBaseMediaPlayer* _player;
    
    int _connectionId;
    
    int _videoStreamId;
    int _audioStreamId;
    
    bool _videoInit;
    bool _audioInit;
    
    AbrState _abrState;
    int _nextVideoStreamId;
    uint64_t _nextStartPts;
    NSMutableArray* _frameQueue;
    
    int _nextAudioStreamId;
    
    dispatch_queue_t _queue;

    CMVideoDimensions _initialResolution;

    bool _muted;
    AudioCodecType _audioCodec;
}
@end

@implementation SldpStreamer

-(id)init {
    self = [super init];
    if (self) {
        _lastConnectionID = 0;
        _connectionMap = [[NSMutableDictionary alloc] init];
        
        _connectionId = -1;
        _videoStreamId = -1;
        _audioStreamId = -1;
        
        _videoInit = false;
        _audioInit = false;
        
        _abrState = kAbrStateStop; // switch 2nd video stream to test play & cancel
        _nextVideoStreamId = -1;
        _nextStartPts = -1;
        _frameQueue = [[NSMutableArray alloc] init];
        
        _queue = dispatch_queue_create("com.wmspanel.libsldp.abr", DISPATCH_QUEUE_SERIAL);
        
        _nextAudioStreamId = -1;
    }
    return self;
}

-(SldpBaseMediaPlayer*)createPlayerWithBufferMs:(int)buffer_ms thresholdMs:(int)threshold_ms
                               disableMediaSync:(BOOL) disableMediaSync
                               externalDecoding:(BOOL) externalDecoding
{
    bool external = [self isSimulator] || externalDecoding;
    if (!disableMediaSync) {
        return [[SldpMediaPlayerV11 alloc] initWithBuffer:buffer_ms andThreshold:threshold_ms externalDecoding: external];
    }
    return [[SldpMediaPlayer alloc] initWithBuffer:buffer_ms andThreshold:threshold_ms externalDecoding: external];
}

// connection
-(int)createConnectionWithConfig:(StreamConfig *)config displayLayer:(AVSampleBufferDisplayLayer*)displayLayer connectionListener:(id<SldpConnectionListener>)connectionListener {
    
    NSURL* uri = config.uri;
    int32_t buffer_ms = config.buffering;
    int32_t threshold = config.threshold;
    int32_t offset = config.offset;
    SldpStreamMode mode = config.mode;
    int32_t bitrate = config.preferredBitrate;
    int32_t delay = 0;
    NSLog(@"Streamer::createConnectionWithListener");
    
    delay = config.steady ? config.buffering : 0;
    if (_connectionMap.count > 0) {
        NSLog(@"Multiple connections are not supported");
        return -1;
    }
    _initialResolution = config.initialResolution;

    _player = [self createPlayerWithBufferMs:buffer_ms
                                 thresholdMs:threshold
                            disableMediaSync:config.disableMediaSync
                            externalDecoding:config.externalDecoding];
    
    [_player setDelegate:self];
    [_player setDisplayLayer:displayLayer];
    [_player setMuted:_muted];
    [_player setVideoChatMode: config.videoChatMode];
    
    BaseConnection* connection;
    if ([uri.scheme caseInsensitiveCompare:@"ws"] == NSOrderedSame ||
        [uri.scheme caseInsensitiveCompare:@"sldp"] == NSOrderedSame) {
        
        connection = [[SldpConnection alloc] initWithConnectionId:++_lastConnectionID
                                                              uri:uri
                                                           offset:offset
                                                           useSSL:false
                                                             mode:mode
                                                          bitrate:bitrate delay: delay
                                               connectionListener:connectionListener streamListener:self];
        
    } else if ([uri.scheme caseInsensitiveCompare:@"wss"] == NSOrderedSame ||
               [uri.scheme caseInsensitiveCompare:@"sldps"] == NSOrderedSame) {
        
        connection = [[SldpConnection alloc] initWithConnectionId:++_lastConnectionID
                                                              uri:uri
                                                           offset:offset
                                                           useSSL:true
                                                             mode:mode
                                                          bitrate:bitrate
                                                            delay: delay
                                               connectionListener:connectionListener streamListener:self];

    } else
    {
        return -1;
    }
    
    if (nil == connection) {
        return -1;
    }
    
    [_connectionMap setObject:connection forKey: @(_lastConnectionID)];
    
    return _lastConnectionID;
}

-(void)releaseConnectionId:(int)connectionID clearImage: (bool) clearImage {
    NSLog(@"Streamer::releaseConnectionId: %d", connectionID);
    BaseConnection* connection = [_connectionMap objectForKey: @(connectionID)];
    [connection Close];
    [_connectionMap removeObjectForKey: @(connectionID)];
    [_player stop: clearImage];
    [self reset];
}

-(void)reset {
    _connectionId = -1;
    _videoStreamId = -1;
    _audioStreamId = -1;
    
    _videoInit = false;
    _audioInit = false;
    
    _abrState = kAbrStateStop; // switch 2nd video stream to test play & cancel
    _nextVideoStreamId = -1;
    _nextStartPts = -1;
    
    [_frameQueue removeAllObjects];
}

-(void)streamInfoDidRecvId:(int)connectionId {
    NSLog(@"streamInfoDidRecvId");
    _connectionId = connectionId;
    
    BaseConnection* connection = [_connectionMap objectForKey:@(connectionId)];
    [connection notifyOnStateChange:kSldpConnectionStateSetup Status:kSldpConnectionStatusSuccess];

    NSDictionary* streams = [connection getStreams];
    
    SldpStreamMode mode = connection.mode;

    if ([connection isKindOfClass:[SldpConnection class]]) {
        NSMutableArray<SldpPlayRequest*>* streams_to_play = [[NSMutableArray alloc] init];
        bool first_audio = true; // TODO: select by language id
        bool add_video = true;

        if (mode != kSldpStreamModeVideoOnly) {
            int32_t bitrate = [(SldpConnection*)connection bitrate];
            bool isRadio = true;
            for (StreamInfoInternal* stream in streams.allValues) {
                if (stream.type == kStreamTypeInternalVideo) {
                    isRadio = false;
                    break;
                }
            }
            if (isRadio && bitrate > 0) {
                long audioId = [connection getAudioStreamIdWithBitrate:bitrate];                
                if (audioId != -1) {
                    SldpPlayRequest* req = [[SldpPlayRequest alloc] initWithStreamId:(int)audioId];
                    req.offset = [(SldpConnection*)connection offset];
                    [streams_to_play addObject:req];
                    first_audio = false;
                }
            }
            _player.steadyMode = ((SldpConnection*)connection).steadyEnabled;
        }

        for (StreamInfoInternal* stream in streams.allValues) {
            if (stream.type == kStreamTypeInternalVideo && mode != kSldpStreamModeAudioOnly) {
                // Get resolution less or equal to requested or lowest one
                if (add_video) {
                    long videoId = -1;
                    if (_initialResolution.width > 0 && _initialResolution.height > 0) {
                        videoId = [connection getMatchVideoId: _initialResolution];
                    }
                    if (videoId < 0) {
                        videoId = [connection getLowestVideoId];
                    }
                    SldpPlayRequest* req = [[SldpPlayRequest alloc] initWithStreamId:(int)videoId];
                    req.offset = [(SldpConnection*)connection offset];
                    [streams_to_play addObject:req];
                    add_video = false;
                }

            } else if (stream.type == kStreamTypeInternalAudio && mode != kSldpStreamModeVideoOnly) {
                if (first_audio) {
                    SldpPlayRequest* req = [[SldpPlayRequest alloc] initWithStreamId:(int)stream.streamId];
                    req.offset = [(SldpConnection*)connection offset];
                    [streams_to_play addObject:req];
                    first_audio = false;
                }
            }
        }
        
        if (streams_to_play.count > 0) {
            [connection sendPlayWithStreams:streams_to_play];
        }
    }
    
    bool hasVideo = false;
    bool hasAudio = false;
    
    for(StreamInfoInternal* stream in streams.allValues) {
        if(stream.state == kStreamStateInternalPlay) {
            if(stream.type == kStreamTypeInternalVideo) {
                NSLog(@"play video %d %d %dx%d", connectionId, stream.streamId, stream.width, stream.height);
                _videoStreamId = stream.streamId;
                hasVideo = true;
            } else if (stream.type == kStreamTypeInternalAudio) {
                NSLog(@"play audio %d %d", connectionId, stream.streamId);
                _audioStreamId = stream.streamId;
                hasAudio = true;
            }
        }
    }
    
    if (hasVideo && hasAudio && mode == kSldpStreamModeVideoAudio) {
        _player.playbackType = kPlaybackTypeVideoAudio;
        NSLog(@"kPlaybackTypeVideoAudio");
    } else if (hasVideo && mode != kSldpStreamModeAudioOnly) {
        _player.playbackType = kPlaybackTypeVideoOnly;
        NSLog(@"kPlaybackTypeVideoOnly");
    } else if (hasAudio && mode != kSldpStreamModeVideoOnly) {
        _player.playbackType = kPlaybackTypeAudioOnly;
        NSLog(@"kPlaybackTypeAudioOnly");
    }  else {
        NSLog(@"no stream to start playback");
    }
}

-(bool)setVideoCodecWithStreamInfo:(StreamInfoInternal*)streamInfo {
    bool status = false;
    if (streamInfo.videoCodec == kVideoCodecTypeAvc) {
        status = [self setVideoCodecAvcWithTimescale:streamInfo.timescale
                                              buffer:(uint8_t*)streamInfo.extradata.bytes
                                                 len:(const uint32_t)streamInfo.extradata.length];
    } else if (streamInfo.videoCodec == kVideoCodecTypeHevc) {
        status = [self setVideoCodecHevcWithTimescale:streamInfo.timescale
                                               buffer:(uint8_t*)streamInfo.extradata.bytes
                                                  len:(const uint32_t)streamInfo.extradata.length];
         if (@available(iOS 11.0, *)) {
             // TODO: report fail
         }
    }
    return status;
}

-(bool)setVideoCodecAvcWithTimescale:(int)timescale buffer:(uint8_t *)buffer len:(const uint32_t)len {
    if ([_frameListener respondsToSelector:@selector(avcHeaderDidArrived:timescale:buffer:len:)]) {
        [_frameListener avcHeaderDidArrived:_connectionId timescale:timescale buffer:buffer len:len];
    }
    return [_player setVideoCodecAvcWithTimescale:timescale buffer:buffer len:len];
}

-(bool)setVideoCodecHevcWithTimescale:(int)timescale buffer:(uint8_t *)buffer len:(const uint32_t)len {
    if ([_frameListener respondsToSelector:@selector(hevcHeaderDidArrived:timescale:buffer:len:)]) {
        [_frameListener hevcHeaderDidArrived:_connectionId timescale:timescale buffer:buffer len:len];
    }
    return [_player setVideoCodecHevcWithTimescale:timescale buffer:buffer len:len];
}

-(bool)writeVideoFrameWithTimestamp:(uint64_t)timestamp composition_time_offset:(uint32_t)composition_time_offset buffer:(const uint8_t *)buffer len:(int)len key_frame:(bool)key_frame {
    if ([_frameListener respondsToSelector:@selector(videoFrameDidArrived:timestamp:composition_time_offset:buffer:len:key_frame:)]) {
        [_frameListener videoFrameDidArrived:_connectionId timestamp:timestamp composition_time_offset:composition_time_offset buffer:buffer len:len key_frame:key_frame];
    }
    return [_player writeVideoFrameWithTimestamp:timestamp composition_time_offset:composition_time_offset buffer:buffer len:len key_frame:key_frame];
}

-(bool)setAudioCodecAacWithTimescale:(int)timescale buffer:(uint8_t *)buffer len:(size_t)len {
    if ([_frameListener respondsToSelector:@selector(aacHeaderDidArrived:timescale:buffer:len:)]) {
        [_frameListener aacHeaderDidArrived:_connectionId timescale:timescale buffer:buffer len:len];
    }
    _audioCodec = kAudioCodecTypeAac;
    return [_player setAudioCodecAacWithTimescale:timescale buffer:buffer len:len];
}

-(bool)setAudioCodecMp3WithTimescale:(int)timescale buffer:(const uint8_t *)buffer len:(size_t)len {
    _audioCodec = kAudioCodecTypeMp3;
    if ([_frameListener respondsToSelector:@selector(mp3HeaderDidArrived:timescale:buffer:len:)]) {
        [_frameListener mp3HeaderDidArrived:_connectionId timescale:timescale buffer:buffer len:len];
    }
    return [_player setAudioCodecMp3WithTimescale:timescale buffer:buffer len:len];
}

-(bool)setAudioCodecOpusWithTimescale:(int)timescale buffer:(const uint8_t *)buffer len:(size_t)len {
    _audioCodec = kAudioCodecTypeOpus;
    return [_player setAudioCodecOpusWithTimescale:timescale buffer:buffer len:len];
}

-(bool)writeAudioFrameWithTimestamp:(uint64_t)timestamp numSamples:(uint32_t)numSamples buffer:(const uint8_t *)buffer len:(int)len {
    if ([_frameListener respondsToSelector:@selector(audioFrameDidArrived:timestamp:buffer:len:)]) {
        [_frameListener audioFrameDidArrived:_connectionId timestamp:timestamp buffer:buffer len:len];
    }
    return [_player writeAudioFrameWithTimestamp:timestamp numSamples: numSamples buffer:buffer len:len];
}

-(void)writeVideoFrameWithStreamInfo:(StreamInfoInternal*)streamInfo
                           timestamp:(uint64_t)timestamp composition_time_offset:(uint32_t)composition_time_offset
                              buffer:(const uint8_t *)buffer len:(int)len key_frame:(bool) key_frame {
    
    //NSLog(@"Streamer::writeVideoFrameWithStreamInfo %d %d", streamInfo.connectionId, streamInfo.streamId);
    if (_player.playbackType == kPlaybackTypeAudioOnly) {
        return;
    }
    
    if (streamInfo.connectionId == _connectionId && streamInfo.streamId == _videoStreamId) {
        
        if (!_videoInit) {
            if(!key_frame) {
                // skip until a first keyframe
                NSLog(@"skip until a first keyframe");
                return;
            }
            _videoInit = true;
            dispatch_sync(_queue, ^{
                _abrState = kAbrStatePlay;
            });
            NSLog(@"video init");
            
            [self setVideoCodecWithStreamInfo:streamInfo];
        }
        
        if (_abrState == kAbrStateWait && timestamp + composition_time_offset >= _nextStartPts) {
            //NSLog(@"can switch now %llu -> %llu", timestamp + composition_time_offset, _nextStartPts);
            dispatch_sync(_queue, ^{
                _abrState = kAbrStateShouldSwitch;
                [self cancelStreamId:_videoStreamId];
            });
        }
        
        if (_abrState != kAbrStateShouldSwitch) {
            [self writeVideoFrameWithTimestamp:timestamp composition_time_offset:composition_time_offset buffer:buffer len:len key_frame:key_frame];
            //NSLog(@"video %d %d %lld %d %d", streamInfo.connectionId, streamInfo.streamId, timestamp, len, key_frame);
        }
        
    } else if (streamInfo.connectionId == _connectionId && streamInfo.streamId == _nextVideoStreamId) {
        
        if (_abrState == kAbrStateWait) {
            if (_nextStartPts == -1 && key_frame) {
                _nextStartPts = timestamp + composition_time_offset;
                NSLog(@"next key_frame %llu", timestamp + composition_time_offset);
            }
            //NSLog(@"new ts, %llu", timestamp);
            if (_nextStartPts != -1) {
                SldpBufferItem* frame = [[SldpBufferItem alloc] initWithBuffer:buffer timestamp:timestamp composition_time_offset:composition_time_offset len:len key_frame:key_frame];
                [_frameQueue addObject:frame];
            }
            
        } else if (_abrState == kAbrStateShouldSwitch) {
            [self setVideoCodecWithStreamInfo:streamInfo];
            [_player resetStreadyTime];
            while (_frameQueue.count > 0) {
                SldpBufferItem* frame = [_frameQueue objectAtIndex:0];
                [self writeVideoFrameWithTimestamp:frame.timestamp composition_time_offset:frame.composition_time_offset buffer:frame.buffer len:frame.len key_frame:frame.key_frame];
                //NSLog(@"queue video %d %d %lld %d %d", streamInfo.connectionId, streamInfo.streamId, frame.timestamp, frame.len, frame.key_frame);
                [_frameQueue removeObjectAtIndex:0];
            }
            
            [self writeVideoFrameWithTimestamp:timestamp composition_time_offset:composition_time_offset buffer:buffer len:len key_frame:key_frame];
            //NSLog(@"next video %d %d %lld %d %d", streamInfo.connectionId, streamInfo.streamId, timestamp, len, key_frame);
            
            dispatch_sync(_queue, ^{
                _abrState = kAbrStatePlay;
                _videoStreamId = _nextVideoStreamId;
                _nextVideoStreamId = -1;
                _nextStartPts = -1;
            });

        }
    }
}

-(void)writeAudioFrameWithStreamInfo:(StreamInfoInternal*)streamInfo
                           timestamp:(uint64_t)timestamp
                          numSamples:(uint32_t)numSamples
                              buffer:(const uint8_t *)buffer len:(int)len {
    
    //NSLog(@"Streamer::writeAudioFrameWithStreamInfo %d %d", streamInfo.connectionId, streamInfo.streamId);
    if (_player.playbackType == kPlaybackTypeVideoOnly) {
        return;
    }
    
    if(streamInfo.connectionId == _connectionId && streamInfo.streamId == _audioStreamId) {
        
        if(!_audioInit) {
            _audioInit = true;
            NSLog(@"audio init");
            switch (streamInfo.audioCodec) {
                case kAudioCodecTypeAac:
                    [self setAudioCodecAacWithTimescale:streamInfo.timescale buffer:(uint8_t*)streamInfo.extradata.bytes len:(uint32_t)streamInfo.extradata.length];
                    break;
                case kAudioCodecTypeMp3:
                    [self setAudioCodecMp3WithTimescale:streamInfo.timescale buffer:buffer len:len];
                    break;
                case kAudioCodecTypeOpus:
                    [self setAudioCodecOpusWithTimescale:streamInfo.timescale buffer:buffer len:len];
                    break;
                case kAudioCodecTypeAc3:
                    break;
                case kAudioCodecTypeEac3:
                    break;

            }
        }
        
        if (_player.playbackType == kPlaybackTypeAudioOnly) {
            [self writeAudioFrameWithTimestamp:timestamp numSamples: numSamples buffer:buffer len:len];
            return;
        }
        
        if (@available(iOS 13.0, *)) {
            if ([_player isKindOfClass:SldpMediaPlayerV11.class]) {
                [self writeAudioFrameWithTimestamp:timestamp numSamples:numSamples buffer:buffer len:len];
                return;
            }
        }
        
        // AVSampleBufferRenderSynchronizer not available (ios<11.0) or broken (ios12): don't write audio before first video frame
        SldpTcpConnection* connection = [_connectionMap objectForKey:@(_connectionId)];
        StreamInfoInternal* videoStreamInfo = [[connection getStreams] objectForKey:@(_videoStreamId)];
        if(_videoInit && videoStreamInfo.hasStartTs && [self getMsFromTimestamp:timestamp withTimescale:streamInfo.timescale] >= [self getMsFromTimestamp:videoStreamInfo.startTs withTimescale:videoStreamInfo.timescale]) {
            [self writeAudioFrameWithTimestamp:timestamp numSamples:numSamples buffer:buffer len:len];
        }

    } else if (streamInfo.connectionId == _connectionId && streamInfo.streamId == _nextAudioStreamId) {
        
        dispatch_sync(_queue, ^{
            [self cancelStreamId:self->_audioStreamId];
            self->_audioStreamId = self->_nextAudioStreamId;
            self->_nextAudioStreamId = -1;
        });
        
        [self writeAudioFrameWithTimestamp:timestamp numSamples:numSamples buffer:buffer len:len];
    }
}

-(uint64_t)getMsFromTimestamp:(uint64_t)timestamp withTimescale:(int)timescale {
    if (timescale == 0) {
        return 0;
    }
    if (timescale == 1000) {
        return timestamp;
    }
    return (uint64_t)((timestamp / (double)timescale) * 1000);
}

-(void)playTrack:(int)trackId {
    dispatch_sync(_queue, ^{
        NSLog(@"play request: %d", trackId);
        SldpTcpConnection* connection = [self->_connectionMap objectForKey:@(self->_connectionId)];
        if (connection == nil || ![connection isKindOfClass:[SldpConnection class]]) {
            return;
        }
        
        NSDictionary* streams = [connection getStreams];
        for (StreamInfoInternal* stream in streams.allValues) {
            if (trackId == stream.streamId) {
                if (stream.type == kStreamTypeInternalVideo) {
                    [self playVideoTrack:trackId connection:connection];
                } else if (stream.type == kStreamTypeInternalAudio) {
                    [self playAudioTrack:trackId connection:connection];
                }
                break;
            }
        }
    });
}

-(void)playVideoTrack:(int)trackId connection:(SldpTcpConnection*)connection {
    if (connection.mode == kSldpStreamModeAudioOnly) {
        return;
    }
    if (_abrState != kAbrStatePlay) {
        NSLog(@"!!!ignore play request kAbrStatePlay!!!");
        return;
    }
    if (_videoStreamId == trackId) {
        NSLog(@"!!!ignore play request trackId!!!");
        return;
    }
    NSLog(@"!!!switch sldp video stream!!!");
    
    if(_nextVideoStreamId != -1) {
        [self cancelStreamId:_nextVideoStreamId];
    }
    
    int stream_id = -1;
    NSDictionary* streams = [connection getStreams];
    for(StreamInfoInternal* stream in streams.allValues) {
        if(stream.type == kStreamTypeInternalVideo && stream.state != kStreamStateInternalPlay && trackId == stream.streamId) {
            stream_id = stream.streamId;
            break;
        }
    }
    
    if(stream_id != -1) {
        [self playStreamId:stream_id];
        _abrState = kAbrStateWait;
    }
    _nextVideoStreamId = stream_id;
}

-(void)playAudioTrack:(int)trackId connection:(SldpTcpConnection*)connection {
    if (connection.mode == kSldpStreamModeVideoOnly ||
        _audioStreamId == trackId ||
        _nextAudioStreamId != -1) {
        return;
    }
    
    int stream_id = -1;
    NSDictionary* streams = [connection getStreams];
    for (StreamInfoInternal* stream in streams.allValues) {
        if (stream.type == kStreamTypeInternalAudio && stream.state != kStreamStateInternalPlay && trackId == stream.streamId) {
            stream_id = stream.streamId;
            break;
        }
    }

    if (stream_id != -1) {
        [self playStreamId:stream_id];
    }
    _nextAudioStreamId = stream_id;
}

-(NSDictionary*)getTracks {
    SldpTcpConnection* connection = [_connectionMap objectForKey:@(_connectionId)];
    if (connection != nil) {
        SldpTcpConnection* connection = [_connectionMap objectForKey:@(_connectionId)];
        NSDictionary* streams = [connection getStreams];
        NSMutableDictionary* infos = [[NSMutableDictionary alloc] init];
        for(StreamInfoInternal* stream in streams.allValues) {
            TrackInfo* info = [[TrackInfo alloc] initWithId:stream.streamId];
            if (stream.type == kStreamTypeInternalVideo) {
                info.type = kTrackTypeVideo;
                info.width = stream.width;
                info.height = stream.height;
                info.bandwidth = stream.bandwidth;
                [infos setObject:info forKey:@(stream.streamId)];
            } else if (stream.type == kStreamTypeInternalAudio) {
                info.type = kTrackTypeAudio;
                info.bandwidth = stream.bandwidth;
                [infos setObject:info forKey:@(stream.streamId)];
            }
        }
        return infos;
    }
    return nil;
}

-(void)videoBufferLevelDidChangeSeconds:(float)level Frames:(int)frames PlaybackRate:(float)rate {
    //if (rate > 0) NSLog(@"buffer sec. = %f (%d frames)", level, frames);
}

-(void)starvationStateChanged: (bool)isStarvation {
    NSLog(@"starvationStateChanged %d", isStarvation);
    BaseConnection* connection = [_connectionMap objectForKey:@(_connectionId)];
    if (connection != nil) {
        SldpConnectionStatus status = isStarvation ? kSldpConnectionStatusNoData : kSldpConnectionStatusSuccess;
        [connection.connectionListener connectionStateDidChangeId:connection.connectionID State:kSldpConnectionStateBuffering Status:status];
    }
}

-(void)playbackDidStart {
    BaseConnection* connection = [_connectionMap objectForKey:@(_connectionId)];
    if (connection != nil) {
        [connection.connectionListener connectionStateDidChangeId:connection.connectionID State:kSldpConnectionStatePlay Status:kSldpConnectionStatusSuccess];
    }
}

-(void)playbackDidFail {
    NSLog(@"playbackDidFail");
    NSLog(@"%@", [NSThread callStackSymbols]);
    BaseConnection* connection = [_connectionMap objectForKey:@(_connectionId)];
    if (connection != nil) {
        [connection.connectionListener connectionStateDidChangeId:connection.connectionID State:kSldpConnectionStateDisconnected Status:kSldpConnectionPlaybackFail];
    }
}

-(void)videoFrameDecoded:(CMSampleBufferRef)frame {
    BaseConnection* connection = [_connectionMap objectForKey:@(_connectionId)];
    if (connection != nil) {
        [connection.connectionListener videoFrameDecoded: frame];
    }
}

-(void)playStreamId:(int)streamId {
    SldpTcpConnection* connection = [_connectionMap objectForKey:@(_connectionId)];
    if (connection != nil && [connection isKindOfClass:[SldpConnection class]]) {
        NSMutableArray<SldpPlayRequest*>* streams_to_play = [[NSMutableArray alloc] init];
        SldpPlayRequest* req = [[SldpPlayRequest alloc]initWithStreamId:streamId];
        [streams_to_play addObject:req];
        [connection sendPlayWithStreams:streams_to_play];
    }
}

-(void)cancelStreamId:(int)streamId {
    SldpTcpConnection* connection = [_connectionMap objectForKey:@(_connectionId)];
    if (connection != nil && [connection isKindOfClass:[SldpConnection class]]) {
        NSMutableArray* streams_to_cancel = [[NSMutableArray alloc] init];
        [streams_to_cancel addObject:@(streamId)];
        [connection sendCancelWithStreams:streams_to_cancel];
    }
}

-(StreamInfoInternal*)getStreamInfoForId:(int)streamId {
    SldpTcpConnection* connection = [_connectionMap objectForKey:@(_connectionId)];
    NSDictionary* streams = [connection getStreams];
    return (StreamInfoInternal*)[streams objectForKey:@(streamId)];
}

-(int)getAudioLevelMs {
    if (_player == nil) {
        return 0;
    }
    return _player.audioLevelMs;
}

-(int)getVideoLevelMs {
    if (_player == nil) {
        return 0;
    }
    return _player.videoLevelMs;
}

-(bool)isSimulator {
    NSProcessInfo *processInfo = [NSProcessInfo processInfo];
    NSDictionary<NSString*, NSString*>* environment = [processInfo environment];
    NSString* simulator = [environment objectForKey:@"SIMULATOR_DEVICE_NAME"];
    return simulator != nil;
}

-(void)mute:(bool)muted {
    [_player mute:muted];
    _muted = muted;
}

-(bool)isMuted {
    if (_player == nil) {
        return _muted;
    }
    return [_player isMuted];
}

-(void)setVolume:(float)volume {
    [_player setVolume:volume];
}

-(float)getVolume {
    if (_player == nil) {
        return 0.0;
    }
    return [_player getVolume];
}

-(void)notifySteadyTimestamp: (NSDate*) absolute_ts for_stream: (int)streamId {
    if ((_player.playbackType != kPlaybackTypeAudioOnly && streamId == _videoStreamId) ||
        (_player.playbackType == kPlaybackTypeAudioOnly && streamId == _audioStreamId) )
    [_player mapAbsoluteTime:absolute_ts];
}

- (bool)getSrtStats:(int)connectionID stats:(PlayerSrtStats* _Nonnull ) stats clear:(bool)clear instantaneous:(bool)instantaneous {
    return false;
}


@end
