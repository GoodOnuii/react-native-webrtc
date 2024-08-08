#import <AVFoundation/AVFoundation.h>
#import <objc/runtime.h>

#import <React/RCTLog.h>
#import <React/RCTView.h>

#import <LiveKitWebRTC/RTCMediaStream.h>
#if TARGET_OS_OSX
#import <LiveKitWebRTC/RTCMTLNSVideoView.h>
#else
#import <LiveKitWebRTC/RTCMTLVideoView.h>
#endif
#import <LiveKitWebRTC/RTCCVPixelBuffer.h>
#import <LiveKitWebRTC/RTCVideoFrame.h>
#import <LiveKitWebRTC/RTCVideoTrack.h>

#import "RTCVideoViewManager.h"
#import "WebRTCModule.h"

/**
 * In the fashion of
 * https://www.w3.org/TR/html5/embedded-content-0.html#dom-video-videowidth
 * and https://www.w3.org/TR/html5/rendering.html#video-object-fit, resembles
 * the CSS style {@code object-fit}.
 */
typedef NS_ENUM(NSInteger, LKRTCVideoViewObjectFit) {
    /**
     * The contain value defined by https://www.w3.org/TR/css3-images/#object-fit:
     *
     * The replaced content is sized to maintain its aspect ratio while fitting
     * within the element's content box.
     */
    LKRTCVideoViewObjectFitContain = 1,
    /**
     * The cover value defined by https://www.w3.org/TR/css3-images/#object-fit:
     *
     * The replaced content is sized to maintain its aspect ratio while filling
     * the element's entire content box.
     */
    LKRTCVideoViewObjectFitCover
};

/**
 * Implements an equivalent of {@code HTMLVideoElement} i.e. Web's video
 * element.
 */
@interface LKRTCVideoView : RCTView

/**
 * The indicator which determines whether this {@code LKRTCVideoView} is to mirror
 * the video specified by {@link #videoTrack} during its rendering. Typically,
 * applications choose to mirror the front/user-facing camera.
 */
@property(nonatomic) BOOL mirror;

/**
 * In the fashion of
 * https://www.w3.org/TR/html5/embedded-content-0.html#dom-video-videowidth
 * and https://www.w3.org/TR/html5/rendering.html#video-object-fit, resembles
 * the CSS style {@code object-fit}.
 */
@property(nonatomic) LKRTCVideoViewObjectFit objectFit;

/**
 * The {@link RRTCVideoRenderer} which implements the actual rendering.
 */
#if TARGET_OS_OSX
@property(nonatomic, readonly) LKRTCMTLNSVideoView *videoView;
#else
@property(nonatomic, readonly) LKRTCMTLVideoView *videoView;
#endif

/**
 * The {@link LKRTCVideoTrack}, if any, which this instance renders.
 */
@property(nonatomic, strong) LKRTCVideoTrack *videoTrack;

/**
 * Reference to the main WebRTC RN module.
 */
@property(nonatomic, weak) WebRTCModule *module;

@end

@implementation LKRTCVideoView

@synthesize videoView = _videoView;

/**
 * Tells this view that its window object changed.
 */
- (void)didMoveToWindow {
    // This LKRTCVideoView strongly retains its videoTrack. The latter strongly
    // retains the former as well though because LKRTCVideoTrack strongly retains
    // the LKRTCVideoRenderers added to it. In other words, there is a cycle of
    // strong retainments. In order to break the cycle, and avoid a leak,
    // have this LKRTCVideoView as the LKRTCVideoRenderer of its
    // videoTrack only while this view resides in a window.
    LKRTCVideoTrack *videoTrack = self.videoTrack;

    if (videoTrack) {
        if (self.window) {
            dispatch_async(_module.workerQueue, ^{
                [videoTrack addRenderer:self.videoView];
            });
        } else {
            dispatch_async(_module.workerQueue, ^{
                [videoTrack removeRenderer:self.videoView];
            });
        }
    }
}

/**
 * Initializes and returns a newly allocated view object with the specified
 * frame rectangle.
 *
 * @param frame The frame rectangle for the view, measured in points.
 */
- (instancetype)initWithFrame:(CGRect)frame {
    if (self = [super initWithFrame:frame]) {
#if TARGET_OS_OSX
        LKRTCMTLNSVideoView *subview = [[LKRTCMTLNSVideoView alloc] initWithFrame:CGRectZero];
        subview.wantsLayer = true;
        _videoView = subview;
#else
        LKRTCMTLVideoView *subview = [[LKRTCMTLVideoView alloc] initWithFrame:CGRectZero];
        _videoView = subview;
#endif
        [self addSubview:self.videoView];
    }

    return self;
}

#if TARGET_OS_OSX
- (void)layout {
  [super layout];
#else
- (void)layoutSubviews {
  [super layoutSubviews];
#endif

  CGRect bounds = self.bounds;
  self.videoView.frame = bounds;
}

/**
 * Implements the setter of the {@link #mirror} property of this
 * {@code LKRTCVideoView}.
 *
 * @param mirror The value to set on the {@code mirror} property of this
 * {@code LKRTCVideoView}.
 */
- (void)setMirror:(BOOL)mirror {
    if (_mirror != mirror) {
        _mirror = mirror;

        self.videoView.transform = mirror ? CGAffineTransformMakeScale(-1.0, 1.0) : CGAffineTransformIdentity;
    }
}

/**
 * Implements the setter of the {@link #objectFit} property of this
 * {@code LKRTCVideoView}.
 *
 * @param objectFit The value to set on the {@code objectFit} property of this
 * {@code LKRTCVideoView}.
 */
- (void)setObjectFit:(LKRTCVideoViewObjectFit)fit {
    if (_objectFit != fit) {
        _objectFit = fit;

#if !TARGET_OS_OSX
        if (fit == LKRTCVideoViewObjectFitCover) {
            self.videoView.videoContentMode = UIViewContentModeScaleAspectFill;
        } else {
            self.videoView.videoContentMode = UIViewContentModeScaleAspectFit;
        }
#endif
    }
}

/**
 * Implements the setter of the {@link #videoTrack} property of this
 * {@code LKRTCVideoView}.
 *
 * @param videoTrack The value to set on the {@code videoTrack} property of this
 * {@code LKRTCVideoView}.
 */
- (void)setVideoTrack:(LKRTCVideoTrack *)videoTrack {
    LKRTCVideoTrack *oldValue = self.videoTrack;

    if (oldValue != videoTrack) {
        if (oldValue) {
            dispatch_async(_module.workerQueue, ^{
                [oldValue removeRenderer:self.videoView];
            });
        }

        _videoTrack = videoTrack;

        // Clear the videoView by rendering a 2x2 blank frame.
        CVPixelBufferRef pixelBuffer;
        CVReturn err = CVPixelBufferCreate(NULL, 2, 2, kCVPixelFormatType_32BGRA, NULL, &pixelBuffer);
        if (err == kCVReturnSuccess) {
            const int kBytesPerPixel = 4;
            CVPixelBufferLockBaseAddress(pixelBuffer, 0);
            int bufferWidth = (int)CVPixelBufferGetWidth(pixelBuffer);
            int bufferHeight = (int)CVPixelBufferGetHeight(pixelBuffer);
            size_t bytesPerRow = CVPixelBufferGetBytesPerRow(pixelBuffer);
            uint8_t *baseAddress = CVPixelBufferGetBaseAddress(pixelBuffer);

            for (int row = 0; row < bufferHeight; row++) {
                uint8_t *pixel = baseAddress + row * bytesPerRow;
                for (int column = 0; column < bufferWidth; column++) {
                    pixel[0] = 0;  // BGRA, Blue value
                    pixel[1] = 0;  // Green value
                    pixel[2] = 0;  // Red value
                    pixel[3] = 0;  // Alpha value
                    pixel += kBytesPerPixel;
                }
            }

            CVPixelBufferUnlockBaseAddress(pixelBuffer, 0);
            int64_t time = (int64_t)(CFAbsoluteTimeGetCurrent() * 1000000000);
            LKRTCCVPixelBuffer *buffer = [[LKRTCCVPixelBuffer alloc] initWithPixelBuffer:pixelBuffer];
            LKRTCVideoFrame *frame = [[[LKRTCVideoFrame alloc] initWithBuffer:buffer
                                                                 rotation:RTCVideoRotation_0
                                                              timeStampNs:time] newI420VideoFrame];

            [self.videoView renderFrame:frame];

            CVPixelBufferRelease(pixelBuffer);
        }

        // See "didMoveToWindow" above.
        if (videoTrack && self.window) {
            dispatch_async(_module.workerQueue, ^{
                [videoTrack addRenderer:self.videoView];
            });
        }
    }
}

@end

@implementation LKRTCVideoViewManager

RCT_EXPORT_MODULE()

- (RCTView *)view {
    LKRTCVideoView *v = [[LKRTCVideoView alloc] init];
    v.module = [self.bridge moduleForName:@"WebRTCModule"];
    v.clipsToBounds = YES;
    return v;
}

- (dispatch_queue_t)methodQueue {
    return dispatch_get_main_queue();
}

#pragma mark - View properties

RCT_EXPORT_VIEW_PROPERTY(mirror, BOOL)

/**
 * In the fashion of
 * https://www.w3.org/TR/html5/embedded-content-0.html#dom-video-videowidth
 * and https://www.w3.org/TR/html5/rendering.html#video-object-fit, resembles
 * the CSS style {@code object-fit}.
 */
RCT_CUSTOM_VIEW_PROPERTY(objectFit, NSString *, LKRTCVideoView) {
    NSString *fitStr = json;
    LKRTCVideoViewObjectFit fit =
        (fitStr && [fitStr isEqualToString:@"cover"]) ? LKRTCVideoViewObjectFitCover : LKRTCVideoViewObjectFitContain;

    view.objectFit = fit;
}

RCT_CUSTOM_VIEW_PROPERTY(streamURL, NSString *, LKRTCVideoView) {
    if (!json) {
        view.videoTrack = nil;
        return;
    }

    NSString *streamReactTag = json;
    WebRTCModule *module = view.module;

    dispatch_async(module.workerQueue, ^{
        LKRTCMediaStream *stream = [module streamForReactTag:streamReactTag];
        NSArray *videoTracks = stream ? stream.videoTracks : @[];
        LKRTCVideoTrack *videoTrack = [videoTracks firstObject];
        if (!videoTrack) {
            RCTLogWarn(@"No video stream for react tag: %@", streamReactTag);
        } else {
            dispatch_async(dispatch_get_main_queue(), ^{
                view.videoTrack = videoTrack;
            });
        }
    });
}

+ (BOOL)requiresMainQueueSetup {
    return NO;
}

@end
