#import "SldpBaseMediaPlayer.h"

API_AVAILABLE(ios(11.0))
@interface SldpMediaPlayerV11 : SldpBaseMediaPlayer

@property AVSampleBufferRenderSynchronizer *renderSynchronizer;
@property NSObject *timeObserverToken;

@property AVSampleBufferAudioRenderer *audioRenderer;
@property CMFormatDescriptionRef audioDesc;
@property uint64_t numAudioFrames;

@property uint64_t audioZeroBiasTs;
@property NSTimer* steadyWaitTimer;

// Suspend video presentation while preserving the audio timeline and connection.
- (void)setVideoRenderingSuspended:(BOOL)suspended;

@end

