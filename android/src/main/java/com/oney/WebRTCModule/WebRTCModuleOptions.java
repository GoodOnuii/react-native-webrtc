package com.oney.WebRTCModule;

import livekit.org.webrtc.Loggable;
import livekit.org.webrtc.Logging;
import livekit.org.webrtc.VideoDecoderFactory;
import livekit.org.webrtc.VideoEncoderFactory;
import livekit.org.webrtc.audio.AudioDeviceModule;

public class WebRTCModuleOptions {
    private static WebRTCModuleOptions instance;

    public VideoEncoderFactory videoEncoderFactory;
    public VideoDecoderFactory videoDecoderFactory;
    public AudioDeviceModule audioDeviceModule;
    public Loggable injectableLogger;
    public Logging.Severity loggingSeverity;
    public String fieldTrials;
    public boolean enableMediaProjectionService;

    public static WebRTCModuleOptions getInstance() {
        if (instance == null) {
            instance = new WebRTCModuleOptions();
        }

        return instance;
    }
}
