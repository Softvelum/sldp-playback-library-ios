@import VideoToolbox;
@import AVFoundation;
@import CoreMedia;

#import "SldpVideoDecoderBase.h"

@interface SldpVideoDecoderExternal: SldpVideoDecoderBase

@property VTDecompressionSessionRef decompressionSession;
@property CMVideoFormatDescriptionRef videoInfo;

@property dispatch_queue_t queue;
@property dispatch_queue_t decodeQueue;
@property dispatch_source_t decodeTimer;

@property NSMutableArray *encodedFrames;
@property NSMutableArray *decodedFrames;
@property NSRecursiveLock *lock;
@property bool decompressing;

-(id)init;

-(bool)setVideoCodec: (CMVideoFormatDescriptionRef) desc;

-(void)decodeVideoSampleBuffer:(CMSampleBufferRef)sampleBuffer;
-(void)enqueueVideoSampleBuffer:(CMSampleBufferRef)sampleBuffer;
-(void)stop;

@end
