#import <React/RCTConvert.h>
#import <LiveKitWebRTC/RTCConfiguration.h>
#import <LiveKitWebRTC/RTCDataChannelConfiguration.h>
#import <LiveKitWebRTC/RTCIceCandidate.h>
#import <LiveKitWebRTC/RTCIceServer.h>
#import <LiveKitWebRTC/RTCSessionDescription.h>

@interface RCTConvert (WebRTC)

+ (LKRTCIceCandidate *)RTCIceCandidate:(id)json;
+ (LKRTCSessionDescription *)RTCSessionDescription:(id)json;
+ (LKRTCIceServer *)RTCIceServer:(id)json;
+ (LKRTCDataChannelConfiguration *)RTCDataChannelConfiguration:(id)json;
+ (LKRTCConfiguration *)RTCConfiguration:(id)json;

@end
