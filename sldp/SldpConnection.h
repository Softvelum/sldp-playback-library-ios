#import "SldpTcpConnection.h"
#import "SldpHttpParser.h"

@interface SldpConnection : SldpTcpConnection<SldpHttpParserDelegate>

@property (weak, readonly) id<SldpStreamListener> streamListener;
@property (readonly) int32_t offset;
@property (readonly) int32_t bitrate;
@property (readonly) BOOL steadyEnabled;

- (id)initWithConnectionId:(int)connectionId uri:(NSURL*)uri offset:(int32_t)offset useSSL:(bool)useSSL mode:(int)mode
                   bitrate:(int32_t)bitrate delay:(int32_t)delay
        connectionListener:(id<SldpConnectionListener>) connectionListener streamListener:(id<SldpStreamListener>)streamListener;

-(long)getAudioStreamIdWithBitrate:(int32_t)bitrate;
@end
