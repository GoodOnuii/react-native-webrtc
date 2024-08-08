#import <objc/runtime.h>

#import <LiveKitWebRTC/RTCCameraVideoCapturer.h>
#import <LiveKitWebRTC/RTCMediaConstraints.h>
#import <LiveKitWebRTC/RTCMediaStreamTrack.h>
#import <LiveKitWebRTC/RTCVideoTrack.h>

#import "RTCMediaStreamTrack+React.h"
#import "WebRTCModule+RTCMediaStream.h"
#import "WebRTCModule+RTCPeerConnection.h"

#import "ScreenCaptureController.h"
#import "ScreenCapturer.h"
#import "TrackCapturerEventsEmitter.h"
#import "VideoCaptureController.h"

@implementation WebRTCModule (LKRTCMediaStream)

#pragma mark - getUserMedia

/**
 * Initializes a new {@link LKRTCAudioTrack} which satisfies the given constraints.
 *
 * @param constraints The {@code MediaStreamConstraints} which the new
 * {@code LKRTCAudioTrack} instance is to satisfy.
 */
- (LKRTCAudioTrack *)createAudioTrack:(NSDictionary *)constraints {
    NSString *trackId = [[NSUUID UUID] UUIDString];
    LKRTCAudioTrack *audioTrack = [self.peerConnectionFactory audioTrackWithTrackId:trackId];
    return audioTrack;
}
/**
 * Initializes a new {@link LKRTCVideoTrack} with the given capture controller
 */
- (LKRTCVideoTrack *)createVideoTrackWithCaptureController:
    (CaptureController * (^)(LKRTCVideoSource *))captureControllerCreator {
#if TARGET_OS_TV
    return nil;
#else

    LKRTCVideoSource *videoSource = [self.peerConnectionFactory videoSource];

    NSString *trackUUID = [[NSUUID UUID] UUIDString];
    LKRTCVideoTrack *videoTrack = [self.peerConnectionFactory videoTrackWithSource:videoSource trackId:trackUUID];

    CaptureController *captureController = captureControllerCreator(videoSource);
    videoTrack.captureController = captureController;
    [captureController startCapture];

    return videoTrack;
#endif
}
/**
 * Initializes a new {@link LKRTCMediaTrack} with the given tracks.
 *
 * @return An array with the mediaStreamId in index 0, and track infos in index 1.
 */
- (NSArray *)createMediaStream:(NSArray<LKRTCMediaStreamTrack *> *)tracks {
#if TARGET_OS_TV
    return nil;
#else
    NSString *mediaStreamId = [[NSUUID UUID] UUIDString];
    LKRTCMediaStream *mediaStream = [self.peerConnectionFactory mediaStreamWithStreamId:mediaStreamId];
    NSMutableArray<NSDictionary *> *trackInfos = [NSMutableArray array];

    for (LKRTCMediaStreamTrack *track in tracks) {
        if ([track.kind isEqualToString:@"audio"]) {
            [mediaStream addAudioTrack:(LKRTCAudioTrack *)track];
        } else if ([track.kind isEqualToString:@"video"]) {
            [mediaStream addVideoTrack:(LKRTCVideoTrack *)track];
        }

        NSString *trackId = track.trackId;

        self.localTracks[trackId] = track;

        NSDictionary *settings = @{};
        if ([track.kind isEqualToString:@"video"]) {
            LKRTCVideoTrack *videoTrack = (LKRTCVideoTrack *)track;
            if ([videoTrack.captureController isKindOfClass:[VideoCaptureController class]]) {
                VideoCaptureController *vcc = (VideoCaptureController *)videoTrack.captureController;
                AVCaptureDeviceFormat *format = vcc.selectedFormat;
                CMVideoDimensions dimensions = CMVideoFormatDescriptionGetDimensions(format.formatDescription);
                settings = @{@"height" : @(dimensions.height), @"width" : @(dimensions.width), @"frameRate" : @(30)};
            }
        }

        [trackInfos addObject:@{
            @"enabled" : @(track.isEnabled),
            @"id" : trackId,
            @"kind" : track.kind,
            @"readyState" : @"live",
            @"remote" : @(NO),
            @"settings" : settings
        }];
    }

    self.localStreams[mediaStreamId] = mediaStream;
    return @[ mediaStreamId, trackInfos ];
#endif
}

/**
 * Initializes a new {@link LKRTCVideoTrack} which satisfies the given constraints.
 */
- (LKRTCVideoTrack *)createVideoTrack:(NSDictionary *)constraints {
#if TARGET_OS_TV
    return nil;
#else
    LKRTCVideoSource *videoSource = [self.peerConnectionFactory videoSource];

    NSString *trackUUID = [[NSUUID UUID] UUIDString];
    LKRTCVideoTrack *videoTrack = [self.peerConnectionFactory videoTrackWithSource:videoSource trackId:trackUUID];

#if !TARGET_IPHONE_SIMULATOR
    LKRTCCameraVideoCapturer *videoCapturer = [[LKRTCCameraVideoCapturer alloc] initWithDelegate:videoSource];
    VideoCaptureController *videoCaptureController =
        [[VideoCaptureController alloc] initWithCapturer:videoCapturer andConstraints:constraints[@"video"]];
    videoTrack.captureController = videoCaptureController;
    [videoCaptureController startCapture];
#endif

    return videoTrack;
#endif
}

- (LKRTCVideoTrack *)createScreenCaptureVideoTrack {
#if TARGET_IPHONE_SIMULATOR || TARGET_OS_OSX || TARGET_OS_TV
    return nil;
#endif

    LKRTCVideoSource *videoSource = [self.peerConnectionFactory videoSourceForScreenCast:YES];

    NSString *trackUUID = [[NSUUID UUID] UUIDString];
    LKRTCVideoTrack *videoTrack = [self.peerConnectionFactory videoTrackWithSource:videoSource trackId:trackUUID];

    ScreenCapturer *screenCapturer = [[ScreenCapturer alloc] initWithDelegate:videoSource];
    ScreenCaptureController *screenCaptureController =
        [[ScreenCaptureController alloc] initWithCapturer:screenCapturer];

    TrackCapturerEventsEmitter *emitter = [[TrackCapturerEventsEmitter alloc] initWith:trackUUID webRTCModule:self];
    screenCaptureController.eventsDelegate = emitter;
    videoTrack.captureController = screenCaptureController;
    [screenCaptureController startCapture];

    return videoTrack;
}

RCT_EXPORT_METHOD(getDisplayMedia : (RCTPromiseResolveBlock)resolve rejecter : (RCTPromiseRejectBlock)reject) {
#if TARGET_OS_TV
    reject(@"unsupported_platform", @"tvOS is not supported", nil);
    return;
#else

    LKRTCVideoTrack *videoTrack = [self createScreenCaptureVideoTrack];

    if (videoTrack == nil) {
        reject(@"DOMException", @"AbortError", nil);
        return;
    }

    NSString *mediaStreamId = [[NSUUID UUID] UUIDString];
    LKRTCMediaStream *mediaStream = [self.peerConnectionFactory mediaStreamWithStreamId:mediaStreamId];
    [mediaStream addVideoTrack:videoTrack];

    NSString *trackId = videoTrack.trackId;
    self.localTracks[trackId] = videoTrack;

    NSDictionary *trackInfo = @{
        @"enabled" : @(videoTrack.isEnabled),
        @"id" : videoTrack.trackId,
        @"kind" : videoTrack.kind,
        @"readyState" : @"live",
        @"remote" : @(NO)
    };

    self.localStreams[mediaStreamId] = mediaStream;
    resolve(@{@"streamId" : mediaStreamId, @"track" : trackInfo});
#endif
}

/**
 * Implements {@code getUserMedia}. Note that at this point constraints have
 * been normalized and permissions have been granted. The constraints only
 * contain keys for which permissions have already been granted, that is,
 * if audio permission was not granted, there will be no "audio" key in
 * the constraints dictionary.
 */
RCT_EXPORT_METHOD(getUserMedia
                  : (NSDictionary *)constraints successCallback
                  : (RCTResponseSenderBlock)successCallback errorCallback
                  : (RCTResponseSenderBlock)errorCallback) {
#if TARGET_OS_TV
    errorCallback(@[ @"PlatformNotSupported", @"getUserMedia is not supported on tvOS." ]);
    return;
#else
    LKRTCAudioTrack *audioTrack = nil;
    LKRTCVideoTrack *videoTrack = nil;

    if (constraints[@"audio"]) {
        audioTrack = [self createAudioTrack:constraints];
    }
    if (constraints[@"video"]) {
        videoTrack = [self createVideoTrack:constraints];
    }

    if (audioTrack == nil && videoTrack == nil) {
        // Fail with DOMException with name AbortError as per:
        // https://www.w3.org/TR/mediacapture-streams/#dom-mediadevices-getusermedia
        errorCallback(@[ @"DOMException", @"AbortError" ]);
        return;
    }

    NSString *mediaStreamId = [[NSUUID UUID] UUIDString];
    LKRTCMediaStream *mediaStream = [self.peerConnectionFactory mediaStreamWithStreamId:mediaStreamId];
    NSMutableArray *tracks = [NSMutableArray array];
    NSMutableArray *tmp = [NSMutableArray array];
    if (audioTrack)
        [tmp addObject:audioTrack];
    if (videoTrack)
        [tmp addObject:videoTrack];

    for (LKRTCMediaStreamTrack *track in tmp) {
        if ([track.kind isEqualToString:@"audio"]) {
            [mediaStream addAudioTrack:(LKRTCAudioTrack *)track];
        } else if ([track.kind isEqualToString:@"video"]) {
            [mediaStream addVideoTrack:(LKRTCVideoTrack *)track];
        }

        NSString *trackId = track.trackId;

        self.localTracks[trackId] = track;

        NSDictionary *settings = @{};
        if ([track.kind isEqualToString:@"video"]) {
            LKRTCVideoTrack *videoTrack = (LKRTCVideoTrack *)track;
            VideoCaptureController *vcc = (VideoCaptureController *)videoTrack.captureController;
            AVCaptureDeviceFormat *format = vcc.selectedFormat;
            CMVideoDimensions dimensions = CMVideoFormatDescriptionGetDimensions(format.formatDescription);
            settings = @{@"height" : @(dimensions.height), @"width" : @(dimensions.width), @"frameRate" : @(30)};
        }

        [tracks addObject:@{
            @"enabled" : @(track.isEnabled),
            @"id" : trackId,
            @"kind" : track.kind,
            @"readyState" : @"live",
            @"remote" : @(NO),
            @"settings" : settings
        }];
    }

    self.localStreams[mediaStreamId] = mediaStream;
    successCallback(@[ mediaStreamId, tracks ]);
#endif
}

#pragma mark - Other stream related APIs

RCT_EXPORT_METHOD(enumerateDevices : (RCTResponseSenderBlock)callback) {
#if TARGET_OS_TV
    callback(@[]);
#else
    NSMutableArray *devices = [NSMutableArray array];
    AVCaptureDeviceDiscoverySession *videoevicesSession =
        [AVCaptureDeviceDiscoverySession discoverySessionWithDeviceTypes:@[ AVCaptureDeviceTypeBuiltInWideAngleCamera, AVCaptureDeviceTypeBuiltInUltraWideCamera, AVCaptureDeviceTypeBuiltInTelephotoCamera, AVCaptureDeviceTypeBuiltInDualCamera, AVCaptureDeviceTypeBuiltInDualWideCamera, AVCaptureDeviceTypeBuiltInTripleCamera]
                                                               mediaType:AVMediaTypeVideo
                                                                position:AVCaptureDevicePositionUnspecified];
    for (AVCaptureDevice *device in videoevicesSession.devices) {
        NSString *position = @"unknown";
        if (device.position == AVCaptureDevicePositionBack) {
            position = @"environment";
        } else if (device.position == AVCaptureDevicePositionFront) {
            position = @"front";
        }
        NSString *label = @"Unknown video device";
        if (device.localizedName != nil) {
            label = device.localizedName;
        }
        [devices addObject:@{
            @"facing" : position,
            @"deviceId" : device.uniqueID,
            @"groupId" : @"",
            @"label" : label,
            @"kind" : @"videoinput",
        }];
    }
    AVCaptureDeviceDiscoverySession *audioDevicesSession =
        [AVCaptureDeviceDiscoverySession discoverySessionWithDeviceTypes:@[ AVCaptureDeviceTypeBuiltInMicrophone ]
                                                               mediaType:AVMediaTypeAudio
                                                                position:AVCaptureDevicePositionUnspecified];
    for (AVCaptureDevice *device in audioDevicesSession.devices) {
        NSString *label = @"Unknown audio device";
        if (device.localizedName != nil) {
            label = device.localizedName;
        }
        [devices addObject:@{
            @"deviceId" : device.uniqueID,
            @"groupId" : @"",
            @"label" : label,
            @"kind" : @"audioinput",
        }];
    }
    callback(@[ devices ]);
#endif
}

RCT_EXPORT_METHOD(mediaStreamCreate : (nonnull NSString *)streamID) {
    LKRTCMediaStream *mediaStream = [self.peerConnectionFactory mediaStreamWithStreamId:streamID];
    self.localStreams[streamID] = mediaStream;
}

RCT_EXPORT_METHOD(mediaStreamAddTrack
                  : (nonnull NSString *)streamID
                  : (nonnull NSNumber *)pcId
                  : (nonnull NSString *)trackID) {
    LKRTCMediaStream *mediaStream = self.localStreams[streamID];
    if (mediaStream == nil) {
        return;
    }

    LKRTCMediaStreamTrack *track = [self trackForId:trackID pcId:pcId];
    if (track == nil) {
        return;
    }

    if ([track.kind isEqualToString:@"audio"]) {
        [mediaStream addAudioTrack:(LKRTCAudioTrack *)track];
    } else if ([track.kind isEqualToString:@"video"]) {
        [mediaStream addVideoTrack:(LKRTCVideoTrack *)track];
    }
}

RCT_EXPORT_METHOD(mediaStreamRemoveTrack
                  : (nonnull NSString *)streamID
                  : (nonnull NSNumber *)pcId
                  : (nonnull NSString *)trackID) {
    LKRTCMediaStream *mediaStream = self.localStreams[streamID];
    if (mediaStream == nil) {
        return;
    }

    LKRTCMediaStreamTrack *track = [self trackForId:trackID pcId:pcId];
    if (track == nil) {
        return;
    }

    if ([track.kind isEqualToString:@"audio"]) {
        [mediaStream removeAudioTrack:(LKRTCAudioTrack *)track];
    } else if ([track.kind isEqualToString:@"video"]) {
        [mediaStream removeVideoTrack:(LKRTCVideoTrack *)track];
    }
}

RCT_EXPORT_METHOD(mediaStreamRelease : (nonnull NSString *)streamID) {
    LKRTCMediaStream *stream = self.localStreams[streamID];
    if (stream) {
        [self.localStreams removeObjectForKey:streamID];
    }
}

RCT_EXPORT_METHOD(mediaStreamTrackRelease : (nonnull NSString *)trackID) {
#if TARGET_OS_TV
    return;
#else

    LKRTCMediaStreamTrack *track = self.localTracks[trackID];
    if (track) {
        track.isEnabled = NO;
        [track.captureController stopCapture];
        [self.localTracks removeObjectForKey:trackID];
    }
#endif
}

RCT_EXPORT_METHOD(mediaStreamTrackSetEnabled : (nonnull NSNumber *)pcId : (nonnull NSString *)trackID : (BOOL)enabled) {
    LKRTCMediaStreamTrack *track = [self trackForId:trackID pcId:pcId];
    if (track == nil) {
        return;
    }

    track.isEnabled = enabled;
#if !TARGET_OS_TV
    if (track.captureController) {  // It could be a remote track!
        if (enabled) {
            [track.captureController startCapture];
        } else {
            [track.captureController stopCapture];
        }
    }
#endif
}

RCT_EXPORT_METHOD(mediaStreamTrackSwitchCamera : (nonnull NSString *)trackID) {
#if TARGET_OS_TV
    return;
#else
    LKRTCMediaStreamTrack *track = self.localTracks[trackID];
    if (track) {
        LKRTCVideoTrack *videoTrack = (LKRTCVideoTrack *)track;
        [(VideoCaptureController *)videoTrack.captureController switchCamera];
    }
#endif
}

RCT_EXPORT_METHOD(mediaStreamTrackSetVolume : (nonnull NSNumber *)pcId : (nonnull NSString *)trackID : (double)volume) {
    LKRTCMediaStreamTrack *track = [self trackForId:trackID pcId:pcId];
    if (track && [track.kind isEqualToString:@"audio"]) {
        LKRTCAudioTrack *audioTrack = (LKRTCAudioTrack *)track;
        audioTrack.source.volume = volume;
    }
}

#pragma mark - Helpers

- (LKRTCMediaStreamTrack *)trackForId:(nonnull NSString *)trackId pcId:(nonnull NSNumber *)pcId {
    if ([pcId isEqualToNumber:[NSNumber numberWithInt:-1]]) {
        return self.localTracks[trackId];
    }

    LKRTCPeerConnection *peerConnection = self.peerConnections[pcId];
    if (peerConnection == nil) {
        return nil;
    }

    return peerConnection.remoteTracks[trackId];
}

@end
