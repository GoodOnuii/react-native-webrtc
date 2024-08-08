#import "CaptureController.h"
#import "WebRTCModule.h"

@interface WebRTCModule (LKRTCMediaStream)
- (LKRTCVideoTrack *)createVideoTrackWithCaptureController:
    (CaptureController * (^)(LKRTCVideoSource *))captureControllerCreator;
- (NSArray *)createMediaStream:(NSArray<LKRTCMediaStreamTrack *> *)tracks;
@end
