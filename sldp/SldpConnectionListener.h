#import <CoreMedia/CoreMedia.h>

typedef NS_ENUM(int, SldpConnectionState) {
    kSldpConnectionStateInitialized,
    kSldpConnectionStateConnected,
    kSldpConnectionStateSetup,
    kSldpConnectionStatePlay,
    kSldpConnectionStateDisconnected,
    kSldpConnectionStateSteadySupportCheck,
    kSldpConnectionStateListen,
    kSldpConnectionStateBuffering
};

typedef NS_ENUM(int, SldpConnectionStatus) {
    kSldpConnectionStatusSuccess,
    kSldpConnectionStatusAuthFail,
    kSldpConnectionStatusConnectionFail,
    kSldpConnectionStatusHandshakeFail,
    kSldpConnectionStatusUnknownFail,
    kSldpConnectionStatusNoData,
    kSldpConnectionPlaybackFail,
    kSldpConnectionSteadyUnsupported
};

@protocol SldpConnectionListener<NSObject>

@required
-(void)connectionStateDidChangeId:(int)connectionId State:(SldpConnectionState)state Status:(SldpConnectionStatus)status;

@optional
-(void)icecastMetadataDidArrived:(int)connectionId Meta:(NSString*)meta;
-(void)rtmpMetadataDidArrived:(int)connectionId Meta:(NSDictionary*)meta;
-(void)videoFrameDecoded:(CMSampleBufferRef)frame;

@end
