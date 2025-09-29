#import <Foundation/Foundation.h>
#import <CoreMedia/CoreMedia.h>

typedef NS_ENUM(int, SldpStreamMode) {
    kSldpStreamModeVideoAudio = 0,
    kSldpStreamModeVideoOnly = 1,
    kSldpStreamModeAudioOnly = 2
};

typedef NS_ENUM(int, PlayerSrtConnectMode) {
    kPlayerSrtConnectModePull = 0,
    kPlayerSrtConnectModeListen = 1,
    kPlayerSrtConnectModeRendezvous = 2
};

extern const int SLDP_SRT_MIN_PASSPHRASE_LEN;
extern const int SLDP_SRT_MAX_PASSPHRASE_LEN;
extern const int SLDP_SRT_MAX_STREAMID_LEN;



@interface StreamConfig : NSObject

-(id _Nullable)init:(NSURL* _Nonnull)url;
-(id _Nullable)init:(NSURL* _Nonnull)url parseQuery:(BOOL) parseQuery;

@property NSURL* _Nonnull uri;  //Stream URL
@property int32_t buffering;    //Pre-buffering in ms; playback will start only when specifed duration of playback frames is accumulated
@property int32_t offset;       //SLDP offset; read this article for details: https://blog.wmspanel.com/2017/08/decrease-start-time-sldp-using-offset.html
@property int32_t threshold;    // Starvation threshold in ms; when no data is coming for specific amount of time, connectionStateDidChangeId with status = kStreamStatusNoData will be send
@property SldpStreamMode mode;  // Playback mode: video+audio, video only, audio only
@property PlayerSrtConnectMode connectMode; //SRT connect mode: Pull, Listen, Rendezvous
@property CMVideoDimensions initialResolution; //SLDP: when set to non-zero, will select stream with specified resolution for ABR; read this for details: https://blog.wmspanel.com/2019/08/abr-sldp-real-time-streaming.html
@property int32_t preferredBitrate;         //SLDP: when set to non-zero, will select specifed resolution for ABR stream
@property NSString* _Nullable passphrase;   // SRT passphrase ( https://github.com/Haivision/srt/blob/master/docs/API/API-socket-options.md#SRTO_PASSPHRASE )
@property int32_t pbkeylen;                 // SRT key length ( https://github.com/Haivision/srt/blob/master/docs/API/API-socket-options.md#srto_pbkeylen )
@property int32_t latency;                  // SRT latency ( https://github.com/Haivision/srt/blob/master/docs/API/API-socket-options.md#SRTO_LATENCY )
@property int32_t maxbw;                    // SRT maximum send bandwidth ( https://github.com/Haivision/srt/blob/master/docs/API/API-socket-options.md#SRTO_MAXBW )
@property NSString* _Nullable streamid;         //SRT stream ID ( https://github.com/Haivision/srt/blob/master/docs/API/API-socket-options.md#SRTO_STREAMID )
@property BOOL steady;                          // SLDP synchonized playback ( https://blog.wmspanel.com/2020/02/synchronized-simultaneous-playback-sldp.html )
@property BOOL disableMediaSync;                // When set to YES, use AVSampleBufferRenderSynchronizer to play frames by timestamps. When set to NO, will play frames sequentally
@property BOOL externalDecoding;                // When set to YES, will decode video frames by VTDecompressionSession. When set to NO, will send compressed frames to display layer
@property BOOL videoChatMode;                   // When set to YES, audio session will be configured for playback and recording; otherwise audio session is configured for playback

@end
