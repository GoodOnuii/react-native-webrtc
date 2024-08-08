#import <LiveKitWebRTC/RTCPeerConnection.h>
#import "DataChannelWrapper.h"
#import "WebRTCModule.h"

@interface LKRTCPeerConnection (React)

@property(nonatomic, strong) NSNumber *reactTag;
@property(nonatomic, strong) NSMutableDictionary<NSString *, DataChannelWrapper *> *dataChannels;
@property(nonatomic, strong) NSMutableDictionary<NSString *, LKRTCMediaStream *> *remoteStreams;
@property(nonatomic, strong) NSMutableDictionary<NSString *, LKRTCMediaStreamTrack *> *remoteTracks;
@property(nonatomic, weak) id webRTCModule;

@end

@interface WebRTCModule (LKRTCPeerConnection)<LKRTCPeerConnectionDelegate>

@end
