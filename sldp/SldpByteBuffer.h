#import <Foundation/Foundation.h>

@interface SldpByteBuffer : NSObject 

@property (readonly) uint8_t *data;
@property (readonly) int limit;
@property (readonly) int capacity;
@property (readonly) int bufferLimit;
@property uint64_t bytesSent;
@property (readonly) uint64_t bytesRecv;

- (id)initWithCapacity:(int)capacity bufferLimit:(int)maxCapacity;
- (id)initWithCapacity:(int)capacity;
- (void)reset;
- (void)rewind:(int)pos;
- (void)rewindBy:(int)offset;
- (void)skip:(int)bytesToSkip;
- (Boolean)put:(const void *)src len:(int)len;
- (Boolean)fillZeroes:(int)len;
- (Boolean)send:(NSOutputStream *)s;
- (Boolean)recv:(NSInputStream *)s;
- (Boolean)hasBytesToSend;
- (void)incBytesSent:(int) count;
- (Boolean)reserve:(int)len;
-(uint8_t*)nextData;

@end
