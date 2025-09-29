#import "SldpConnection.h"
#import	<CommonCrypto/CommonDigest.h>
#import "StreamInfoInternal.h"
#import "SldpPlayRequest.h"

typedef NS_ENUM(uint8_t, WebsocketLiveFrameType) {
    WEB_AAC_SEQUENCE_HEADER = 0,
    WEB_AAC_FRAME = 1,
    WEB_AVC_SEQUENCE_HEADER = 2,
    WEB_AVC_KEY_FRAME = 3,
    WEB_AVC_FRAME = 4,
    WEB_HEVC_SEQUENCE_HEADER = 5,
    WEB_HEVC_KEY_FRAME = 6,
    WEB_HEVC_FRAME = 7,
    WEB_VP6_KEY_FRAME = 8,
    WEB_VP6_FRAME = 9,
    WEB_VP8_KEY_FRAME = 10,
    WEB_VP8_FRAME = 11,
    WEB_VP9_KEY_FRAME = 12,
    WEB_VP9_FRAME = 13,
    WEB_MP3 = 14,
    WEB_OPUS_FRAME = 15
};

typedef NS_ENUM(int, RtspConnectionState) {
    kHandshake,
    kStatus,
    kPlay,
    kClosed
};

typedef NS_ENUM(int, FrameType) {
    kUnknownFrame,
    kTextFrame,
    kBinaryFrame
};

const uint64_t INVALID_TIMESTAMP = ~0ull;

@implementation SldpConnection {
   
    NSURL* _original_uri;
    NSString* _user;
    NSString* _pass;
    NSURL* _uri;
    NSMutableString* stream_;
    RtspConnectionState _state;
    SldpHttpParser* _http_parser;
    
    NSTimer* _dataSendTimer;
    int _status;
    
    FrameType  _frame_type;
    SldpByteBuffer* _frame_buffer;
    
    NSMutableDictionary* stream_id_map_;
    NSMutableDictionary* stream_sn_map_;
    
    NSArray* sorted_videos_id;
    
    int stream_id_;
    int sn_;
    
    uint64_t _steady_ts;
    uint64_t _system_ts;
    NSTimeInterval _playback_delay;
    NSTimeInterval _zero_time;
}
static int SLDP_INIT_FRAME_SIZE = 256 * 1024;
static int SLDP_MAX_FRAME_SIZE = 4 * 1024 * 1024;

- (id)initWithConnectionId:(int)connectionId uri:(NSURL*)uri offset:(int32_t)offset useSSL:(bool)useSSL mode:(int)mode
                   bitrate:(int32_t)bitrate delay:(int32_t)delay
        connectionListener:(id<SldpConnectionListener>)connectionListener streamListener:(id<SldpStreamListener>)streamListener {
    NSLog(@"SldpConnection::initWithConnectionId");

    int port = useSSL ? 443 : 80;
    if(uri.port != NULL) {
        port = uri.port.intValue;
    }
    
    self = [super initWithConnectionId:connectionId host:uri.host port:port useSSL:useSSL mode:mode connectionListener:connectionListener];
    
    _original_uri = uri;
    _user = _original_uri.user;
    _pass = _original_uri.password;
    _uri = [self removeUserInfo:_original_uri];
    
    // parse apllication and stream
    NSArray* splittedUri = [[_original_uri absoluteString] componentsSeparatedByString:@"/"];
    if(splittedUri.count < 5) {
        return nil;
    }
        // get stream
    stream_ = [[NSMutableString alloc] initWithString: splittedUri[3]];
    for(int i = 4; i < splittedUri.count; ++i) {
        [stream_ appendFormat: @"/%@", splittedUri[i]];
    }
    
    stream_id_map_ = [[NSMutableDictionary alloc] init];
    stream_sn_map_ = [[NSMutableDictionary alloc] init];
    
    stream_id_ = 0;
    
    _offset = offset;
    _bitrate = bitrate;
    
    _http_parser = [[SldpHttpParser alloc] initWithDelegate:self];
    
    _status = kSldpConnectionStatusConnectionFail;
    
    _streamListener = streamListener;
    
    _frame_buffer = [[SldpByteBuffer alloc] initWithCapacity: SLDP_INIT_FRAME_SIZE bufferLimit:SLDP_MAX_FRAME_SIZE];
    _frame_type = kUnknownFrame;
    
    _playback_delay = (NSTimeInterval)delay / 1000.0;
    _steady_ts = INVALID_TIMESTAMP;
    _system_ts = INVALID_TIMESTAMP;
    
    return self;
}

-(NSURL*)removeUserInfo:(NSURL*)original_uri {

    NSString* scheme = [original_uri scheme];
    
    NSRange range = [original_uri.absoluteString rangeOfString:@"@"];
    if(range.length != 1) {
        return original_uri;
    }
    
    NSString* s = [NSString stringWithFormat:@"%@://%@", scheme, [original_uri.absoluteString substringFromIndex:range.location + 1]];
    NSURL* uri = [[NSURL alloc]initWithString:s];
    
    return uri;
}

-(void)sendUpgradeRequest {
    
    NSMutableString* request = [[NSMutableString alloc] initWithFormat:@"GET /%@ HTTP/1.1\r\n", stream_];
    [request appendFormat:@"Upgrade: websocket\r\n"];
    [request appendFormat:@"Connection: Upgrade\r\n"];
    [request appendFormat:@"Host: %@\r\n", self.host];
    [request appendFormat:@"Origin: http://dev.wmspanel.com\r\n"];
    [request appendFormat:@"Sec-WebSocket-Protocol: sldp.softvelum.com\r\n"];
    [request appendFormat:@"Pragma: no-cache\r\n"];
    [request appendFormat:@"Sec-WebSocket-Key: MYnDFVtBIiNR1eIQ5NNvmA==\r\n"];
    [request appendFormat:@"Sec-WebSocket-Version: 13\r\n"];
    [request appendFormat:@"Sec-WebSocket-Extensions: x-webkit-deflate-frame\r\n"];
    [request appendFormat:@"Sec-WebSocket-Version: 13\r\n"];
    [request appendFormat:@"User-Agent: SLDPLib\r\n\r\n"];
    
    [self Send: request];
}

-(uint64_t)processServerMessage:(SldpByteBuffer*)buffer {
    //NSLog(@"SldpConnection::processServerMessage %d", buffer.limit);

    int hdr_len = 2;
    
    if(buffer.limit < hdr_len) {
        return 0;
    }
    
    if(buffer.data[1] & 0x80) {
        // mask
        return -1;
    }
    
    uint64_t payload_len = buffer.data[1] & 0x7F;
    if(payload_len == 126) {
        // 16 bit Extended payload length
        hdr_len += 2;
        
        if(buffer.limit < hdr_len) {
            return 0;
        }
        
        payload_len = ((uint16_t)buffer.data[2] << 8) | buffer.data[3];
    
    } else if(payload_len == 127) {
        // 64 bit Extended payload length
        hdr_len += 8;
        
        if(buffer.limit < hdr_len) {
            return 0;
        }
        
        payload_len =
        ((uint64_t)buffer.data[2] << 56) |
        ((uint64_t)buffer.data[3] << 48) |
        ((uint64_t)buffer.data[4] << 40) |
        ((uint64_t)buffer.data[5] << 32) |
        (buffer.data[6] << 24) |
        (buffer.data[7] << 16) |
        (buffer.data[8] << 8) |
        buffer.data[9];
        
        
        NSLog(@"%lld", payload_len);
    }
    if (payload_len > INT_MAX) {
        NSLog(@"Payload length is too large");
        return 0;
    }
    int payload_int = (int)payload_len;
    
    if(hdr_len + payload_len > buffer.limit) {
        // incomplete frame
        //NSLog(@"incomplete frame");
        return 0;
    }
    
    int opcode = buffer.data[0] & 0xF;
    switch (opcode) {
        case 0x0:
            // continuation frame
            //NSLog(@"continuation frame %llu", payload_len);
            if(![_frame_buffer put:buffer.data + hdr_len len:payload_int]) {
                return -1;
            }
            break;
            
        case 0x1:
            // text frame
            _frame_type = kTextFrame;
            [_frame_buffer reset];
            NSLog(@"text frame %llu", payload_len);
            if(![_frame_buffer put:buffer.data + hdr_len len:payload_int]) {
                return -1;
            }
            break;
            
        case 0x2:
            // binary frame
            //NSLog(@"binary frame %llu", payload_len);
            _frame_type = kBinaryFrame;
            [_frame_buffer reset];
            if(![_frame_buffer put:buffer.data + hdr_len len:payload_int]) {
                return -1;
            }
            break;
            
        case 0x8:
            // connection close
            NSLog(@"0x8 - connection close");
            [self Close];
            return hdr_len + payload_len;
            
        case 0x9:
            // ping
            NSLog(@"0x9 - ping");
            [self sendPong];
            return hdr_len + payload_len;
            
        case 0xA:
            // pong
            NSLog(@"0xA - pong");
            return hdr_len + payload_len;
            
        default:
            break;
    }
    
    if(buffer.data[0] & 0x80) {
        // fin
        
        switch (_frame_type) {
            case kTextFrame:
                [self processTextMessage:_frame_buffer.data len:_frame_buffer.limit];
                break;
                
            case kBinaryFrame:
                [self processBinaryMessage:_frame_buffer.data len:_frame_buffer.limit];
                break;
                
            default:
                break;
        }
        
        _frame_type = kUnknownFrame;
        [_frame_buffer reset];
        
    }

    return hdr_len + payload_len;
}

-(void)processTextMessage:(uint8_t*)buffer len:(int)len {

    NSMutableData* data = [NSMutableData dataWithBytes:buffer length:len];
    
    NSError* error = nil;
    NSMutableDictionary* result = [NSJSONSerialization JSONObjectWithData:data options:NSJSONReadingMutableContainers error:&error];
    if (error) {
        NSLog(@"JSONObjectWithData error: %@", error);
    }
    
    NSString* command = [result valueForKey:@"command"];
    NSLog(@"command=%@", command);
    if([command isEqual: @"status"]) {
        NSLog(@"process status command");

        NSString* steady = [result valueForKey:@"steady"];
        NSString* system = [result valueForKey:@"system"];
        if (steady == NULL || system == NULL) {
            [self notifyOnStateChange:kSldpConnectionStateSteadySupportCheck Status:kSldpConnectionSteadyUnsupported];
        } else {
            [self notifyOnStateChange:kSldpConnectionStateSteadySupportCheck Status:kSldpConnectionStatusSuccess];
            if (_playback_delay > 0.0) {
                _steady_ts = [steady longLongValue];
                _system_ts = [system longLongValue];
//                NSLog(@"steady: %llu, system:%llu", _steady_ts, _system_ts);
                NSTimeInterval epoch_time = _system_ts / 1000000.0;
                NSDate* remoteDate = [NSDate dateWithTimeIntervalSince1970:epoch_time];
                NSDate* localDate = [[NSDate alloc]init];
                NSDateFormatter *dateFormatter = [[NSDateFormatter alloc] init];
                NSTimeInterval remote_clock_offset = [localDate timeIntervalSince1970] - epoch_time;
                dateFormatter.locale = [[NSLocale alloc] initWithLocaleIdentifier:@"en_US"];
                [dateFormatter setLocalizedDateFormatFromTemplate:@"yyyy-MM-dd'T'HH:mm:ss.SSS"];
                NSLog(@"Remote: %@ Local: %@ delta: %10.4f", [dateFormatter stringFromDate:remoteDate], [dateFormatter stringFromDate:localDate], remote_clock_offset);
                if (remote_clock_offset < 0.1) {
                    remote_clock_offset = 0.0;
                }
                _zero_time = epoch_time - (_steady_ts / 1000000.0) + remote_clock_offset  + _playback_delay;
            }
        }

        NSMutableArray* info_array = [result valueForKey:@"info"];
        if(nil == info_array) {
            NSLog(@"failed to get info");
            return;
        }

        for(NSMutableDictionary* info in info_array) {
            
            NSString* stream = [info valueForKey:@"stream"];
            NSLog(@"stream: %@", stream);
            
            NSMutableDictionary* stream_info = [info valueForKey:@"stream_info"];
            if(nil == stream_info) {
                NSLog(@"failed to get stream_info");
                return;
            }
            
            
            NSString* bandwidth = [stream_info valueForKey:@"bandwidth"];
            NSLog(@"bandwidth=%@", bandwidth);
            
            NSString* resolution = [stream_info valueForKey:@"resolution"];
            NSLog(@"resolution=%@", resolution);
            
            NSString* vcodec = [stream_info valueForKey:@"vcodec"];
            NSString* vtimescale = [stream_info valueForKey:@"vtimescale"];
            if(vcodec != nil && vtimescale != nil) {
                NSLog(@"video %@ %@", vcodec, vtimescale);
                
                StreamInfoInternal *video = [[StreamInfoInternal alloc]initWithConnectionId:super.connectionID streamId:++stream_id_ type:kStreamTypeInternalVideo];
                video.stream = stream;
                video.timescale = [vtimescale intValue];
                video.bandwidth = [bandwidth intValue];
                
                NSRegularExpression *regex = [NSRegularExpression regularExpressionWithPattern:@"(\\d+)x(\\d+)" options:0 error:nil];
                NSTextCheckingResult *match = [regex firstMatchInString:resolution options:0 range:NSMakeRange(0, [resolution length])];
                
                if(match.numberOfRanges != 3) {
                    NSLog(@"failed to parse resolution %@", resolution);
                    return;
                }
                
                NSRange widthRange = [match rangeAtIndex:1];
                NSString* s_width = [resolution substringWithRange:widthRange];
                video.width = [s_width intValue];
                
                NSRange heightRange = [match rangeAtIndex:2];
                NSString* s_height = [resolution substringWithRange:heightRange];
                video.height = [s_height intValue];
                
                [stream_id_map_ setObject:video forKey:@(stream_id_)];
            }
            
            NSString* acodec = [stream_info valueForKey:@"acodec"];
            NSString* atimescale = [stream_info valueForKey:@"atimescale"];
            if(acodec != nil && atimescale != nil) {
                NSLog(@"audio %@ %@", acodec, atimescale);
                
                StreamInfoInternal* audio = [[StreamInfoInternal alloc]initWithConnectionId:super.connectionID streamId:++stream_id_ type:kStreamTypeInternalAudio];
                audio.stream = stream;
                audio.timescale = [atimescale intValue];
                audio.bandwidth = [bandwidth intValue];
                
                [stream_id_map_ setObject:audio forKey:@(stream_id_)];
            }
        }
        
        [self initSortedVideoStreams];
        [_streamListener streamInfoDidRecvId:super.connectionID];
        
    } else {
        NSLog(@"unsupported command %@", command);
    }

}


-(void)processBinaryMessage:(uint8_t*)buffer len:(int)len {

    if(len < 2) {
        NSLog(@"failed to read binary frame header");
        return;
    }
    
    uint8_t sn = buffer[0];
    WebsocketLiveFrameType frame_type = buffer[1];
    buffer += 2; len -= 2;
    
    uint64_t timestamp = INVALID_TIMESTAMP;
    uint64_t steady_timestamp = INVALID_TIMESTAMP;

    if(frame_type != WEB_AAC_SEQUENCE_HEADER &&
       frame_type != WEB_AVC_SEQUENCE_HEADER &&
       frame_type != WEB_HEVC_SEQUENCE_HEADER) {
        
        if(len < 8) {
            NSLog(@"failed to read timestamp");
            return;
        }
        
        timestamp = ((uint64_t)buffer[0] << 56) |
            ((uint64_t)buffer[1] << 48) |
            ((uint64_t)buffer[2] << 40) |
            ((uint64_t)buffer[3] << 32) |
            ((uint64_t)buffer[4] << 24) |
            ((uint64_t)buffer[5] << 16) |
            ((uint64_t)buffer[6] << 8)  |
            buffer[7];
        
        buffer += 8; len -= 8;

        if (self.steadyEnabled) {
            steady_timestamp = ((uint64_t)buffer[0] << 56) |
                ((uint64_t)buffer[1] << 48) |
                ((uint64_t)buffer[2] << 40) |
                ((uint64_t)buffer[3] << 32) |
                ((uint64_t)buffer[4] << 24) |
                ((uint64_t)buffer[5] << 16) |
                ((uint64_t)buffer[6] << 8)  |
                buffer[7];
            
            buffer += 8; len -= 8;
        }
    }

    uint32_t composition_time_offset = -1;
    if(frame_type == WEB_AVC_KEY_FRAME ||
       frame_type == WEB_AVC_FRAME ||
       frame_type == WEB_HEVC_FRAME ||
       frame_type == WEB_HEVC_KEY_FRAME) {
        
        if(len < 4) {
            NSLog(@"failed to read composition time offset");
            return;
        }
        
        composition_time_offset = ((uint32_t)buffer[0] << 24) |
            ((uint32_t)buffer[1] << 16) |
            ((uint32_t)buffer[2] << 8) |
            buffer[3];
        
        buffer += 4; len -= 4;
    }
    
    StreamInfoInternal *streamInfo = [stream_sn_map_ objectForKey:@(sn)];
    if(kStreamTypeInternalVideo == streamInfo.type) {
        // video
        [self processVideoFrameWithStreamInfo:streamInfo frame_type:frame_type
                                    timestamp: timestamp
                      composition_time_offset:composition_time_offset
                           steady_timestamp: steady_timestamp
                                       buffer:buffer len:len];
        
        
    } else if(kStreamTypeInternalAudio == streamInfo.type) {
        // audio
        [self processAudioFrameWithStreamInfo:streamInfo
                                   frame_type:frame_type
                                    timestamp:timestamp
                           steady_timestamp:steady_timestamp
                                       buffer:buffer len:len];
        
    } else {
        NSLog(@"unknown frame recvd: sn=%d type=%d %lld %d len=%d", sn, frame_type, timestamp, composition_time_offset, len);
    }
}

-(NSDate*)relativeToAbsoulteTs: (uint64_t) ts {
    NSTimeInterval ts_sec = ts / 1000000.0;
    NSTimeInterval abs_time = _zero_time + ts_sec;
    return [[NSDate alloc]initWithTimeIntervalSince1970:abs_time];
}

-(void)processVideoFrameWithStreamInfo:(StreamInfoInternal*)streamInfo frame_type:(WebsocketLiveFrameType)frame_type
                             timestamp:(uint64_t)timestamp composition_time_offset:(uint32_t)composition_time_offset steady_timestamp:(uint64_t)steady_timestamp
               buffer:(uint8_t*)buffer len:(int)len {

    //NSLog(@"video frame: type=%d %lld %d len=%d", frame_type, timestamp, composition_time_offset, len);
    switch (frame_type) {
        case WEB_AVC_SEQUENCE_HEADER:
        case WEB_HEVC_SEQUENCE_HEADER:
            if (frame_type == WEB_AVC_SEQUENCE_HEADER) {
                streamInfo.videoCodec = kVideoCodecTypeAvc;
            } else if (frame_type == WEB_HEVC_SEQUENCE_HEADER) {
                streamInfo.videoCodec = kVideoCodecTypeHevc;
            }
            streamInfo.extradata = [[NSData alloc]initWithBytes:buffer length:len];
            break;
            
        case WEB_AVC_KEY_FRAME:
        case WEB_HEVC_KEY_FRAME:
            //NSLog(@"video %llu %llu", timestamp, timestamp);
            if (!streamInfo.hasStartTs) {
                streamInfo.hasStartTs = true;
                streamInfo.startTs = timestamp;
            }
            [_streamListener writeVideoFrameWithStreamInfo:streamInfo timestamp:timestamp composition_time_offset:composition_time_offset buffer:buffer len:len key_frame:true];
            break;
            
        case WEB_AVC_FRAME:
        case WEB_HEVC_FRAME:
            //NSLog(@"video %llu %llu", timestamp, timestamp);
            [_streamListener writeVideoFrameWithStreamInfo:streamInfo timestamp:timestamp composition_time_offset:composition_time_offset buffer:buffer len:len key_frame:false];
            break;
            
        default:
            break;
    }
    if (steady_timestamp != INVALID_TIMESTAMP && (frame_type == WEB_AVC_KEY_FRAME || frame_type == WEB_HEVC_KEY_FRAME)) {
        [_streamListener notifySteadyTimestamp: [self relativeToAbsoulteTs:steady_timestamp] for_stream:streamInfo.streamId];
    }
}

-(void)processAudioFrameWithStreamInfo:(StreamInfoInternal*)streamInfo frame_type:(WebsocketLiveFrameType)frame_type
               timestamp:(uint64_t)timestamp steady_timestamp:(uint64_t)steady_timestamp
                  buffer:(uint8_t*)buffer len:(int)len {
 
    //NSLog(@"audio frame: type=%d %lld len=%d", frame_type, timestamp, len);
    switch (frame_type) {
        case WEB_AAC_SEQUENCE_HEADER:
            streamInfo.audioCodec = kAudioCodecTypeAac;
            streamInfo.extradata = [[NSData alloc]initWithBytes:buffer length:len];
            break;
            
        case WEB_MP3:
            streamInfo.audioCodec = kAudioCodecTypeMp3;
            [_streamListener writeAudioFrameWithStreamInfo:streamInfo timestamp:timestamp numSamples:0 buffer:buffer len:len];
            break;
        case WEB_AAC_FRAME:
            [_streamListener writeAudioFrameWithStreamInfo:streamInfo timestamp:timestamp numSamples: 0 buffer:buffer len:len];
            break;
        case WEB_OPUS_FRAME:
            streamInfo.audioCodec = kAudioCodecTypeOpus;
            [_streamListener writeAudioFrameWithStreamInfo:streamInfo timestamp:timestamp numSamples: 0 buffer:buffer len:len];

        default:
            break;
    }
    if (steady_timestamp != INVALID_TIMESTAMP && (frame_type == WEB_MP3 || frame_type == WEB_AAC_FRAME || frame_type == WEB_OPUS_FRAME)) {
        //Send for audio-only streams
        [_streamListener notifySteadyTimestamp: [self relativeToAbsoulteTs:steady_timestamp] for_stream:streamInfo.streamId];
    }
}


-(void)sendCommand:(NSString*)s {

    NSData* data = [s dataUsingEncoding:[NSString defaultCStringEncoding]];
    
    [self AppendByte:0x81];
    
    if(data.length <= 125) {
        
        [self AppendByte:0x80 | data.length];
        
    } else if(data.length <= 0xFFFF) {
        
        [self AppendByte:0x80 | 126];
        [self AppendByte:data.length >> 8];
        [self AppendByte:data.length & 0xFF];
        
    } else {
        NSLog(@"we don't support huge messages");
        [self Close];
        return;
    }
    
    uint8_t mask[4];
    arc4random_buf(mask, 4);

    [self AppendByte:mask[0]];
    [self AppendByte:mask[1]];
    [self AppendByte:mask[2]];
    [self AppendByte:mask[3]];
    
    uint8_t* bytes = (uint8_t*)data.bytes;
    for(int i = 0; i < data.length; i++) {
        [self AppendByte: bytes[i] ^ mask[i % 4]];
    }
    
    [self sendBuffer];
}


-(void)sendPlayWithStreams:(NSArray<SldpPlayRequest*>*)playRequests {
    
    NSMutableString* play = [[NSMutableString alloc] initWithString:@"{\"command\":\"Play\", \"streams\":["];
    NSMutableString* steady = [[NSMutableString alloc]init];
    if (self.steadyEnabled) {
        [steady appendString: @",\"steady\":true"];
    }

    for (int i = 0; i < [playRequests count]; i++) {
    
        SldpPlayRequest* req = [playRequests objectAtIndex: i];
        if(nil == req) {
            continue;
        }
        
        StreamInfoInternal* streamInfo = [stream_id_map_ objectForKey:@(req.streamId)];
        if(streamInfo == nil) {
            NSLog(@"failed to play stream %d %d: not found", super.connectionID, req.streamId);
            continue;
        }
        
        if (kStreamTypeInternalVideo == streamInfo.type) {
            streamInfo.sn = ++sn_;
            streamInfo.state = kStreamStateInternalPlay;
            [stream_sn_map_ setObject:streamInfo forKey:@(streamInfo.sn)];
            
            if(i > 0) {
                [play appendString:@","];
            }
            [play appendFormat:@"{\"stream\":\"%@\",\"type\":\"video\",\"sn\":\"%d\",\"offset\":\"%llu\",\"duration\":\"%llu\"%@}",
             streamInfo.stream, streamInfo.sn, req.offset, req.duration, steady];

        } else if (kStreamTypeInternalAudio == streamInfo.type) {
            streamInfo.sn = ++sn_;
            streamInfo.state = kStreamStateInternalPlay;
            [stream_sn_map_ setObject:streamInfo forKey:@(streamInfo.sn)];
            
            if(i > 0) {
                [play appendString:@","];
            }
            [play appendFormat:@"{\"stream\":\"%@\",\"type\":\"audio\",\"sn\":\"%d\",\"offset\":\"%llu\",\"duration\":\"%llu\"%@}",
             streamInfo.stream, streamInfo.sn, req.offset, req.duration, steady];
        } else {
            NSLog(@"unsupported stream type=%d, %d %d", streamInfo.type, super.connectionID, req.streamId);
            continue;
        }
    }
    [play appendString:@"]}"];
    NSLog(@"%@", play);
    
    [self sendCommand:play];
}

-(void)sendCancelWithStreams:(NSArray*)streams {
    NSMutableString* cancel = [[NSMutableString alloc] initWithString:@"{\"command\":\"Cancel\", \"streams\":["];
    for (int i = 0; i < [streams count]; i++) {
        int stream_id = [[streams objectAtIndex: i] intValue];
        StreamInfoInternal* streamInfo = [stream_id_map_ objectForKey:@(stream_id)];
        if(streamInfo == nil) {
            NSLog(@"failed to cancel stream %d %d: not found", super.connectionID, stream_id);
            continue;
        }
        
        if(i > 0) {
            [cancel appendString:@","];
        }
        [cancel appendFormat:@"\"%d\"", streamInfo.sn];

        [stream_sn_map_ removeObjectForKey:@(streamInfo.sn)];
        streamInfo.state = kStreamStateInternalStop;
        streamInfo.sn = -1;
    }
    [cancel appendString:@"]}"];
    NSLog(@"%@", cancel);
    
    [self sendCommand:cancel];
}

-(void)sendPong {
    // TBD

}

-(void)OnConnect {
    _status = kSldpConnectionStatusUnknownFail;
    [self notifyOnStateChange:kSldpConnectionStateConnected Status:kSldpConnectionStatusSuccess];

    [self sendUpgradeRequest];
    _state = kHandshake;
}

-(void)OnSend {
    return;
}

-(void)OnReceive:(SldpByteBuffer*)buffer {
    //NSLog(@"SldpConnection::OnReceive len=%d", buffer.limit);
    
    int64_t bytesProcessed = 0;
    
    if (_state == kHandshake) {
        bytesProcessed = [_http_parser parse:(Byte*)buffer.data length:buffer.limit];
        if(bytesProcessed < 0) {
            [self Close];
            return;
        }
        [buffer skip:(int)bytesProcessed];
    }
    //State can change after header parse, so we can go here after handshake
    if (_state == kStatus || _state == kPlay) {
        while(true) {
            
            bytesProcessed = [self processServerMessage:buffer];
            if(bytesProcessed < 0) {
                [self Close];
                return;
            }
            if(bytesProcessed == 0) {
                break;
            }
            
            [buffer skip:(int)bytesProcessed];
        }
    }
}

-(void)onComplete:(SldpHttpParser*)parser {
    //NSLog(@"RtspConnection::onComplete");
    
    switch(_state) {
        case kHandshake:
            if(101 != parser.statusCode) {
                _status = kSldpConnectionStatusHandshakeFail;
                [self Close];
                return;
            }
            _state = kStatus;
            break;

        case kStatus:
        case kPlay:
        case kClosed:
        default:
            [self Close];
            break;
    }
}

-(void)Close {
    
    if(_state != kClosed) {
        _state = kClosed;
        if (self.inactivity_triggered) {
            _status = kSldpConnectionStatusConnectionFail;
        }

        [_dataSendTimer invalidate];
        [super Close];
        [self notifyOnStateChange:kSldpConnectionStateDisconnected Status:_status];
    }
}

-(NSDictionary*) getStreams {
    return stream_id_map_;
}

-(void)initSortedVideoStreams {
    NSMutableDictionary* videos_id_map = [[NSMutableDictionary alloc] init];
    for (id key in stream_id_map_) {
        StreamInfoInternal *info = [stream_id_map_ objectForKey:key];
        if (info.type == kStreamTypeInternalVideo) {
            [videos_id_map setObject:info forKey:key];
        }
    }
    sorted_videos_id = [videos_id_map keysSortedByValueUsingComparator: ^(id obj1, id obj2) {
        if ([(StreamInfoInternal*)obj1 height] > [(StreamInfoInternal*)obj2 height]) {
            return (NSComparisonResult)NSOrderedDescending;
        }
        if ([(StreamInfoInternal*)obj1 height] < [(StreamInfoInternal*)obj2 height]) {
            return (NSComparisonResult)NSOrderedAscending;
        }
        return (NSComparisonResult)NSOrderedSame;
    }];
}

-(long)getHighestVideoId {
    long videoId = [[sorted_videos_id lastObject] integerValue];
    StreamInfoInternal *info = [stream_id_map_ objectForKey:[sorted_videos_id lastObject]];
    NSLog(@"Higest video id %ld %dp", videoId, [info height]);
    return videoId;
}

-(long)getHigherVideoId:(int)streamId {
    long videoId = -1;
    if (sorted_videos_id.count < 2) {
        return -1;
    }
    if (streamId == (int)[self getHighestVideoId]) {
        return -1;
    }
    StreamInfoInternal *curInfo = [stream_id_map_ objectForKey:[NSNumber numberWithLong:streamId]];
    if (curInfo == nil) {
        return -1;
    }
    for (id key in sorted_videos_id) {
        StreamInfoInternal *info = [stream_id_map_ objectForKey:key];
        if (info.height > curInfo.height) {
            videoId = [key integerValue];
            NSLog(@"Higher video id %ld %dp", videoId, [info height]);
            break;
        }
    }
    return videoId;
}

-(long)getLowestVideoId {
    long videoId = [[sorted_videos_id firstObject] integerValue];
    StreamInfoInternal *info = [stream_id_map_ objectForKey:[sorted_videos_id firstObject]];
    NSLog(@"Lowest video id %ld %dp", videoId, [info height]);
    return videoId;
}

-(long)getMatchVideoId:(CMVideoDimensions) resolution {
    long videoId = [[sorted_videos_id firstObject] integerValue];
    for (id key in sorted_videos_id) {
        StreamInfoInternal *info = stream_id_map_[key];
        if (info.width > resolution.width || info.height > resolution.width) {
            break;
        }
        videoId = [key intValue];
    }
    return videoId;
}



-(long)getAudioStreamIdWithBitrate:(int32_t)bitrate {
    NSLog(@"preferred bitrate: %d", bitrate);
    long streamId = -1;
    int bandwidth = 0;
    for (id key in stream_id_map_) {
        StreamInfoInternal *info = [stream_id_map_ objectForKey:key];
        if (info.type == kStreamTypeInternalAudio) {
            if (streamId == -1) {
                streamId = [key integerValue];
                bandwidth = info.bandwidth;
            } else if (info.bandwidth < bandwidth) {
                streamId = [key integerValue];
                bandwidth = info.bandwidth;
            }
        }
    }
    for (id key in stream_id_map_) {
        StreamInfoInternal *info = [stream_id_map_ objectForKey:key];
        if (info.type == kStreamTypeInternalAudio) {
            if (info.bandwidth <= bitrate && info.bandwidth > bandwidth) {
                streamId = [key integerValue];
                bandwidth = info.bandwidth;
            }
        }
    }
    return streamId;
}

-(BOOL)steadyEnabled {
    return _playback_delay > 0.0 && _steady_ts != INVALID_TIMESTAMP && _system_ts != INVALID_TIMESTAMP;
}

@end
