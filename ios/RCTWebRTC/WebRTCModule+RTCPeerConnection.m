#import <objc/runtime.h>

#import <React/RCTBridge.h>
#import <React/RCTEventDispatcher.h>
#import <React/RCTLog.h>
#import <React/RCTUtils.h>

#import <LiveKitWebRTC/RTCConfiguration.h>
#import <LiveKitWebRTC/RTCIceCandidate.h>
#import <LiveKitWebRTC/RTCIceServer.h>
#import <LiveKitWebRTC/RTCMediaConstraints.h>
#import <LiveKitWebRTC/RTCMediaStreamTrack.h>
#import <LiveKitWebRTC/RTCRtpReceiver.h>
#import <LiveKitWebRTC/RTCRtpTransceiver.h>
#import <LiveKitWebRTC/RTCSessionDescription.h>
#import <LiveKitWebRTC/RTCStatisticsReport.h>

#import "SerializeUtils.h"
#import "WebRTCModule+RTCDataChannel.h"
#import "WebRTCModule+RTCPeerConnection.h"
#import "WebRTCModule+VideoTrackAdapter.h"
#import "WebRTCModule.h"

@implementation LKRTCPeerConnection (React)

- (NSMutableDictionary<NSString *, DataChannelWrapper *> *)dataChannels {
    return objc_getAssociatedObject(self, _cmd);
}

- (void)setDataChannels:(NSMutableDictionary<NSString *, DataChannelWrapper *> *)dataChannels {
    objc_setAssociatedObject(self, @selector(dataChannels), dataChannels, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

- (NSNumber *)reactTag {
    return objc_getAssociatedObject(self, _cmd);
}

- (void)setReactTag:(NSNumber *)reactTag {
    objc_setAssociatedObject(self, @selector(reactTag), reactTag, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

- (NSMutableDictionary<NSString *, LKRTCMediaStream *> *)remoteStreams {
    return objc_getAssociatedObject(self, _cmd);
}

- (void)setRemoteStreams:(NSMutableDictionary<NSString *, LKRTCMediaStream *> *)remoteStreams {
    objc_setAssociatedObject(self, @selector(remoteStreams), remoteStreams, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

- (NSMutableDictionary<NSString *, LKRTCMediaStreamTrack *> *)remoteTracks {
    return objc_getAssociatedObject(self, _cmd);
}

- (void)setRemoteTracks:(NSMutableDictionary<NSString *, LKRTCMediaStreamTrack *> *)remoteTracks {
    objc_setAssociatedObject(self, @selector(remoteTracks), remoteTracks, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

- (id)webRTCModule {
    return objc_getAssociatedObject(self, _cmd);
}

- (void)setWebRTCModule:(id)webRTCModule {
    objc_setAssociatedObject(self, @selector(webRTCModule), webRTCModule, OBJC_ASSOCIATION_ASSIGN);
}

@end

@implementation WebRTCModule (LKRTCPeerConnection)

int _transceiverNextId = 0;

/*
 * This method is synchronous and blocking. This is done so we can implement createDataChannel
 * in the same way (synchronous) since the peer connection needs to exist before.
 */
RCT_EXPORT_BLOCKING_SYNCHRONOUS_METHOD(peerConnectionInit
                                       : (LKRTCConfiguration *)configuration objectID
                                       : (nonnull NSNumber *)objectID) {
    __block BOOL ret = YES;

    dispatch_sync(self.workerQueue, ^{
        LKRTCMediaConstraints *constraints = [[LKRTCMediaConstraints alloc] initWithMandatoryConstraints:nil
                                                                                 optionalConstraints:nil];
        LKRTCPeerConnection *peerConnection = [self.peerConnectionFactory peerConnectionWithConfiguration:configuration
                                                                                            constraints:constraints
                                                                                               delegate:self];
        if (peerConnection == nil) {
            ret = NO;
            return;
        }

        peerConnection.dataChannels = [NSMutableDictionary new];
        peerConnection.reactTag = objectID;
        peerConnection.remoteStreams = [NSMutableDictionary new];
        peerConnection.remoteTracks = [NSMutableDictionary new];
        peerConnection.videoTrackAdapters = [NSMutableDictionary new];
        peerConnection.webRTCModule = self;

        self.peerConnections[objectID] = peerConnection;
    });

    return @(ret);
}

RCT_EXPORT_METHOD(peerConnectionSetConfiguration
                  : (LKRTCConfiguration *)configuration objectID
                  : (nonnull NSNumber *)objectID) {
    LKRTCPeerConnection *peerConnection = self.peerConnections[objectID];
    if (!peerConnection) {
        return;
    }
    [peerConnection setConfiguration:configuration];
}

RCT_EXPORT_METHOD(peerConnectionCreateOffer
                  : (nonnull NSNumber *)objectID options
                  : (NSDictionary *)options resolver
                  : (RCTPromiseResolveBlock)resolve rejecter
                  : (RCTPromiseRejectBlock)reject) {
    LKRTCPeerConnection *peerConnection = self.peerConnections[objectID];
    if (!peerConnection) {
        reject(@"E_INVALID", @"PeerConnection not found", nil);
        return;
    }

    LKRTCMediaConstraints *constraints = [[LKRTCMediaConstraints alloc] initWithMandatoryConstraints:options
                                                                             optionalConstraints:nil];

    NSMutableArray *receiversIds = [NSMutableArray new];
    for (LKRTCRtpTransceiver *transceiver in peerConnection.transceivers) {
        [receiversIds addObject:transceiver.receiver.receiverId];
    }

    RTCCreateSessionDescriptionCompletionHandler handler = ^(LKRTCSessionDescription *desc, NSError *error) {
        dispatch_async(self.workerQueue, ^{
            if (error) {
                reject(@"E_OPERATION_ERROR", error.localizedDescription, nil);
            } else {
                NSMutableArray *newTransceivers = [NSMutableArray new];
                for (LKRTCRtpTransceiver *transceiver in peerConnection.transceivers) {
                    if (![receiversIds containsObject:transceiver.receiver.receiverId]) {
                        NSMutableDictionary *newTransceiver = [NSMutableDictionary new];
                        newTransceiver[@"transceiverOrder"] = [NSNumber numberWithInt:_transceiverNextId++];
                        newTransceiver[@"transceiver"] =
                            [SerializeUtils transceiverToJSONWithPeerConnectionId:objectID transceiver:transceiver];
                        [newTransceivers addObject:newTransceiver];
                    }
                }
                id data = @{
                    @"sdpInfo" : @{@"type" : [LKRTCSessionDescription stringForType:desc.type], @"sdp" : desc.sdp},
                    @"transceiversInfo" :
                        [SerializeUtils constructTransceiversInfoArrayWithPeerConnection:peerConnection],
                    @"newTransceivers" : newTransceivers
                };
                resolve(data);
            }
        });
    };

    [peerConnection offerForConstraints:constraints completionHandler:handler];
}

RCT_EXPORT_METHOD(peerConnectionCreateAnswer
                  : (nonnull NSNumber *)objectID options
                  : (NSDictionary *)options resolver
                  : (RCTPromiseResolveBlock)resolve rejecter
                  : (RCTPromiseRejectBlock)reject) {
    LKRTCPeerConnection *peerConnection = self.peerConnections[objectID];
    if (!peerConnection) {
        reject(@"E_INVALID", @"PeerConnection not found", nil);
        return;
    }

    LKRTCMediaConstraints *constraints = [[LKRTCMediaConstraints alloc] initWithMandatoryConstraints:options
                                                                             optionalConstraints:nil];

    RTCCreateSessionDescriptionCompletionHandler handler = ^(LKRTCSessionDescription *desc, NSError *error) {
        dispatch_async(self.workerQueue, ^{
            if (error) {
                reject(@"E_OPERATION_ERROR", error.localizedDescription, nil);
            } else {
                id data = @{
                    @"sdpInfo" : @{@"type" : [LKRTCSessionDescription stringForType:desc.type], @"sdp" : desc.sdp},
                    @"transceiversInfo" :
                        [SerializeUtils constructTransceiversInfoArrayWithPeerConnection:peerConnection]
                };
                resolve(data);
            }
        });
    };

    [peerConnection answerForConstraints:constraints completionHandler:handler];
}

RCT_EXPORT_METHOD(peerConnectionSetLocalDescription
                  : (nonnull NSNumber *)objectID desc
                  : (LKRTCSessionDescription *)desc resolver
                  : (RCTPromiseResolveBlock)resolve rejecter
                  : (RCTPromiseRejectBlock)reject) {
    LKRTCPeerConnection *peerConnection = self.peerConnections[objectID];
    if (!peerConnection) {
        reject(@"E_INVALID", @"PeerConnection not found", nil);
        return;
    }

    RTCSetSessionDescriptionCompletionHandler handler = ^(NSError *error) {
        dispatch_async(self.workerQueue, ^{
            if (error) {
                reject(@"E_OPERATION_ERROR", error.localizedDescription, nil);
            } else {
                NSMutableDictionary *sdpInfo = [NSMutableDictionary new];
                LKRTCSessionDescription *localDesc = peerConnection.localDescription;
                if (localDesc) {
                    sdpInfo[@"type"] = [LKRTCSessionDescription stringForType:localDesc.type];
                    sdpInfo[@"sdp"] = localDesc.sdp;
                }
                id data = @{
                    @"sdpInfo" : sdpInfo,
                    @"transceiversInfo" :
                        [SerializeUtils constructTransceiversInfoArrayWithPeerConnection:peerConnection]
                };
                resolve(data);
            }
        });
    };

    if (desc == nil) {
        [peerConnection setLocalDescriptionWithCompletionHandler:handler];
    } else {
        [peerConnection setLocalDescription:desc completionHandler:handler];
    }
}

RCT_EXPORT_METHOD(peerConnectionSetRemoteDescription
                  : (nonnull NSNumber *)objectID desc
                  : (LKRTCSessionDescription *)desc resolver
                  : (RCTPromiseResolveBlock)resolve rejecter
                  : (RCTPromiseRejectBlock)reject) {
    LKRTCPeerConnection *peerConnection = self.peerConnections[objectID];
    if (!peerConnection) {
        reject(@"E_INVALID", @"PeerConnection not found", nil);
        return;
    }

    NSMutableArray *receiversIds = [NSMutableArray new];
    for (LKRTCRtpTransceiver *transceiver in peerConnection.transceivers) {
        [receiversIds addObject:transceiver.receiver.receiverId];
    }

    RTCSetSessionDescriptionCompletionHandler handler = ^(NSError *error) {
        dispatch_async(self.workerQueue, ^{
            if (error) {
                reject(@"E_OPERATION_ERROR", error.localizedDescription, nil);
            } else {
                NSMutableArray *newTransceivers = [NSMutableArray new];
                for (LKRTCRtpTransceiver *transceiver in peerConnection.transceivers) {
                    if (![receiversIds containsObject:transceiver.receiver.receiverId]) {
                        NSMutableDictionary *newTransceiver = [NSMutableDictionary new];
                        newTransceiver[@"transceiverOrder"] = [NSNumber numberWithInt:_transceiverNextId++];
                        newTransceiver[@"transceiver"] =
                            [SerializeUtils transceiverToJSONWithPeerConnectionId:objectID transceiver:transceiver];
                        [newTransceivers addObject:newTransceiver];
                    }
                }

                NSMutableDictionary *sdpInfo = [NSMutableDictionary new];
                LKRTCSessionDescription *remoteDesc = peerConnection.remoteDescription;
                if (remoteDesc) {
                    sdpInfo[@"type"] = [LKRTCSessionDescription stringForType:remoteDesc.type];
                    sdpInfo[@"sdp"] = remoteDesc.sdp;
                }
                id data = @{
                    @"sdpInfo" : sdpInfo,
                    @"transceiversInfo" :
                        [SerializeUtils constructTransceiversInfoArrayWithPeerConnection:peerConnection],
                    @"newTransceivers" : newTransceivers
                };
                resolve(data);
            }
        });
    };

    [peerConnection setRemoteDescription:desc completionHandler:handler];
}

RCT_EXPORT_METHOD(peerConnectionAddICECandidate
                  : (nonnull NSNumber *)objectID candidate
                  : (LKRTCIceCandidate *)candidate resolver
                  : (RCTPromiseResolveBlock)resolve rejecter
                  : (RCTPromiseRejectBlock)reject) {
    LKRTCPeerConnection *peerConnection = self.peerConnections[objectID];
    if (!peerConnection) {
        reject(@"E_INVALID", @"PeerConnection not found", nil);
        return;
    }

    id handler = ^(NSError *error) {
        dispatch_async(self.workerQueue, ^{
            if (error) {
                reject(@"E_OPERATION_ERROR", @"addIceCandidate failed", error);
            } else {
                LKRTCSessionDescription *remoteDesc = peerConnection.remoteDescription;
                id newSdp = @{@"type" : [LKRTCSessionDescription stringForType:remoteDesc.type], @"sdp" : remoteDesc.sdp};
                resolve(newSdp);
            }
        });
    };

    [peerConnection addIceCandidate:candidate completionHandler:handler];
}

RCT_EXPORT_METHOD(peerConnectionClose : (nonnull NSNumber *)objectID) {
    LKRTCPeerConnection *peerConnection = self.peerConnections[objectID];
    if (!peerConnection) {
        return;
    }

    [peerConnection close];
}

RCT_EXPORT_METHOD(peerConnectionDispose : (nonnull NSNumber *)objectID) {
    LKRTCPeerConnection *peerConnection = self.peerConnections[objectID];
    if (!peerConnection) {
        return;
    }

    // Remove video track adapters
    for (NSString *key in peerConnection.remoteTracks.allKeys) {
        LKRTCMediaStreamTrack *track = peerConnection.remoteTracks[key];
        if (track.kind == kRTCMediaStreamTrackKindVideo) {
            [peerConnection removeVideoTrackAdapter:(LKRTCVideoTrack *)track];
        }
    }

    // Clean up peerConnection's streams and tracks
    [peerConnection.remoteStreams removeAllObjects];
    [peerConnection.remoteTracks removeAllObjects];

    // Clean up peerConnection's dataChannels.
    NSMutableDictionary<NSString *, DataChannelWrapper *> *dataChannels = peerConnection.dataChannels;
    for (NSString *tag in dataChannels) {
        dataChannels[tag].delegate = nil;
        // There is no need to close the LKRTCDataChannel because it is owned by the
        // LKRTCPeerConnection and the latter will close the former.
    }
    [dataChannels removeAllObjects];

    [self.peerConnections removeObjectForKey:objectID];
}

RCT_EXPORT_METHOD(peerConnectionGetStats
                  : (nonnull NSNumber *)objectID resolver
                  : (RCTPromiseResolveBlock)resolve rejecter
                  : (RCTPromiseRejectBlock)reject) {
    LKRTCPeerConnection *peerConnection = self.peerConnections[objectID];
    if (!peerConnection) {
        RCTLogWarn(@"PeerConnection %@ not found in peerConnectionGetStats()", objectID);
        resolve(@"[]");
        return;
    }

    [peerConnection statisticsWithCompletionHandler:^(LKRTCStatisticsReport *report) {
        resolve([self statsToJSON:report]);
    }];
}

RCT_EXPORT_METHOD(receiverGetStats
                  : (nonnull NSNumber *)pcId receiverId
                  : (nonnull NSString *)receiverId resolver
                  : (RCTPromiseResolveBlock)resolve rejecter
                  : (RCTPromiseRejectBlock)reject) {
    LKRTCPeerConnection *peerConnection = self.peerConnections[pcId];
    if (!peerConnection) {
        RCTLogWarn(@"PeerConnection %@ not found in receiverGetStats()", pcId);
        resolve(@"[]");
        return;
    }

    LKRTCRtpReceiver *receiver;
    for (LKRTCRtpReceiver *findRecv in peerConnection.receivers) {
        if ([findRecv.receiverId isEqualToString:receiverId]) {
            receiver = findRecv;
            break;
        }
    }

    if (!receiver) {
        RCTLogWarn(@"RTCRtpReceiver %@ not found in receiverGetStats()", receiverId);
        resolve(@"[]");
        return;
    }

    [peerConnection statisticsForReceiver:receiver
                        completionHandler:^(LKRTCStatisticsReport *report) {
                            resolve([self statsToJSON:report]);
                        }];
}

RCT_EXPORT_METHOD(senderGetStats
                  : (nonnull NSNumber *)pcId senderId
                  : (nonnull NSString *)senderId resolver
                  : (RCTPromiseResolveBlock)resolve rejecter
                  : (RCTPromiseRejectBlock)reject) {
    LKRTCPeerConnection *peerConnection = self.peerConnections[pcId];
    if (!peerConnection) {
        RCTLogWarn(@"PeerConnection %@ not found in senderGetStats()", pcId);
        resolve(@"[]");
        return;
    }

    LKRTCRtpSender *sender;
    for (LKRTCRtpSender *findSend in peerConnection.senders) {
        if ([findSend.senderId isEqualToString:senderId]) {
            sender = findSend;
            break;
        }
    }

    if (!sender) {
        RCTLogWarn(@"RTCRtpSender %@ not found in senderGetStats()", senderId);
        resolve(@"[]");
        return;
    }

    [peerConnection statisticsForSender:sender
                      completionHandler:^(LKRTCStatisticsReport *report) {
                          resolve([self statsToJSON:report]);
                      }];
}

RCT_EXPORT_METHOD(peerConnectionRestartIce : (nonnull NSNumber *)objectID) {
    LKRTCPeerConnection *peerConnection = self.peerConnections[objectID];
    if (!peerConnection) {
        return;
    }

    [peerConnection restartIce];
}

RCT_EXPORT_BLOCKING_SYNCHRONOUS_METHOD(peerConnectionAddTrack
                                       : (nonnull NSNumber *)objectID trackId
                                       : (NSString *)trackId options
                                       : (NSDictionary *)options) {
    __block id params = nil;

    dispatch_sync(self.workerQueue, ^{
        LKRTCPeerConnection *peerConnection = self.peerConnections[objectID];
        if (!peerConnection) {
            RCTLogWarn(@"PeerConnection %@ not found in peerConnectionAddTrack()", objectID);
            return;
        }

        LKRTCMediaStreamTrack *track = self.localTracks[trackId];

        NSArray *streamIds = [options objectForKey:@"streamIds"];
        LKRTCRtpSender *sender = [peerConnection addTrack:track streamIds:streamIds];
        LKRTCRtpTransceiver *transceiver = nil;

        for (LKRTCRtpTransceiver *t in peerConnection.transceivers) {
            if ([t.sender.senderId isEqual:sender.senderId]) {
                transceiver = t;
                break;
            }
        }

        if (!transceiver) {
            RCTLogWarn(@"Transceiver not found in peerConnectionAddTrack()");
            return;
        }

        params = @{
            @"transceiverOrder" : [NSNumber numberWithInt:_transceiverNextId++],
            @"transceiver" : [SerializeUtils transceiverToJSONWithPeerConnectionId:objectID transceiver:transceiver],
            @"sender" : [SerializeUtils senderToJSONWithPeerConnectionId:objectID sender:sender]
        };
    });

    return params;
}

RCT_EXPORT_BLOCKING_SYNCHRONOUS_METHOD(peerConnectionAddTransceiver
                                       : (nonnull NSNumber *)objectID options
                                       : (NSDictionary *)options) {
    __block id params = nil;

    dispatch_sync(self.workerQueue, ^{
        LKRTCPeerConnection *peerConnection = self.peerConnections[objectID];
        if (!peerConnection) {
            RCTLogWarn(@"PeerConnection %@ not found in peerConnectionAddTransceiver()", objectID);
            return;
        }

        LKRTCRtpTransceiver *transceiver = nil;
        NSString *kind = [options objectForKey:@"type"];
        NSString *trackId = [options objectForKey:@"trackId"];
        RTCRtpMediaType type = RTCRtpMediaTypeUnsupported;

        if (kind) {
            if ([kind isEqual:@"audio"]) {
                type = RTCRtpMediaTypeAudio;
            } else if ([kind isEqual:@"video"]) {
                type = RTCRtpMediaTypeVideo;
            }

            NSDictionary *initOptions = [options objectForKey:@"init"];
            LKRTCRtpTransceiverInit *transceiverInit = [SerializeUtils parseTransceiverOptions:initOptions];

            transceiver = [peerConnection addTransceiverOfType:type init:transceiverInit];
        } else if (trackId) {
            LKRTCMediaStreamTrack *track = self.localTracks[trackId];

            if (!track) {
                track = peerConnection.remoteTracks[trackId];
            }

            NSDictionary *initOptions = [options objectForKey:@"init"];
            LKRTCRtpTransceiverInit *transceiverInit = [SerializeUtils parseTransceiverOptions:initOptions];

            transceiver = [peerConnection addTransceiverWithTrack:track init:transceiverInit];
        } else {
            RCTLogWarn(@"peerConnectionAddTransceiver() no type nor trackId provided in options");
            return;
        }

        if (transceiver == nil) {
            RCTLogWarn(@"peerConnectionAddTransceiver() Error adding transceiver");
            return;
        }

        params = @{
            @"transceiverOrder" : [NSNumber numberWithInt:_transceiverNextId++],
            @"transceiver" : [SerializeUtils transceiverToJSONWithPeerConnectionId:objectID transceiver:transceiver]
        };
    });

    return params;
}

RCT_EXPORT_BLOCKING_SYNCHRONOUS_METHOD(peerConnectionRemoveTrack
                                       : (nonnull NSNumber *)objectID senderId
                                       : (nonnull NSString *)senderId) {
    __block BOOL ret = NO;

    dispatch_sync(self.workerQueue, ^{
        LKRTCPeerConnection *peerConnection = self.peerConnections[objectID];
        if (!peerConnection) {
            RCTLogWarn(@"PeerConnection %@ not found in peerConnectionRemoveTrack()", objectID);
            return;
        }

        LKRTCRtpSender *sender = nil;

        for (LKRTCRtpSender *s in peerConnection.senders) {
            if ([s.senderId isEqual:senderId]) {
                sender = s;
                break;
            }
        }

        if (!sender) {
            RCTLogWarn(@"Sender not found in peerConnectionRemoveTrack()");
            return;
        }

        ret = [peerConnection removeTrack:sender];
    });

    return @(ret);
}

// TODO: move these below to some SerializeUtils file

/**
 * Constructs a JSON <tt>NSString</tt> representation of a specific
 * <tt>RTCStatisticsReport</tt>s.
 * <p>
 *
 * @param <tt>RTCStatisticsReport</tt>s
 * @return an <tt>NSString</tt> which represents the specified <tt>report</tt> in
 * JSON format
 */
- (NSString *)statsToJSON:(LKRTCStatisticsReport *)report {
    /*
    The initial capacity matters, of course, because it determines how many
    times the NSMutableString will have grow. But walking through the reports
    to compute an initial capacity which exactly matches the requirements of
    the reports is too much work without real-world bang here. An improvement
    should be caching the required capacity from the previous invocation of the
    method and using it as the initial capacity in the next invocation.
    As I didn't want to go even through that,choosing just about any initial
    capacity is OK because NSMutableCopy doesn't have too bad a strategy of growing.
    */
    NSMutableString *s = [NSMutableString stringWithCapacity:16 * 1024];

    [s appendString:@"["];
    BOOL firstReport = YES;
    for (NSString *key in report.statistics.allKeys) {
        if (firstReport) {
            firstReport = NO;
        } else {
            [s appendString:@","];
        }

        [s appendString:@"[\""];
        [s appendString:key];
        [s appendString:@"\",{"];

        LKRTCStatistics *statistics = report.statistics[key];
        [s appendString:@"\"timestamp\":"];
        [s appendFormat:@"%f", statistics.timestamp_us / 1000.0];
        [s appendString:@",\"type\":\""];
        [s appendString:statistics.type];
        [s appendString:@"\",\"id\":\""];
        [s appendString:statistics.id];
        [s appendString:@"\""];

        for (id key in statistics.values) {
            [s appendString:@","];
            [s appendString:@"\""];
            [s appendString:key];
            [s appendString:@"\":"];
            NSObject *statisticsValue = [statistics.values objectForKey:key];
            [self appendValue:statisticsValue toString:s];
        }

        [s appendString:@"}]"];
    }

    [s appendString:@"]"];

    return s;
}

- (void)appendValue:(NSObject *)statisticsValue toString:(NSMutableString *)s {
    if ([statisticsValue isKindOfClass:[NSArray class]]) {
        [s appendString:@"["];
        BOOL firstValue = YES;
        for (NSObject *element in (NSArray *)statisticsValue) {
            if (firstValue) {
                firstValue = NO;
            } else {
                [s appendString:@","];
            }

            [s appendString:@"\""];
            [s appendString:[NSString stringWithFormat:@"%@", element]];
            [s appendString:@"\""];
        }

        [s appendString:@"]"];
    } else if ([statisticsValue isKindOfClass:[NSDictionary class]]) {
        NSError *error;
        NSData *jsonData = [NSJSONSerialization dataWithJSONObject:statisticsValue options:0 error:&error];

        if (!jsonData) {
            [s appendString:@"\""];
            [s appendString:[NSString stringWithFormat:@"%@", statisticsValue]];
            [s appendString:@"\""];
        } else {
            NSString *jsonString = [[NSString alloc] initWithData:jsonData encoding:NSUTF8StringEncoding];
            [s appendString:jsonString];
        }
    } else if ([statisticsValue isKindOfClass:[NSNumber class]]) {
        [s appendString:[NSString stringWithFormat:@"%@", statisticsValue]];
    } else {
        [s appendString:@"\""];
        [s appendString:[NSString stringWithFormat:@"%@", statisticsValue]];
        [s appendString:@"\""];
    }
}

- (NSString *)stringForPeerConnectionState:(RTCPeerConnectionState)state {
    switch (state) {
        case RTCPeerConnectionStateNew:
            return @"new";
        case RTCPeerConnectionStateConnecting:
            return @"connecting";
        case RTCPeerConnectionStateConnected:
            return @"connected";
        case RTCPeerConnectionStateDisconnected:
            return @"disconnected";
        case RTCPeerConnectionStateFailed:
            return @"failed";
        case RTCPeerConnectionStateClosed:
            return @"closed";
    }
    return nil;
}

- (NSString *)stringForICEConnectionState:(RTCIceConnectionState)state {
    switch (state) {
        case RTCIceConnectionStateNew:
            return @"new";
        case RTCIceConnectionStateChecking:
            return @"checking";
        case RTCIceConnectionStateConnected:
            return @"connected";
        case RTCIceConnectionStateCompleted:
            return @"completed";
        case RTCIceConnectionStateFailed:
            return @"failed";
        case RTCIceConnectionStateDisconnected:
            return @"disconnected";
        case RTCIceConnectionStateClosed:
            return @"closed";
        case RTCIceConnectionStateCount:
            return @"count";
    }
    return nil;
}

- (NSString *)stringForICEGatheringState:(RTCIceGatheringState)state {
    switch (state) {
        case RTCIceGatheringStateNew:
            return @"new";
        case RTCIceGatheringStateGathering:
            return @"gathering";
        case RTCIceGatheringStateComplete:
            return @"complete";
    }
    return nil;
}

- (NSString *)stringForSignalingState:(RTCSignalingState)state {
    switch (state) {
        case RTCSignalingStateStable:
            return @"stable";
        case RTCSignalingStateHaveLocalOffer:
            return @"have-local-offer";
        case RTCSignalingStateHaveLocalPrAnswer:
            return @"have-local-pranswer";
        case RTCSignalingStateHaveRemoteOffer:
            return @"have-remote-offer";
        case RTCSignalingStateHaveRemotePrAnswer:
            return @"have-remote-pranswer";
        case RTCSignalingStateClosed:
            return @"closed";
    }
    return nil;
}

#pragma mark - LKRTCPeerConnectionDelegate methods

- (void)peerConnection:(LKRTCPeerConnection *)peerConnection didChangeSignalingState:(RTCSignalingState)newState {
    dispatch_async(self.workerQueue, ^{
        [self sendEventWithName:kEventPeerConnectionSignalingStateChanged
                           body:@{
                               @"pcId" : peerConnection.reactTag,
                               @"signalingState" : [self stringForSignalingState:newState]
                           }];
    });
}

- (void)peerConnectionShouldNegotiate:(LKRTCPeerConnection *)peerConnection {
    dispatch_async(self.workerQueue, ^{
        [self sendEventWithName:kEventPeerConnectionOnRenegotiationNeeded body:@{@"pcId" : peerConnection.reactTag}];
    });
}

- (void)peerConnection:(LKRTCPeerConnection *)peerConnection didChangeConnectionState:(RTCPeerConnectionState)newState {
    dispatch_async(self.workerQueue, ^{
        [self sendEventWithName:kEventPeerConnectionStateChanged
                           body:@{
                               @"pcId" : peerConnection.reactTag,
                               @"connectionState" : [self stringForPeerConnectionState:newState]
                           }];
    });
}

- (void)peerConnection:(LKRTCPeerConnection *)peerConnection didChangeIceConnectionState:(RTCIceConnectionState)newState {
    dispatch_async(self.workerQueue, ^{
        [self sendEventWithName:kEventPeerConnectionIceConnectionChanged
                           body:@{
                               @"pcId" : peerConnection.reactTag,
                               @"iceConnectionState" : [self stringForICEConnectionState:newState]
                           }];
    });
}

- (void)peerConnection:(LKRTCPeerConnection *)peerConnection didChangeIceGatheringState:(RTCIceGatheringState)newState {
    dispatch_async(self.workerQueue, ^{
        id newSdp = @{};
        if (newState == RTCIceGatheringStateComplete) {
            // Can happen when doing a rollback.
            if (peerConnection.localDescription) {
                newSdp = @{
                    @"type" : [LKRTCSessionDescription stringForType:peerConnection.localDescription.type],
                    @"sdp" : peerConnection.localDescription.sdp
                };
            }
        }

        [self sendEventWithName:kEventPeerConnectionIceGatheringChanged
                           body:@{
                               @"pcId" : peerConnection.reactTag,
                               @"iceGatheringState" : [self stringForICEGatheringState:newState],
                               @"sdp" : newSdp
                           }];
    });
}

- (void)peerConnection:(LKRTCPeerConnection *)peerConnection didGenerateIceCandidate:(LKRTCIceCandidate *)candidate {
    dispatch_async(self.workerQueue, ^{
        id newSdp = @{};
        // Can happen when doing a rollback.
        if (peerConnection.localDescription) {
            newSdp = @{
                @"type" : [LKRTCSessionDescription stringForType:peerConnection.localDescription.type],
                @"sdp" : peerConnection.localDescription.sdp
            };
        }

        [self sendEventWithName:kEventPeerConnectionGotICECandidate
                           body:@{
                               @"pcId" : peerConnection.reactTag,
                               @"candidate" : @{
                                   @"candidate" : candidate.sdp,
                                   @"sdpMLineIndex" : @(candidate.sdpMLineIndex),
                                   @"sdpMid" : candidate.sdpMid
                               },
                               @"sdp" : newSdp
                           }];
    });
}

- (void)peerConnection:(LKRTCPeerConnection *)peerConnection didOpenDataChannel:(LKRTCDataChannel *)dataChannel {
    dispatch_async(self.workerQueue, ^{
        NSString *reactTag = [[NSUUID UUID] UUIDString];
        DataChannelWrapper *dcw = [[DataChannelWrapper alloc] initWithChannel:dataChannel reactTag:reactTag];
        dcw.pcId = peerConnection.reactTag;
        peerConnection.dataChannels[reactTag] = dcw;
        dcw.delegate = self;

        NSDictionary *dataChannelInfo = @{
            @"peerConnectionId" : peerConnection.reactTag,
            @"reactTag" : reactTag,
            @"label" : dataChannel.label,
            @"id" : @(dataChannel.channelId),
            @"ordered" : @(dataChannel.isOrdered),
            @"maxPacketLifeTime" : @(dataChannel.maxPacketLifeTime),
            @"maxRetransmits" : @(dataChannel.maxRetransmits),
            @"protocol" : dataChannel.protocol,
            @"negotiated" : @(dataChannel.isNegotiated),
            @"readyState" : [self stringForDataChannelState:dataChannel.readyState]
        };
        NSDictionary *body = @{@"pcId" : peerConnection.reactTag, @"dataChannel" : dataChannelInfo};

        [self sendEventWithName:kEventPeerConnectionDidOpenDataChannel body:body];
    });
}

- (void)peerConnection:(RTC_OBJC_TYPE(RTCPeerConnection) *)peerConnection
        didAddReceiver:(RTC_OBJC_TYPE(RTCRtpReceiver) *)rtpReceiver
               streams:(NSArray<RTC_OBJC_TYPE(RTCMediaStream) *> *)mediaStreams {
    dispatch_async(self.workerQueue, ^{
        LKRTCRtpTransceiver *transceiver = nil;
        for (LKRTCRtpTransceiver *t in peerConnection.transceivers) {
            if ([rtpReceiver.receiverId isEqual:t.receiver.receiverId]) {
                transceiver = t;
                break;
            }
        }

        if (!transceiver) {
            RCTLogWarn(@"Transceiver not found in didAddReceiver()");
            return;
        }

        LKRTCMediaStreamTrack *track = rtpReceiver.track;

        // We need to fire this event for an existing track sometimes, like
        // when the transceiver direction (on the sending side) switches from
        // sendrecv to recvonly and then back.
        BOOL existingTrack = peerConnection.remoteTracks[track.trackId] != nil;

        if (!existingTrack) {
            if (track.kind == kRTCMediaStreamTrackKindVideo) {
                LKRTCVideoTrack *videoTrack = (LKRTCVideoTrack *)track;
                [peerConnection addVideoTrackAdapter:videoTrack];
            }

            peerConnection.remoteTracks[track.trackId] = track;
        }

        NSMutableDictionary *params = [NSMutableDictionary new];
        NSMutableArray *streams = [NSMutableArray new];

        for (LKRTCMediaStream *stream in mediaStreams) {
            NSString *streamReactTag = nil;

            for (NSString *key in [peerConnection.remoteStreams allKeys]) {
                if ([[peerConnection.remoteStreams objectForKey:key].streamId isEqual:stream.streamId]) {
                    streamReactTag = key;
                    break;
                }
            }

            if (!streamReactTag) {
                streamReactTag = [[NSUUID UUID] UUIDString];
            }

            // Make sure the stored stream is updated in case we get a new reference.
            peerConnection.remoteStreams[streamReactTag] = stream;

            [streams addObject:[SerializeUtils streamToJSONWithPeerConnectionId:peerConnection.reactTag
                                                                         stream:stream
                                                                 streamReactTag:streamReactTag]];
        }

        params[@"streams"] = streams;
        params[@"receiver"] = [SerializeUtils receiverToJSONWithPeerConnectionId:peerConnection.reactTag
                                                                        receiver:rtpReceiver];
        params[@"transceiverOrder"] = [NSNumber numberWithInt:_transceiverNextId++];
        params[@"transceiver"] = [SerializeUtils transceiverToJSONWithPeerConnectionId:peerConnection.reactTag
                                                                           transceiver:transceiver];
        params[@"pcId"] = peerConnection.reactTag;

        [self sendEventWithName:kEventPeerConnectionOnTrack body:params];
    });
}

- (void)peerConnection:(RTC_OBJC_TYPE(RTCPeerConnection) *)peerConnection
     didRemoveReceiver:(RTC_OBJC_TYPE(RTCRtpReceiver) *)rtpReceiver {
    dispatch_async(self.workerQueue, ^{
        NSMutableDictionary *params = [NSMutableDictionary new];

        params[@"pcId"] = peerConnection.reactTag;
        params[@"receiverId"] = rtpReceiver.receiverId;

        [self sendEventWithName:kEventPeerConnectionOnRemoveTrack body:params];
    });
}

- (void)peerConnection:(nonnull LKRTCPeerConnection *)peerConnection
    didRemoveIceCandidates:(nonnull NSArray<LKRTCIceCandidate *> *)candidates {
    // Unimplemented, there is no matching web API.
}

- (void)peerConnection:(nonnull LKRTCPeerConnection *)peerConnection didAddStream:(nonnull LKRTCMediaStream *)stream {
    // Unused in Unified Plan.
}

- (void)peerConnection:(nonnull LKRTCPeerConnection *)peerConnection didRemoveStream:(nonnull LKRTCMediaStream *)stream {
    // Unused in Unified Plan.
}

@end
