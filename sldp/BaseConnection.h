#import <Network/Network.h>
#import "SldpByteBuffer.h"
#import "SldpPlayRequest.h"
#import "StreamConfig.h"
#import "SldpConnectionListener.h"
#import "SldpStreamListener.h"

typedef NS_ENUM(int, ConnectionProtocol) {
    kConnectionProtocolUnknown = 0,
    kConnectionProtocolSldp = 1,
    kConnectionProtocolRtmp = 2,
    kConnectionProtocolIcecast = 3,
    kConnectionProtocolSrt = 4
};

@interface BaseConnection : NSObject

@property (readonly) int connectionID;
@property (readonly) NSString* host;
@property (readonly) int port;
@property (readonly) SldpStreamMode mode;
@property (readonly) bool inactivity_triggered;


- (id)initWithConnectionId:(int)connectionId host:(NSString*)host port:(int)port mode:(SldpStreamMode)mode connectionListener:(id<SldpConnectionListener>) connectionListener;

- (void)OnConnect;
- (void)OnReceive:(SldpByteBuffer*)buffer;
- (void)Close;
- (void)startInactivityTimer;
- (void)cancelInactivityTimer;
- (void)resetInactivityTimer;

- (void)OnSend;
- (uint64_t)getBytesSent;
- (uint64_t)getBytesRecv;

-(void)sendPlayWithStreams:(NSArray<SldpPlayRequest*>*)playRequests;
-(void)sendCancelWithStreams:(NSArray*)streams;

-(NSDictionary*)getStreams;
-(long)getAudioStreamIdWithBitrate:(int32_t)bitrate;

-(long)getHighestVideoId;
-(long)getLowestVideoId;
-(long)getHigherVideoId:(int)streamId;
-(long)getMatchVideoId:(CMVideoDimensions)resolution;

@property (weak, readonly) id<SldpConnectionListener> connectionListener;

-(void)notifyOnStateChange:(SldpConnectionState)state Status:(int)status;
@end






