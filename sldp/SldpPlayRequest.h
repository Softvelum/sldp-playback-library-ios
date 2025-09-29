@interface SldpPlayRequest : NSObject {
}

@property int streamId;
@property uint64_t offset;
@property uint64_t duration;

-(id)initWithStreamId:(int)streamId;

@end
