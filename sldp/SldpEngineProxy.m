#import <Foundation/Foundation.h>

#import "SldpEngineProxy.h"
#import "SldpStreamer.h"
#import "SldpConnectionListener.h"

@interface SldpEngineProxy ()<SldpConnectionListener>
@end

@implementation SldpEngineProxy {
    SldpStreamer *_engine;
}

- (id)init {
    self = [super init];
    if (self) {
        _engine = [[SldpStreamer alloc] init];
    }
    return self;
}

- (void)setDelegate:(id<SldpEngineDelegate>)newDelegate {
    _delegate = newDelegate;
    _engine.frameListener = newDelegate;
}

- (void)setVideoLayer:(AVSampleBufferDisplayLayer *)newLayer {
    _videoLayer = newLayer;
}

- (int)createStream:(StreamConfig *)config {
    return [_engine createConnectionWithConfig:config displayLayer:_videoLayer connectionListener:self];
}

- (void)releaseStream:(int)streamId clearImage: (bool) clearImage {
    [_engine releaseConnectionId:streamId clearImage:clearImage];
}

- (void)releaseStream:(int)streamId {
    [self releaseStream:streamId clearImage:true];
}

- (void)connectionStateDidChangeId:(int)connectionId State:(SldpConnectionState)state Status:(SldpConnectionStatus)status {
    //NSLog(@"connectionStateDidChangeId %d %d %d", connectionId, state, status);
    [_delegate streamStateDidChangeId:connectionId State:(StreamState)state Status:(StreamStatus)status];
}

- (void)icecastMetadataDidArrived:(int)connectionId Meta:(NSString*)meta {
    NSLog(@"icecastMetadataDidArrived %d", connectionId);
    if ([_delegate respondsToSelector:@selector(icecastMetadataDidArrived:Meta:)]) {
        [_delegate icecastMetadataDidArrived:connectionId Meta:meta];
    }
}

- (void)rtmpMetadataDidArrived:(int)connectionId Meta:(NSDictionary*)meta {
    //NSLog(@"rtmpMetadataDidArrived %d", connectionId);
    //NSError* err;
    //NSData* jsonData = [NSJSONSerialization dataWithJSONObject:meta options:0 error:&err];
    //NSString* jsonString = [[NSString alloc] initWithData:jsonData encoding:NSUTF8StringEncoding];
    //NSLog(@"%@", jsonString);
    if ([_delegate respondsToSelector:@selector(rtmpMetadataDidArrived:Meta:)]) {
        [_delegate rtmpMetadataDidArrived:connectionId Meta:meta];
    }
}


-(void)videoFrameDecoded:(CMSampleBufferRef)frame {
    if ([_delegate respondsToSelector:@selector(videoFrameDecoded:)]) {
        [_delegate videoFrameDecoded: frame];
    }
}

- (NSDictionary*)getTracks {
    return [_engine getTracks];
}

- (void)playTrack:(int)trackId {
    [_engine playTrack:trackId];
}

- (int)getAudioLevelMs {
    return [_engine getAudioLevelMs];
}

- (int)getVideoLevelMs {
    return [_engine getVideoLevelMs];
}

- (void)setMuted:(bool)muted {
    [_engine mute:muted];
}

- (bool)isMuted {
    return [_engine isMuted];
}

- (void)setVolume:(float)volume {
    [_engine setVolume:volume];
}

- (float)getVolume {
    return [_engine getVolume];
}

- (bool)getSrtStats:(int)connectionID stats:(PlayerSrtStats* _Nonnull ) stats clear:(bool)clear instantaneous:(bool)instantaneous {
    return [_engine getSrtStats:connectionID stats:stats clear:clear instantaneous:instantaneous];
}

@end
