#import <Foundation/Foundation.h>

@interface SldpBufferItem : NSObject
@property uint64_t timestamp;
@property uint32_t composition_time_offset;
@property uint8_t* buffer;
@property int len;
@property bool key_frame;

- (id)initWithBuffer:(const uint8_t*)buffer timestamp:(uint64_t)timestamp composition_time_offset:(uint32_t)composition_time_offset len:(int)len key_frame:(bool)key_frame;
@end
