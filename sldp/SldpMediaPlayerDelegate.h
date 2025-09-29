typedef NS_ENUM(int, PlaybackType) {
    kPlaybackTypeVideoAudio = 0,
    kPlaybackTypeVideoOnly  = 1,
    kPlaybackTypeAudioOnly  = 2
};

@protocol SldpMediaPlayerDelegate<NSObject>
@required
-(void)videoBufferLevelDidChangeSeconds:(float)level Frames:(int)frames PlaybackRate:(float)rate;
-(void)starvationStateChanged: (bool)isStarvation;
-(void)playbackDidStart;
-(void)playbackDidFail;
@optional
-(void)videoFrameDecoded:(CMSampleBufferRef)frame;

@end
