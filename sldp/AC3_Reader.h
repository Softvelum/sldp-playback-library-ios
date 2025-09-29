#import <Foundation/Foundation.h>
#import <CoreAudioTypes/CoreAudioTypes.h>

#import "AC3_Frame.h"

@interface AC3_Reader : NSObject
+(bool) processAC3Header:(const uint8_t*) buffer size: (uint32_t) size sample_rate: (int*) sample_rate frame_size: (uint32_t*) frame_size;
+(uint32_t) getMpeg2tsDuration:(int) sample_rate;
+(bool) getChannelLayout:(const uint8_t*) buffer size:(uint32_t) size layout: (uint8_t*) channel_layout;
+(bool) processAC3Bitstream:(const uint8_t*) buffer size: (uint32_t) size frames:(NSMutableArray<AC3_Frame*>*) frame_list part: (AC3_Frame*) frame_part;
+(int) ac3_channel_count:(const uint8_t) layout;
+(AudioChannelLayoutTag) layoutToCoreAudioTag: (uint8_t) channel_layout;
@end
