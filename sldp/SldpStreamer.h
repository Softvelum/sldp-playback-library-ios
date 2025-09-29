#import <Foundation/Foundation.h>
#import <AVFoundation/AVFoundation.h>
#import <GLKit/GLKit.h>
#import "SldpConnectionListener.h"
#import "SldpMediaPlayerDelegate.h"
#import "SldpStreamListener.h"
#import "TrackInfo.h"
#import "StreamConfig.h"
#import "SldpEngineDelegate.h"
#import "SrtStats.h"

typedef NS_ENUM(int, AbrState) {
    kAbrStateStop = 0,
    kAbrStatePlay = 1,
    kAbrStateWait = 2,
    kAbrStateShouldSwitch = 3
};

@interface SldpStreamer : NSObject <SldpStreamListener, SldpMediaPlayerDelegate>

-(int)createConnectionWithConfig:(StreamConfig *_Nonnull)config displayLayer:(AVSampleBufferDisplayLayer*_Nullable)displayLayer connectionListener:(id<SldpConnectionListener>_Nonnull)connectionListener;
-(void)releaseConnectionId:(int)id clearImage: (bool) clearImage;

-(NSDictionary*_Nullable)getTracks;
-(void)playTrack:(int)trackId;

-(void)playStreamId:(int)streamId;
-(void)cancelStreamId:(int)streamId;
-(StreamInfoInternal*_Nullable)getStreamInfoForId:(int)streamId;

-(int)getAudioLevelMs;
-(int)getVideoLevelMs;

-(void)mute:(bool)muted;
-(bool)isMuted;

-(void)setVolume:(float)volume;
-(float)getVolume;

- (bool)getSrtStats:(int)connectionID stats:(PlayerSrtStats* _Nonnull ) stats clear:(bool)clear instantaneous:(bool)instantaneous;


@property (weak) id<SldpEngineDelegate> _Nullable frameListener;

@end
