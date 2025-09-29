
#import "SldpVideoDecoderBase.h"

@implementation SldpVideoDecoderBase



-(void)stop {
    
}

-(bool)setVideoCodec: (CMVideoFormatDescriptionRef) desc {
    return true;
}

-(void)decodeVideoSampleBuffer:(CMSampleBufferRef)sampleBuffer {
    if ([self.delegate updateStreamPosition:sampleBuffer]) {
        [self.displayLayer enqueueSampleBuffer:sampleBuffer];
    }
}



@end
