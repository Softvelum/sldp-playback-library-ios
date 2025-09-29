#import "StreamInfoInternal.h"

@protocol SldpStreamListener

@required
- (void)streamInfoDidRecvId:(int)connectionId;

- (void)writeVideoFrameWithStreamInfo:(StreamInfoInternal*)streamInfo
        timestamp:(uint64_t)timestamp composition_time_offset:(uint32_t)composition_time_offset
        buffer:(const uint8_t *)buffer len:(int)len key_frame:(bool) key_frame;

- (void)writeAudioFrameWithStreamInfo:(StreamInfoInternal*)streamInfo
        timestamp:(uint64_t)timestamp
        numSamples: (uint32_t) numSamples
        buffer:(const uint8_t *)buffer len:(int)len;

-(void)notifySteadyTimestamp: (NSDate*) steady_ts for_stream: (int)streamId;

@end
