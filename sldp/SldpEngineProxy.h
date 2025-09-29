#import <Foundation/Foundation.h>

#import "SldpEngineDelegate.h"
#import "StreamConfig.h"
#import "TrackInfo.h"
#import "SrtStats.h"

@import AVFoundation;

@interface SldpEngineProxy : NSObject

@property (weak, readonly) id<SldpEngineDelegate> _Nullable delegate;
@property (weak, readonly) AVSampleBufferDisplayLayer * _Nullable videoLayer;

- (void)setDelegate:(id<SldpEngineDelegate>_Nullable)newDelegate;

- (void)setVideoLayer:(AVSampleBufferDisplayLayer *_Nullable)newLayer;

- (int)createStream:(StreamConfig *_Nonnull)config;
- (void)releaseStream:(int)streamId;
//pass false to clearImage to preserve last picture on video layer
- (void)releaseStream:(int)streamId clearImage: (bool) clearImage;

- (NSDictionary*_Nonnull)getTracks;
- (void)playTrack:(int)trackId;

-(int)getAudioLevelMs;
-(int)getVideoLevelMs;

// A value of 0.0 means "silence all audio", while 1.0 means "play at the full volume of the audio media".
// This property should be used for frequent volume changes, for example via a volume knob or fader.
// This property is most useful on iOS to control the volume of the renderer relative to other audio output, not for setting absolute volume.
-(float)getVolume;
// Range:   0.0 -> 1.0
// Default: 1.0
-(void)setVolume:(float)volume;

// Indicates whether or not audio output of the renderer is muted.
// Setting this property only affects audio muting for the renderer instance and not for the device.
-(bool)isMuted;
-(void)setMuted:(bool)muted;

-(bool)getSrtStats:(int)connectionID stats:(PlayerSrtStats* _Nonnull ) stats clear:(bool)clear instantaneous:(bool)instantaneous;


@end
