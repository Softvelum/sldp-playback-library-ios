#import <Foundation/Foundation.h>
#import "SldpMediaPlayerV11.h"

// Hardware renderers may be unavailable on a headless Mac. Only their lifecycle
// methods are needed to verify the production synchronizer coordination.
@interface TestRenderer : NSObject
-(void)flush;
-(void)flushAndRemoveImage;
-(AVQueuedSampleBufferRenderingStatus)status;
-(void)enqueueSampleBuffer:(CMSampleBufferRef)sampleBuffer;
@end
@implementation TestRenderer
-(void)flush {}
-(void)flushAndRemoveImage {}
-(AVQueuedSampleBufferRenderingStatus)status { return AVQueuedSampleBufferRenderingStatusRendering; }
-(void)enqueueSampleBuffer:(CMSampleBufferRef)sampleBuffer {}
@end

@interface TestSynchronizer : AVSampleBufferRenderSynchronizer
@property NSMutableArray *attached;
@property NSMutableArray *removals;
@property float testRate;
@property (copy) void (^beforeAdd)(void);
-(void)finishRemovals;
@end
@implementation TestSynchronizer
-(id)init { if ((self = [super init])) { _attached = [NSMutableArray new]; _removals = [NSMutableArray new]; _testRate = 1.0; } return self; }
-(NSArray *)renderers { return [_attached copy]; }
-(float)rate { return _testRate; }
-(void)setRate:(float)rate time:(CMTime)time { _testRate = rate; }
-(void)addRenderer:(id<AVQueuedSampleBufferRendering>)renderer {
    NSCAssert(![_attached containsObject:renderer], @"Duplicate renderer attachment");
    void (^beforeAdd)(void) = self.beforeAdd;
    self.beforeAdd = nil;
    if (beforeAdd) { beforeAdd(); }
    [_attached addObject:renderer];
}
-(void)removeRenderer:(id<AVQueuedSampleBufferRendering>)renderer atTime:(CMTime)time completionHandler:(void (^)(BOOL))completion {
    if (![_attached containsObject:renderer]) { completion(NO); return; }
    [_removals addObject:@[renderer, [completion copy]]];
}
-(void)finishRemovals {
    while (_removals.count) {
        NSArray *entry = _removals.firstObject;
        [_removals removeObjectAtIndex:0];
        BOOL removed = [_attached containsObject:entry[0]];
        [_attached removeObject:entry[0]];
        void (^completion)(BOOL) = entry[1];
        completion(removed);
    }
}
@end

int main(void) {
    @autoreleasepool {
        SldpMediaPlayerV11 *player = [[SldpMediaPlayerV11 alloc] initWithBuffer:1500 andThreshold:1000 externalDecoding:NO];
        TestSynchronizer *sync = [TestSynchronizer new];
        AVSampleBufferDisplayLayer *video = (AVSampleBufferDisplayLayer *)[TestRenderer new];
        AVSampleBufferAudioRenderer *audio = (AVSampleBufferAudioRenderer *)[TestRenderer new];
        player.renderSynchronizer = sync;
        player.displayLayer = video;
        player.audioRenderer = audio;
        player.numVideoFrames = 3;
        [sync addRenderer:audio]; [sync addRenderer:video];

        [player setVideoRenderingSuspended:YES];
        [sync finishRemovals];
        NSCAssert([sync.renderers containsObject:audio], @"Background must retain audio");
        NSCAssert(![sync.renderers containsObject:video], @"Background must detach video");
        NSCAssert(sync.rate == 1.0, @"Background must not pause the timeline");
        player.timescaleVideo = 1000;
        [player writeVideoFrameWithTimestamp:9000 composition_time_offset:0 buffer:NULL len:0 key_frame:NO];
        NSCAssert(player.numVideoFrames == 3 && player.videoPtsMs == 9000, @"Background must track video timestamps without decoding");
        [player setVideoRenderingSuspended:NO];
        NSCAssert([sync.renderers containsObject:video], @"Foreground must restore video");
        NSCAssert(sync.rate == 1.0, @"Foreground must not pause audio");
        [player writeVideoFrameWithTimestamp:10000 composition_time_offset:0 buffer:NULL len:0 key_frame:NO];
        NSCAssert(player.numVideoFrames == 3 && player.videoPtsMs == 10000, @"Return must wait for a keyframe without losing timeline statistics");

        [player setVideoRenderingSuspended:YES];
        [player setVideoRenderingSuspended:NO];
        [sync finishRemovals];
        NSCAssert(sync.renderers.count == 2, @"Rapid return must restore exactly one audio/video pair");

        [player setVideoRenderingSuspended:YES];
        [player stop:NO];
        [sync finishRemovals];
        NSCAssert(![sync.renderers containsObject:video], @"Delayed detach must not resurrect stopped video");
        NSCAssert(sync.rate == 0.0, @"Stop must still stop the timeline");
        SldpMediaPlayerV11 *racing = [[SldpMediaPlayerV11 alloc] initWithBuffer:1500 andThreshold:1000 externalDecoding:NO];
        TestSynchronizer *raceSync = [TestSynchronizer new];
        AVSampleBufferDisplayLayer *raceVideo = (AVSampleBufferDisplayLayer *)[TestRenderer new];
        AVSampleBufferAudioRenderer *raceAudio = (AVSampleBufferAudioRenderer *)[TestRenderer new];
        racing.renderSynchronizer = raceSync; racing.displayLayer = raceVideo; racing.audioRenderer = raceAudio;
        racing.numVideoFrames = 3;
        [raceSync addRenderer:raceAudio]; [raceSync addRenderer:raceVideo];
        [racing setVideoRenderingSuspended:YES]; [raceSync finishRemovals];
        dispatch_semaphore_t stopped = dispatch_semaphore_create(0);
        dispatch_semaphore_t enteredStop = dispatch_semaphore_create(0);
        __block BOOL stoppedDuringAdd = NO;
        raceSync.beforeAdd = ^{
            dispatch_async(dispatch_get_global_queue(QOS_CLASS_DEFAULT, 0), ^{
                dispatch_semaphore_signal(enteredStop);
                [racing stop:NO]; dispatch_semaphore_signal(stopped);
            });
            NSCAssert(dispatch_semaphore_wait(enteredStop, dispatch_time(DISPATCH_TIME_NOW, NSEC_PER_SEC)) == 0, @"Concurrent stopper must start");
            stoppedDuringAdd = dispatch_semaphore_wait(stopped, dispatch_time(DISPATCH_TIME_NOW, 50 * NSEC_PER_MSEC)) == 0;
        };
        [racing setVideoRenderingSuspended:NO];
        if (!stoppedDuringAdd) {
            NSCAssert(dispatch_semaphore_wait(stopped, dispatch_time(DISPATCH_TIME_NOW, NSEC_PER_SEC)) == 0, @"Stop must complete after restoration releases its lock");
        }
        [raceSync finishRemovals];
        NSCAssert(!stoppedDuringAdd, @"Stop must serialize with restoration check/add");
        NSCAssert(![raceSync.renderers containsObject:raceVideo], @"Concurrent stop must not leave restored video alive");
        SldpMediaPlayerV11 *audioOnly = [[SldpMediaPlayerV11 alloc] initWithBuffer:1500 andThreshold:1000 externalDecoding:NO];
        TestSynchronizer *audioSync = [TestSynchronizer new];
        audioOnly.renderSynchronizer = audioSync;
        audioOnly.audioRenderer = (AVSampleBufferAudioRenderer *)[TestRenderer new];
        [audioSync addRenderer:audioOnly.audioRenderer];
        audioOnly.playbackType = kPlaybackTypeAudioOnly;
        audioOnly.numAudioFrames = 5; audioOnly.timescaleAudio = 48000;
        audioOnly.audioZeroPtsMs = 0; audioOnly.rate = 1.0;
        audioOnly.zeroTime = kCMTimeZero;
        AudioStreamBasicDescription format = { .mSampleRate = 48000, .mFormatID = kAudioFormatMPEG4AAC, .mFramesPerPacket = 1024, .mChannelsPerFrame = 1 };
        CMAudioFormatDescriptionRef description;
        NSCAssert(CMAudioFormatDescriptionCreate(kCFAllocatorDefault, &format, 0, NULL, 0, NULL, NULL, &description) == noErr, @"Audio test format must be valid");
        audioOnly.audioDesc = description;
        [audioOnly setVideoRenderingSuspended:YES];
        uint8_t packet = 0;
        NSCAssert([audioOnly writeAudioFrameWithTimestamp:48000 numSamples:1024 buffer:&packet len:1], @"Audio-only packet must remain accepted");
        NSCAssert(audioOnly.numAudioFrames == 6 && audioSync.rate == 1.0, @"Audio-only streams must not reanchor or pause when video is suspended");
        [audioOnly stop:NO]; [audioSync finishRemovals];
        puts("Video suspension: background, return, rapid return, stop, overlapping stop and audio-only no-op passed");
    }
    return 0;
}
