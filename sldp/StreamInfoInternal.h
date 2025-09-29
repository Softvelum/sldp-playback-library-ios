typedef NS_ENUM(int, StreamTypeInternal) {
    kStreamTypeInternalUnknown = 0,
    kStreamTypeInternalVideo = 1,
    kStreamTypeInternalAudio = 2
};

typedef NS_ENUM(int, StreamStateInternal) {
    kStreamStateInternalStop = 0,
    kStreamStateInternalPlay = 1
};

typedef NS_ENUM(int, AudioCodecType) {
    kAudioCodecTypeAac  = 0,
    kAudioCodecTypeMp3  = 1,
    kAudioCodecTypeOpus = 2,
    kAudioCodecTypeAc3  = 3,
    kAudioCodecTypeEac3 = 4
};

typedef NS_ENUM(int, VideoCodecType) {
    kVideoCodecTypeAvc = 0,
    kVideoCodecTypeHevc = 1
};

@interface StreamInfoInternal : NSObject {
}

@property int connectionId;
@property int streamId;

@property int timescale;

@property NSString* stream;
@property NSString* codec;
@property int bandwidth;

@property AudioCodecType audioCodec;
@property VideoCodecType videoCodec;

@property int offset;
@property int duration;
@property int sn;

@property StreamTypeInternal type;

@property StreamStateInternal state;

@property int width;
@property int height;

@property NSData* extradata;

@property int ac3_sample_rate;
@property uint8_t ac3_channel_layout;

@property bool hasStartTs;
@property uint64_t startTs;

-(StreamInfoInternal*)initWithConnectionId:(int)connectionId streamId:(int)streamId type:(StreamTypeInternal)type;
//-(uint8_t)ac3_channel_count;

@end
