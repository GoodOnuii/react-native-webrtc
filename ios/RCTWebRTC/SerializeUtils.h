#import <LiveKitWebRTC/RTCMediaStreamTrack.h>
#import <LiveKitWebRTC/RTCPeerConnectionFactory.h>
#import <LiveKitWebRTC/RTCRtpReceiver.h>
#import <LiveKitWebRTC/RTCRtpTransceiver.h>
#import <LiveKitWebRTC/RTCVideoCodecInfo.h>
#import "WebRTCModule+RTCPeerConnection.h"

@interface SerializeUtils : NSObject

+ (NSString *_Nonnull)transceiverToJSONWithPeerConnectionId:(nonnull NSNumber *)id
                                                transceiver:(RTCRtpTransceiver *_Nonnull)transceiver;
+ (NSDictionary *_Nonnull)senderToJSONWithPeerConnectionId:(nonnull NSNumber *)id sender:(RTCRtpSender *_Nonnull)sender;
+ (NSDictionary *_Nonnull)receiverToJSONWithPeerConnectionId:(nonnull NSNumber *)id
                                                    receiver:(RTCRtpReceiver *_Nonnull)receiver;
+ (NSDictionary *_Nonnull)trackToJSONWithPeerConnectionId:(nonnull NSNumber *)id
                                                    track:(RTCMediaStreamTrack *_Nonnull)track;
+ (NSDictionary *_Nonnull)capabilitiesToJSON:(RTCRtpCapabilities *_Nonnull)capabilities;
+ (NSDictionary *_Nonnull)codecCapabilityToJSON:(RTCRtpCodecCapability *_Nonnull)codec;
+ (NSString *_Nonnull)serializeDirection:(RTCRtpTransceiverDirection)direction;
+ (RTCRtpTransceiverDirection)parseDirection:(NSString *_Nonnull)direction;
+ (RTCRtpTransceiverInit *_Nonnull)parseTransceiverOptions:(NSDictionary *_Nonnull)parameters;
+ (NSDictionary *_Nonnull)parametersToJSON:(RTCRtpParameters *_Nonnull)parameters;
+ (NSMutableArray *_Nonnull)constructTransceiversInfoArrayWithPeerConnection:
    (RTCPeerConnection *_Nonnull)peerConnection;
+ (NSDictionary *_Nonnull)streamToJSONWithPeerConnectionId:(NSNumber *_Nonnull)id
                                                    stream:(RTCMediaStream *_Nonnull)stream
                                            streamReactTag:(NSString *_Nonnull)streamReactTag;
@end
