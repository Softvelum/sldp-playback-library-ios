@import AVFoundation;

#import "SldpMediaPlayerDelegate.h"
#import "SldpVideoDecoderBase.h"

@interface SldpBaseMediaPlayer : NSObject<SldpVideoDecoderDelegate>

@property uint32_t bufferMs;
@property uint32_t thresholdMs;

@property PlaybackType playbackType;

@property (nonatomic, weak) AVSampleBufferDisplayLayer *displayLayer;
@property SldpVideoDecoderBase *videoDecoder;
@property CMVideoFormatDescriptionRef videoDesc;
@property CMTimeScale timescaleVideo;
@property uint64_t numVideoFrames;

@property AudioStreamBasicDescription audioFormat;
@property int timescaleAudio;

@property CMTime firstPts;
@property CMTime lastPts;
@property float rate;
@property (weak) id<SldpMediaPlayerDelegate> delegate;
@property bool videoChatMode;

// for AVSampleBufferDisplayLayer
@property CMTime zeroTime;

// for verifyStarvation func
@property uint64_t streamZeroPtsMs;

@property uint64_t videoZeroPtsMs;
@property uint64_t videoPtsMs;
@property uint64_t audioZeroPtsMs;
@property uint64_t audioPtsMs;

@property uint64_t videoZeroBiasTs;

@property NSDate *renderStartRealTime;
@property NSTimer *starvationTimer;
@property Boolean isStarvation;

@property int audioLevelMs;
@property int videoLevelMs;

@property float lastVolume;
@property bool muted;
@property bool steadyMode;
@property bool stopped;

-(id)initWithBuffer:(uint32_t)capacity andThreshold:(uint32_t)thresholdMs externalDecoding:(BOOL) externalDecoding;

-(bool)updateStreamPosition:(CMSampleBufferRef)sampleBuffer;

-(bool)setVideoCodecAvcWithTimescale:(int)timescale buffer:(uint8_t *)buffer len:(const uint32_t)len;
-(bool)setVideoCodecHevcWithTimescale:(int)timescale buffer:(uint8_t *)buffer len:(const uint32_t)len;
-(bool)writeVideoFrameWithTimestamp:(uint64_t)timestamp composition_time_offset:(uint32_t)composition_time_offset buffer:(const uint8_t *)buffer len:(int)len key_frame:(bool) key_frame;

-(bool)setAudioCodecAacWithTimescale:(int)timescale buffer:(const uint8_t *)buffer len:(size_t)len;
-(bool)setAudioCodecMp3WithTimescale:(int)timescale buffer:(const uint8_t *)buffer len:(size_t)len;
-(bool)setAudioCodecOpusWithTimescale:(int)timescale buffer:(const uint8_t *)buffer len:(size_t)len;
-(bool)setAudioCodecAc3WithTimescale:(int)timescale sample_rate: (const int) ac3_sample_rate
                            channels: (const uint8_t) ac3_channel_count layout: (AudioChannelLayoutTag) layout;
-(bool)setAudioCodecEac3WithTimescale:(int)timescale sample_rate: (const int) ac3_sample_rate
                             channels: (const uint8_t) ac3_channel_count layout: (AudioChannelLayoutTag) layout;

-(bool)writeAudioFrameWithTimestamp:(uint64_t)timestamp numSamples:(uint32_t) numSamples buffer:(const uint8_t *)buffer len:(int)len;

-(void)printAudioStreamBasicDescription:(AudioStreamBasicDescription)asbd;
-(bool)startAudioDecodeWithTimescale:(int)timescale
                              format:(AudioStreamBasicDescription)audioFormat
                      packetCapacity:(AVAudioFrameCount)packetCapacity;
-(bool)startAudioDecodeWithTimescale:(int)timescale
                              format:(AudioStreamBasicDescription)audioFormat channelLayout:(AudioChannelLayoutTag) layout
                      packetCapacity:(AVAudioFrameCount)packetCapacity;


-(void)updateVideoStreamPositionWithTimestamp:(uint64_t)timestamp;
-(void)updateAudioStreamPositionWithTimestamp:(uint64_t)timestamp;
-(uint64_t)getMsFromTimestamp:(uint64_t)timestamp withTimescale:(int)timescale;
-(void)mapAbsoluteTime: (NSDate*) time;
-(double)getDeviationForPlayTime: (double) playtime;
-(void)resetStreadyTime;


-(void)stop: (bool)removeImage;

-(void)startStarvationTimer;
-(void)verifyStarvation;

-(void)mute:(bool)muted;
-(bool)isMuted;

-(void)setVolume:(float)volume;
-(float)getVolume;

-(void)printDisplayLayerError;

@end

