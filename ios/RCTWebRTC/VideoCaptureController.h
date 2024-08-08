#if !TARGET_OS_TV

#import <Foundation/Foundation.h>
#import <LiveKitWebRTC/RTCCameraVideoCapturer.h>

#import "CaptureController.h"

@interface VideoCaptureController : CaptureController
@property(nonatomic, readonly, strong) AVCaptureDeviceFormat *selectedFormat;
@property(nonatomic, readonly, assign) int frameRate;

- (instancetype)initWithCapturer:(LKRTCCameraVideoCapturer *)capturer andConstraints:(NSDictionary *)constraints;
- (void)startCapture;
- (void)stopCapture;
- (void)switchCamera;

@end
#endif
