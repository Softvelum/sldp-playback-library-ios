#import <CoreMedia/CoreMedia.h>

typedef NS_ENUM(int, StreamState) {
    kStreamStateInitialized,
    kStreamStateConnected,
    kStreamStateSetup,
    kStreamStatePlay,
    kStreamStateDisconnected,
    kStreamStateSteadySupportCheck,
    kStreamStateListen,
    kStreamStateBuffering
};

typedef NS_ENUM(int, StreamStatus) {
    kStreamStatusSuccess,
    kStreamStatusAuthFail,
    kStreamStatusConnectionFail,
    kStreamStatusHandshakeFail,
    kStreamStatusUnknownFail,
    kStreamStatusNoData,
    kStreamStatusPlaybackFail,
    kStreamStatusSteadyUnsupported
};

@protocol SldpEngineDelegate <NSObject>

@required
-(void)streamStateDidChangeId:(int)streamId State:(StreamState)state Status:(StreamStatus)status;

@optional
-(void)icecastMetadataDidArrived:(int)connectionId Meta:(NSString*)meta;
-(void)rtmpMetadataDidArrived:(int)connectionId Meta:(NSDictionary*)meta;

-(void)avcHeaderDidArrived:(int)connectionId timescale:(int)timescale buffer:(uint8_t *)buffer len:(uint32_t)len;
-(void)hevcHeaderDidArrived:(int)connectionId timescale:(int)timescale buffer:(uint8_t *)buffer len:(uint32_t)len;
-(void)videoFrameDidArrived:(int)connectionId timestamp:(uint64_t)timestamp composition_time_offset:(uint32_t)composition_time_offset buffer:(const uint8_t *)buffer len:(int)len key_frame:(bool)key_frame;

-(void)aacHeaderDidArrived:(int)connectionId timescale:(int)timescale buffer:(const uint8_t *)buffer len:(size_t)len;
-(void)mp3HeaderDidArrived:(int)connectionId timescale:(int)timescale buffer:(const uint8_t *)buffer len:(size_t)len;
-(void)audioFrameDidArrived:(int)connectionId timestamp:(uint64_t)timestamp buffer:(const uint8_t *)buffer len:(int)len;
/// NOTE: this function will be called only when externalDecoding set to true in StreamConfig
-(void)videoFrameDecoded:(CMSampleBufferRef)frame;

@end
