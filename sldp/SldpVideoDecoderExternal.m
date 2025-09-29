
#import "SldpVideoDecoderExternal.h"

static const int MAX_DECODED_FRAMES = 10;

void logOSStatus_(NSString* info, OSStatus status)
{
    NSError *error = [NSError errorWithDomain:NSOSStatusErrorDomain code:status userInfo:nil];
    NSLog(@"%@", info);
    NSLog(@"%@", [error localizedDescription]);
}

void decompressionSessionDecodeFrameCallback(void *decompressionOutputRefCon,
                                             void *sourceFrameRefCon,
                                             OSStatus status,
                                             VTDecodeInfoFlags infoFlags,
                                             CVImageBufferRef imageBuffer,
                                             CMTime presentationTimeStamp,
                                             CMTime presentationDuration) {
    
    SldpVideoDecoderExternal *streamManager = (__bridge SldpVideoDecoderExternal *)decompressionOutputRefCon;
    
    if (status != noErr) {
        logOSStatus_(@"Decompress error", status);
        [streamManager enqueueVideoSampleBuffer:NULL];

    } else {
        //NSLog(@"Decompressed sucessfully, ts=%lld, duration=%lld", presentationTimeStamp.value, presentationDuration.value);
        CMSampleBufferRef sampleBuffer = NULL;
        OSStatus err = noErr;
        
        if (streamManager.videoInfo != NULL && !CMVideoFormatDescriptionMatchesImageBuffer(streamManager.videoInfo, imageBuffer)) {
            NSLog(@"CMVideoFormatDescriptionMatchesImageBuffer: false");
            CFRelease(streamManager.videoInfo);
            streamManager.videoInfo = NULL;
        }
        
        if (streamManager.videoInfo == NULL) {
            CMVideoFormatDescriptionRef _videoInfo = streamManager.videoInfo;
            err = CMVideoFormatDescriptionCreateForImageBuffer(NULL, imageBuffer, &_videoInfo);
            if (err) {
                logOSStatus_(@"Error at CMVideoFormatDescriptionCreateForImageBuffer", err);
                return;
            }
            streamManager.videoInfo = _videoInfo;
            
            CMVideoDimensions dim = CMVideoFormatDescriptionGetDimensions(_videoInfo);
            NSLog(@"CMVideoDimensions %dx%d", dim.width, dim.height);
        }
        
        CMSampleTimingInfo timingInfo = {
            .duration = kCMTimeIndefinite,
            .presentationTimeStamp = presentationTimeStamp,
            .decodeTimeStamp = kCMTimeZero
        };
        
        // Wrap the pixel buffer in a sample buffer
        err = CMSampleBufferCreateForImageBuffer(kCFAllocatorDefault,
                                                 imageBuffer,
                                                 true, NULL, NULL,
                                                 streamManager.videoInfo,
                                                 &timingInfo,
                                                 &sampleBuffer);
        if (err) {
            logOSStatus_(@"Error at CMSampleBufferCreateForImageBuffer", err);
            return;
        }
        
        CFArrayRef attachments = CMSampleBufferGetSampleAttachmentsArray(sampleBuffer, YES);
        CFMutableDictionaryRef dict = (CFMutableDictionaryRef)CFArrayGetValueAtIndex(attachments, 0);
        CFDictionarySetValue(dict, kCMSampleAttachmentKey_DisplayImmediately, kCFBooleanFalse);
        CFDictionarySetValue(dict, kCMSampleBufferAttachmentKey_PostNotificationWhenConsumed, kCFBooleanTrue);
        
        [streamManager enqueueVideoSampleBuffer:sampleBuffer];
        CFRelease(sampleBuffer);
    }
}

@implementation SldpVideoDecoderExternal
{
    bool _firstFrame;
    bool _stopping;
    CMVideoFormatDescriptionRef _nextVideoDesc;
    CFStringRef newCodecKey;
}

-(id) init {
    self = [super init];
    if (self) {
        _decompressionSession = NULL;
        _videoInfo = NULL;
        _queue = dispatch_queue_create("com.wmspanel.libsldp.player", DISPATCH_QUEUE_SERIAL);
        _decodeQueue = dispatch_queue_create("com.wmspanel.libsldp.decoder", DISPATCH_QUEUE_SERIAL);
        _lock = [[NSRecursiveLock alloc] init];
        _encodedFrames = [[NSMutableArray alloc] init];
        _decodedFrames = [[NSMutableArray alloc] initWithCapacity:MAX_DECODED_FRAMES];
        _decompressing = false;
        _firstFrame = true;
        _stopping = false;
        newCodecKey = CFSTR("SWITCH_VIDEO_CODEC");
    }
    return self;
}

-(void)releaseDecompressionSession {
    if (_decompressionSession) {
        VTDecompressionSessionWaitForAsynchronousFrames(_decompressionSession);
        VTDecompressionSessionInvalidate(_decompressionSession);
        CFRelease(_decompressionSession);
        _decompressionSession = NULL;
        _decompressing = false;
    }
}

-(bool)createDecompressionSession: (CMVideoFormatDescriptionRef) videoDesc {
    VTDecompressionOutputCallbackRecord callBackRecord;
    callBackRecord.decompressionOutputCallback = decompressionSessionDecodeFrameCallback;
    callBackRecord.decompressionOutputRefCon = (__bridge void *)self;
    
    NSDictionary *destinationImageBufferAttributes = [NSDictionary dictionaryWithObjectsAndKeys:
                                                      [NSNumber numberWithBool:YES],
                                                      (id)kCVPixelBufferMetalCompatibilityKey,
                                                      nil];
    
    OSStatus status = VTDecompressionSessionCreate(NULL,
                                                   videoDesc,
                                                   NULL,
                                                   (__bridge CFDictionaryRef)destinationImageBufferAttributes,
                                                   &callBackRecord,
                                                   &_decompressionSession);
    if (status != noErr) {
        NSLog(@"\t\t VTD ERROR type: %d", (int)status);
        return false;
    }

    NSLog(@"Created decompressionSession");
    return true;
}

-(bool)setVideoCodec: (CMVideoFormatDescriptionRef) videoDesc {
    if (_videoInfo == NULL) {
        [self releaseDecompressionSession];
        bool success = [self createDecompressionSession: videoDesc];
        return success;
    }
    _nextVideoDesc = videoDesc;
    return true;
}

-(void)decodeVideoSampleBuffer:(CMSampleBufferRef)sampleBuffer {
    //NSLog(@"New frame\tEncoded: %lu\tDecoded: %lu", _encodedFrames.count, _decodedFrames.count);

    if ([self.delegate updateStreamPosition:sampleBuffer] == false) {
        return;
    }
    
    if (_firstFrame) {
        [self.displayLayer requestMediaDataWhenReadyOnQueue: _queue usingBlock:^{
            while (self.displayLayer.isReadyForMoreMediaData && self.decodedFrames.count > 0) {

                //NSLog(@"requestMediaDataWhenReadyOnQueue %lu", self.frames.count);
                if (! [self.lock tryLock]) {
                    return;
                }
                id sampleBufferObject = self.decodedFrames.firstObject;
                CMSampleBufferRef sampeBuffer = (__bridge CMSampleBufferRef)sampleBufferObject;
                [self.delegate onEqueueVideoSampleBuffer:sampeBuffer];
                [self.displayLayer enqueueSampleBuffer: sampeBuffer];
                [self.decodedFrames removeObjectAtIndex:0];
//                if (self.decodedFrames.count < MAX_DECODED_FRAMES) {
//                    NSLog(@"decodeNextFrame %d", __LINE__);
//                    [self decodeNextFrame];
//                }

                [self.lock unlock];
                //NSLog(@"Displayed -- Encoded: %lu\tDecoded: %lu", self.encodedFrames.count, self.decodedFrames.count);
            }
        }];
        
        [self startDecodeTimer];

        _firstFrame = false;
    }
    [_lock lock];
    if (!_stopping) {
        [self copyBuffer:sampleBuffer];
//        if (_decodedFrames.count < MAX_DECODED_FRAMES) {
//            NSLog(@"decodeNextFrame %d", __LINE__);
//            [self decodeNextFrame];
//        }
    }
    [_lock unlock];
}

-(void)startDecodeTimer {
    _decodeTimer = dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER, 0, 0, _decodeQueue);
    if (_decodeTimer) {
        dispatch_source_set_timer(_decodeTimer, dispatch_time(DISPATCH_TIME_NOW, 1 * NSEC_PER_MSEC), NSEC_PER_MSEC, NSEC_PER_MSEC);
        dispatch_source_set_event_handler(_decodeTimer, ^{
            if (! [self.lock tryLock]) {
                return;
            }
            if (self->_stopping) {
                [self stopAsync];
            }
            if (self.decodedFrames.count < MAX_DECODED_FRAMES && self.encodedFrames.count > 0 &&!self.decompressing) {
                [self decodeNextFrame];
            }
            [self.lock unlock];
        });
        dispatch_resume(_decodeTimer);
    }
}

-(void)copyBuffer:(CMSampleBufferRef)sampleBuffer {
    CMSampleBufferRef bufferCopy;

    char* dataSrc;
    size_t dataSize;
    CMBlockBufferRef data = CMSampleBufferGetDataBuffer(sampleBuffer);
    CMBlockBufferGetDataPointer(data, 0, NULL, &dataSize, &dataSrc);
    void* dataCopy = CFAllocatorAllocate(kCFAllocatorDefault, dataSize, 0);
    memcpy(dataCopy, dataSrc, dataSize);
    CMBlockBufferRef blockCopy;
    CMBlockBufferCreateWithMemoryBlock(kCFAllocatorDefault, dataCopy, dataSize, kCFAllocatorDefault, NULL, 0, dataSize, 0, &blockCopy);
    
    CMFormatDescriptionRef fmt = CMSampleBufferGetFormatDescription(sampleBuffer);
    CMSampleTimingInfo timing;
    timing.decodeTimeStamp = CMSampleBufferGetDecodeTimeStamp(sampleBuffer);
    timing.presentationTimeStamp = CMSampleBufferGetPresentationTimeStamp(sampleBuffer);
    timing.duration = CMSampleBufferGetDuration(sampleBuffer);
    
    CMSampleBufferCreateReady(kCFAllocatorDefault,
                              blockCopy,
                              fmt,
                              1,
                              1, &timing,
                              1, &dataSize,
                              &bufferCopy);

    if (_nextVideoDesc != NULL) {
        //Put codec description to next frame attachment
        CMSetAttachment(bufferCopy, newCodecKey, _nextVideoDesc, kCMAttachmentMode_ShouldPropagate);
        _nextVideoDesc = NULL;
    }
    id sampleBufferObject = (__bridge id)bufferCopy;
    [_encodedFrames addObject:sampleBufferObject];

}

-(void)decodeNextFrame {
    id encodedFrameObject = [_encodedFrames firstObject];
    if (encodedFrameObject == nil || _decompressing || _decompressionSession == NULL || _stopping) {
        return;
    }
    CMSampleBufferRef sampleBuffer =  (__bridge CMSampleBufferRef)(encodedFrameObject);
    if (![self decodeFrameInternal: sampleBuffer]) {
        [self.delegate onDecodingFailed];
    }
    [_encodedFrames removeObjectAtIndex:0];
}

-(bool)decodeFrameInternal: (CMSampleBufferRef)sampleBuffer {
    bool success = true;
    CMBlockBufferRef bb = CMSampleBufferGetDataBuffer(sampleBuffer);
    if (bb == NULL) {
        NSLog(@"!!! No data buffer");
        success = false;
    }
    if (success) {
        CMVideoFormatDescriptionRef desc = CMGetAttachment(sampleBuffer, newCodecKey, NULL);
        if (desc != NULL) {
            [self releaseDecompressionSession];
            bool success = [self createDecompressionSession: desc];
            if (!success) {
                NSLog(@"Failed to recreate conpression session");
                success = false;
            }
        }
    }
    if (success) {
        dispatch_async(_decodeQueue, ^{
            self->_decompressing = true;
            VTDecodeFrameFlags flags = kVTDecodeFrame_EnableAsynchronousDecompression;
            VTDecodeInfoFlags flagOut;

            OSStatus err = VTDecompressionSessionDecodeFrame(self.decompressionSession,
                                              sampleBuffer,
                                              flags,
                                              NULL,
                                              &flagOut);
            if (err != noErr) {
                NSLog(@"Failed to decompress frame: error %d", err);
                self->_decompressing = false;
            }
            CFRelease(sampleBuffer);
            if (bb != NULL) {
                CFRelease(bb);
            }
        });
    }
    return success;
}

-(void)enqueueVideoSampleBuffer:(CMSampleBufferRef)sampleBuffer {
    //NSLog(@"Decompressed\tEncoded: %lu\tDecoded: %lu", _encodedFrames.count, _decodedFrames.count);

    _decompressing = false;

    if (sampleBuffer == NULL) {
        return;
    }
    [_lock lock];
    if (!_stopping) {
        id sampleBufferObject = (__bridge id)sampleBuffer;
        [_decodedFrames addObject:sampleBufferObject];
    }
//    if (_decodedFrames.count < MAX_DECODED_FRAMES) {
//        [self decodeNextFrame];
//    }
    [_lock unlock];
}

-(void)stop {
    _stopping = true;
    [self.displayLayer stopRequestingMediaData];
}

-(void)stopAsync {
    dispatch_source_cancel(_decodeTimer);
    [self releaseDecompressionSession];
    for(id obj in _encodedFrames) {
        CMSampleBufferRef sampleBuffer =  (__bridge CMSampleBufferRef)(obj);
        CMBlockBufferRef bb = CMSampleBufferGetDataBuffer(sampleBuffer);
        CFRelease(sampleBuffer);
        if (bb != NULL) {
            CFRelease(bb);
        }
    }
    [_decodedFrames removeAllObjects];
    [_encodedFrames removeAllObjects];
    [_lock unlock];
    if (_videoInfo) {
        CFRelease(_videoInfo);
        _videoInfo = NULL;
    }

}

@end
