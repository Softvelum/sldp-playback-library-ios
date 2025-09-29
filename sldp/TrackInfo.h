typedef NS_ENUM(int, TrackType) {
    kTrackTypeVideo = 0,
    kTrackTypeAudio = 1
};

@interface TrackInfo : NSObject

@property int trackId;
@property TrackType type;

@property int width;
@property int height;
@property int bandwidth;

-(TrackInfo*)initWithId:(int)trackId;

@end
