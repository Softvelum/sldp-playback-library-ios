//
//  BaseConnection.m
//  sldp
//
//  Created by Denis Slobodskoy on 24/09/2019.
//  Copyright © 2019 Softvelum, LLC. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "BaseConnection.h"

@implementation BaseConnection
{
    int _inactivityCount;
    dispatch_source_t _inactivityTimer;
}

- (id)initWithConnectionId:(int)connectionId host:(NSString*)host port:(int)port mode:(SldpStreamMode)mode connectionListener:(id<SldpConnectionListener>) connectionListener {
    self = [super init];
    
    _connectionID = connectionId;
    _host = host;
    _port = port;
    _mode = mode;
    _connectionListener = connectionListener;
    
    return self;
}

- (void)startInactivityTimer {
    [self cancelInactivityTimer];
    _inactivityCount = 0;
    
    dispatch_queue_t queue = dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0);
    double interval = 2.0f;
    
    _inactivityTimer = dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER, 0, 0, queue);
    if (_inactivityTimer) {
        dispatch_source_set_timer(_inactivityTimer, dispatch_time(DISPATCH_TIME_NOW, interval * NSEC_PER_SEC), interval * NSEC_PER_SEC, (1ull * NSEC_PER_SEC) / 10);
        dispatch_source_set_event_handler(_inactivityTimer, ^{
            self->_inactivityCount++;
            if(self->_inactivityCount > 5) {
                NSLog(@"inactivity timer expired");
                self->_inactivity_triggered = true;
                [self Close];
            }
        });
        dispatch_resume(_inactivityTimer);
    }
}

- (void)cancelInactivityTimer {
    if (_inactivityTimer) {
        dispatch_source_cancel(_inactivityTimer);
        _inactivityTimer = nil;
    }
}

-(void)resetInactivityTimer {
    self->_inactivityCount = 0;
}

-(void) Close {
    NSLog(@"connection closed");
    //NSLog(@"%@", [NSThread callStackSymbols]);
    
    [self cancelInactivityTimer];
}

-(long)getHighestVideoId {
    return -1;
}

-(long)getLowestVideoId {
    return -1;
}

-(long)getHigherVideoId:(int)streamId {
    return -1;
}

-(long)getMatchVideoId:(CMVideoDimensions)resolution {
    return -1;
}

-(NSDictionary*)getStreams {
    NSDictionary* streams = @{};
    return streams;
}

-(long)getAudioStreamIdWithBitrate:(int32_t)bitrate {
    return -1;
}


-(void)OnConnect {
    [self notifyOnStateChange:kSldpConnectionStateConnected Status:kSldpConnectionStatusSuccess];
}

-(void)OnSend {
    return;
}

-(void)OnReceive:(SldpByteBuffer*)buffer {
    
}

- (uint64_t)getBytesSent {
    return 0;
}

- (uint64_t)getBytesRecv {
    return 0;
}

-(void)sendPlayWithStreams:(NSArray<SldpPlayRequest*>*)playRequests {
}

-(void)sendCancelWithStreams:(NSArray*)streams {
    
}


-(void)notifyOnStateChange:(SldpConnectionState)state Status:(int)status {
    [self.connectionListener connectionStateDidChangeId: _connectionID State:state Status:status];
}


@end
