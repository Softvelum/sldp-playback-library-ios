#import <Foundation/Foundation.h>
#import "SldpPlayRequest.h"

@interface SldpPlayRequest() {
}
@end

@implementation SldpPlayRequest

-(id)initWithStreamId:(int)streamId {
    self = [super init];
    _streamId = streamId;
    _offset   = 0;
    _duration = 0;    
    return self;
}
@end
