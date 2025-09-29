#import <Foundation/Foundation.h>
#import "TrackInfo.h"

@implementation TrackInfo

-(TrackInfo*)initWithId:(int)trackId {
    self = [super init];
    if (self) {
        _trackId = trackId;
    }
    return self;
}

@end
