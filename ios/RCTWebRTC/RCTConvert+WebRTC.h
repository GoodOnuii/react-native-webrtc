#import <React/RCTConvert.h>
#import <LiveKitWebRTC/RTCConfiguration.h>
#import <LiveKitWebRTC/RTCDataChannelConfiguration.h>
#import <LiveKitWebRTC/RTCIceCandidate.h>
#import <LiveKitWebRTC/RTCIceServer.h>
#import <LiveKitWebRTC/RTCSessionDescription.h>

@interface RCTConvert (WebRTC)

+ (RTCIceCandidate *)RTCIceCandidate:(id)json;
+ (RTCSessionDescription *)RTCSessionDescription:(id)json;
+ (RTCIceServer *)RTCIceServer:(id)json;
+ (RTCDataChannelConfiguration *)RTCDataChannelConfiguration:(id)json;
+ (RTCConfiguration *)RTCConfiguration:(id)json;

@end
