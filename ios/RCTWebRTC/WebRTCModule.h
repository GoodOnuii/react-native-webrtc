#import <AVFoundation/AVFoundation.h>
#import <Foundation/Foundation.h>

#import <React/RCTBridgeModule.h>
#import <React/RCTConvert.h>
#import <React/RCTEventEmitter.h>

#import <LiveKitWebRTC/LiveKitWebRTC.h>

static NSString *const kEventPeerConnectionSignalingStateChanged = @"peerConnectionSignalingStateChanged";
static NSString *const kEventPeerConnectionStateChanged = @"peerConnectionStateChanged";
static NSString *const kEventPeerConnectionOnRenegotiationNeeded = @"peerConnectionOnRenegotiationNeeded";
static NSString *const kEventPeerConnectionIceConnectionChanged = @"peerConnectionIceConnectionChanged";
static NSString *const kEventPeerConnectionIceGatheringChanged = @"peerConnectionIceGatheringChanged";
static NSString *const kEventPeerConnectionGotICECandidate = @"peerConnectionGotICECandidate";
static NSString *const kEventPeerConnectionDidOpenDataChannel = @"peerConnectionDidOpenDataChannel";
static NSString *const kEventDataChannelDidChangeBufferedAmount = @"dataChannelDidChangeBufferedAmount";
static NSString *const kEventDataChannelStateChanged = @"dataChannelStateChanged";
static NSString *const kEventDataChannelReceiveMessage = @"dataChannelReceiveMessage";
static NSString *const kEventMediaStreamTrackMuteChanged = @"mediaStreamTrackMuteChanged";
static NSString *const kEventMediaStreamTrackEnded = @"mediaStreamTrackEnded";
static NSString *const kEventPeerConnectionOnRemoveTrack = @"peerConnectionOnRemoveTrack";
static NSString *const kEventPeerConnectionOnTrack = @"peerConnectionOnTrack";

@interface WebRTCModule : RCTEventEmitter<RCTBridgeModule>

@property(nonatomic, strong) dispatch_queue_t workerQueue;

@property(nonatomic, strong) LKRTCPeerConnectionFactory *peerConnectionFactory;
@property(nonatomic, strong) id<LKRTCVideoDecoderFactory> decoderFactory;
@property(nonatomic, strong) id<LKRTCVideoEncoderFactory> encoderFactory;

@property(nonatomic, strong) NSMutableDictionary<NSNumber *, LKRTCPeerConnection *> *peerConnections;
@property(nonatomic, strong) NSMutableDictionary<NSString *, LKRTCMediaStream *> *localStreams;
@property(nonatomic, strong) NSMutableDictionary<NSString *, LKRTCMediaStreamTrack *> *localTracks;

- (LKRTCMediaStream *)streamForReactTag:(NSString *)reactTag;

@end
