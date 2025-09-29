#import <Network/Network.h>
#import "SldpByteBuffer.h"
#import "SldpPlayRequest.h"
#import "BaseConnection.h"


@interface SldpTcpConnection : BaseConnection <NSStreamDelegate>

// Network.framework API on iOS 12+
@property (readonly) nw_connection_t streamConnection;
@property (readonly) dispatch_queue_t streamConnectionQueue;
@property (readonly) dispatch_queue_t dataQueue;
@property (readonly) dispatch_queue_t verifyQueue;

- (id)initWithConnectionId:(int)connectionId host:(NSString*)host port:(int)port useSSL:(bool)useSSL mode:(SldpStreamMode)mode connectionListener:(id<SldpConnectionListener>) connectionListener;
- (Boolean)Append:(const void*)data length:(int)len;
- (Boolean)Send:(const void*)data length:(int)len;
- (Boolean)Send:(NSString*)s;
-(Boolean)AppendByte:(uint8_t)value;
-(Boolean)SendByte:(uint8_t)value;
-(void)sendBuffer;
- (void)OnConnect;
//- (int)OnReceive:(const void*)data length:(int)len;
- (void)OnReceive:(SldpByteBuffer*)buffer;
- (void)Close;
- (void)skipRecvBuffer: (int)bytesToSkip;

- (uint64_t)getBytesSent;
- (uint64_t)getBytesRecv;

-(void)sendPlayWithStreams:(NSArray<SldpPlayRequest*>*)playRequests;
-(void)sendCancelWithStreams:(NSArray*)streams;

-(NSDictionary*)getStreams;


// @property (weak, readonly) id<SldpConnectionListener> connectionListener;

-(void)notifyOnStateChange:(SldpConnectionState)state Status:(int)status;
-(NSString*)base64Encode:(NSString *)s;
@end






