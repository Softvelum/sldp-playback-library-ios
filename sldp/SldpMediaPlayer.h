#import "SldpBaseMediaPlayer.h"

@interface SldpMediaPlayer : SldpBaseMediaPlayer

@property AVAudioEngine *engine;
@property AVAudioPlayerNode *player;
@property AVAudioMixerNode *mixer;
@property AVAudioFormat *processingFormat;
@property AVAudioFormat *compressedFormat;
@property AVAudioCompressedBuffer *compressedBuffer;
@property AVAudioConverter *decompress;
@property uint32_t offset;
@property uint32_t idx;
@property AVAudioFrameCount packetCapacity;
@property AVAudioFrameCount frameCapacity;

@property bool isAudioPlaybackStarted;

-(void)playAudio;

@end

