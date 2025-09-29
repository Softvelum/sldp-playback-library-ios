#import "SldpBufferItem.h"

@implementation SldpBufferItem
- (id)initWithBuffer:(const uint8_t*)buffer timestamp:(uint64_t)timestamp composition_time_offset:(uint32_t)composition_time_offset len:(int)len key_frame:(bool)key_frame {
    self = [super init];
    if (self) {
        _buffer = malloc(len);
        if (_buffer != NULL) {
            memcpy(_buffer, buffer, len);
        }
        _timestamp = timestamp;
        _composition_time_offset = composition_time_offset;
        _len = len;
        _key_frame = key_frame;
    }
    return self;
}

-(void)dealloc {
    if (_buffer != NULL) {
        free(_buffer);
        _buffer = NULL;
    }
}
@end
