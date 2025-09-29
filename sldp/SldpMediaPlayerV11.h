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

@end

