#import <Foundation/Foundation.h>
#import "StreamInfoInternal.h"
#import "AC3_Reader.h"

@interface StreamInfoInternal() {
    bool init_;
}
@end

@implementation StreamInfoInternal
-(StreamInfoInternal*)initWithConnectionId:(int)connectionId streamId:(int)streamId type:(StreamTypeInternal)type {

    self = [super init];
    
    _connectionId = connectionId;
    _streamId = streamId;
    _type = type;
    
    _state = kStreamStateInternalStop;
    
    _hasStartTs = false;
    _startTs = 0;
    
    return self;
}

-(uint8_t)ac3_channel_count {
    return [AC3_Reader ac3_channel_count: _ac3_channel_layout];
}


@end
