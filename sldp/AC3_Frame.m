//
//  AC3_frame.m
//  sldp
//
//  Created by Denis Slobodskoy on 20.10.2022.
//  Copyright © 2022 Softvelum, LLC. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "AC3_Frame.h"

@implementation AC3_Frame

-(id)init {
    self = [super init];
    if (self) {
        [self reset];
    }
    return self;
}

-(void)reset {
    _sample_rate = 0;
    _frame_size = 0;
    _buffer = 0;
    _buffer_size = 0;
}

@end
