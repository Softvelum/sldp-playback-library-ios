@import AVFoundation;

@protocol SldpVideoDecoderDelegate<NSObject>
-(bool)updateStreamPosition:(CMSampleBufferRef)sampleBuffer;
-(void)onEqueueVideoSampleBuffer:(CMSampleBufferRef)sampleBuffer;
-(void)onDecodingFailed;
@end

@interface SldpVideoDecoderBase: NSObject

@property (weak) AVSampleBufferDisplayLayer *displayLayer;
@property id<SldpVideoDecoderDelegate> delegate;

-(bool)setVideoCodec: (CMVideoFormatDescriptionRef) desc;

-(void)decodeVideoSampleBuffer:(CMSampleBufferRef)sampleBuffer;
-(void)stop;

@end
