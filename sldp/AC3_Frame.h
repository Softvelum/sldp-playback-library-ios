

@interface AC3_Frame: NSObject

@property int sample_rate;
@property uint32_t frame_size;
@property const uint8_t* buffer;
@property uint32_t buffer_size;
-(id)init;
-(void)reset;
@end
