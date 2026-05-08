//
//  AudioSessionManager.swift
//  AuraPlayer
//
//  Manages the AVAudioSession lifecycle: category, mode, sample rate,
//  route monitoring, and external DAC detection.
//

import Foundation
import AVFoundation
import Combine

// MARK: - Audio Route Info

/// Describes the currently active audio output route.
struct AudioRouteInfo: Equatable, Sendable {
    let portName: String
    let portType: AVAudioSession.Port
    let isExternalDAC: Bool
    let isHeadphones: Bool
    let isBluetooth: Bool
    let isBuiltInSpeaker: Bool
    let sampleRate: Double
    let outputChannels: Int
    
    /// Human-readable quality label for the route.
    var qualityLabel: String {
        if isExternalDAC {
            return "USB DAC · \(formattedSampleRate)"
        } else if isHeadphones {
            return "Headphones · \(formattedSampleRate)"
        } else if isBluetooth {
            return "Bluetooth · \(formattedSampleRate)"
        } else {
            return "Speaker · \(formattedSampleRate)"
        }
    }
    
    private var formattedSampleRate: String {
        let kHz = sampleRate / 1000.0
        if kHz.truncatingRemainder(dividingBy: 1) == 0 {
            return String(format: "%.0f kHz", kHz)
        }
        return String(format: "%.1f kHz", kHz)
    }
    
    static let builtInSpeaker = AudioRouteInfo(
        portName: "Built-in Speaker",
        portType: .builtInSpeaker,
        isExternalDAC: false,
        isHeadphones: false,
        isBluetooth: false,
        isBuiltInSpeaker: true,
        sampleRate: 44100,
        outputChannels: 2
    )
}

// MARK: - AudioSessionManager

/// Singleton that owns the AVAudioSession configuration.
///
/// Responsibilities:
/// - Configures the session for high-fidelity playback (.playback category)
/// - Monitors route changes (DAC plug/unplug, Bluetooth, headphones)
/// - Publishes the current audio route for UI display
/// - Sets preferred sample rate to match the current track's native rate
@MainActor
final class AudioSessionManager: ObservableObject {
    
    static let shared = AudioSessionManager()
    
    // MARK: - Published State
    
    @Published private(set) var currentRoute: AudioRouteInfo = .builtInSpeaker
    @Published private(set) var isExternalDACConnected: Bool = false
    @Published private(set) var sessionSampleRate: Double = 44100
    @Published private(set) var isSessionActive: Bool = false
    
    // MARK: - Callbacks
    
    /// Called when the audio route changes (e.g. DAC connected/disconnected).
    /// The AudioEngineManager listens to this to reconfigure the engine.
    var onRouteChanged: ((AudioRouteInfo) -> Void)?
    
    /// Called when the session is interrupted (e.g. phone call).
    var onInterruption: ((Bool) -> Void)?  // true = should resume
    
    // MARK: - Private
    
    private var routeChangeObserver: NSObjectProtocol?
    private var interruptionObserver: NSObjectProtocol?
    private var mediaResetObserver: NSObjectProtocol?
    
    private init() {}
    
    // MARK: - Session Configuration
    
    /// Configures and activates the audio session for high-fidelity playback.
    ///
    /// Must be called once at app launch (e.g. in AppDelegate).
    func configureSession() {
        let session = AVAudioSession.sharedInstance()
        
        do {
            // .playback category with .longFormAudio policy for uninterrupted playback.
            // Options:
            //   .allowBluetoothA2DP — permits A2DP streaming to Bluetooth devices
            //   .allowAirPlay — permits AirPlay streaming
            try session.setCategory(
                .playback,
                mode: .default,
                policy: .longFormAudio,
                options: [.allowBluetoothA2DP, .allowAirPlay]
            )
            
            // Request the highest sample rate the hardware can provide.
            // For USB DACs this can be up to 384 kHz.
            try session.setPreferredSampleRate(192000)
            
            // Low-latency buffer for responsive seeking.
            // 0.005s = ~220 samples at 44.1 kHz
            try session.setPreferredIOBufferDuration(0.005)
            
            // Activate the session.
            try session.setActive(true, options: [])
            
            isSessionActive = true
            sessionSampleRate = session.sampleRate
            
            // Read the initial route.
            updateRoute()
            
            // Start observing changes.
            setupObservers()
            
        } catch {
            print("[AudioSession] Configuration failed: \(error.localizedDescription)")
        }
    }
    
    /// Updates the preferred sample rate to match the track being played.
    /// This is critical for bit-perfect DAC output — the session sample rate
    /// must match the file's native rate to avoid resampling.
    func setPreferredSampleRate(_ sampleRate: Double) {
        let session = AVAudioSession.sharedInstance()
        
        do {
            try session.setPreferredSampleRate(sampleRate)
            sessionSampleRate = session.sampleRate
        } catch {
            print("[AudioSession] Failed to set sample rate \(sampleRate): \(error)")
        }
    }
    
    /// Deactivates the session (e.g. when the app goes to background with no playback).
    func deactivateSession() {
        do {
            try AVAudioSession.sharedInstance().setActive(false, options: [.notifyOthersOnDeactivation])
            isSessionActive = false
        } catch {
            print("[AudioSession] Deactivation failed: \(error)")
        }
    }
    
    /// Reactivates the session after an interruption.
    func reactivateSession() {
        do {
            try AVAudioSession.sharedInstance().setActive(true, options: [])
            isSessionActive = true
            sessionSampleRate = AVAudioSession.sharedInstance().sampleRate
            updateRoute()
        } catch {
            print("[AudioSession] Reactivation failed: \(error)")
        }
    }
    
    // MARK: - Route Monitoring
    
    private func updateRoute() {
        let session = AVAudioSession.sharedInstance()
        let route = session.currentRoute
        
        guard let output = route.outputs.first else {
            currentRoute = .builtInSpeaker
            isExternalDACConnected = false
            return
        }
        
        let info = AudioRouteInfo(
            portName: output.portName,
            portType: output.portType,
            isExternalDAC: output.portType == .usbAudio,
            isHeadphones: output.portType == .headphones || output.portType == .headsetMic,
            isBluetooth: output.portType == .bluetoothA2DP || output.portType == .bluetoothLE || output.portType == .bluetoothHFP,
            isBuiltInSpeaker: output.portType == .builtInSpeaker,
            sampleRate: session.sampleRate,
            outputChannels: session.outputNumberOfChannels
        )
        
        currentRoute = info
        isExternalDACConnected = info.isExternalDAC
        sessionSampleRate = session.sampleRate
    }
    
    // MARK: - Observers
    
    private func setupObservers() {
        // Route change (DAC connected, headphones plugged, etc.)
        routeChangeObserver = NotificationCenter.default.addObserver(
            forName: AVAudioSession.routeChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let self else { return }
            
            let reason = notification.userInfo?[AVAudioSessionRouteChangeReasonKey] as? UInt
            let changeReason = AVAudioSession.RouteChangeReason(rawValue: reason ?? 0)
            
            Task { @MainActor in
                self.updateRoute()
                self.onRouteChanged?(self.currentRoute)
                
                // If the old device was removed (e.g. headphones unplugged),
                // the system auto-pauses. We notify the player.
                if changeReason == .oldDeviceUnavailable {
                    self.onInterruption?(false)
                }
            }
        }
        
        // Interruption (phone call, Siri, alarm, etc.)
        interruptionObserver = NotificationCenter.default.addObserver(
            forName: AVAudioSession.interruptionNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let self else { return }
            
            let typeValue = notification.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt ?? 0
            let type = AVAudioSession.InterruptionType(rawValue: typeValue)
            
            Task { @MainActor [weak self] in
                guard let self else { return }
                if type == .began {
                    // Interruption began — pause playback.
                    self.onInterruption?(false)
                } else if type == .ended {
                    // Interruption ended — check if we should resume.
                    let optionsValue = notification.userInfo?[AVAudioSessionInterruptionOptionKey] as? UInt ?? 0
                    let options = AVAudioSession.InterruptionOptions(rawValue: optionsValue)
                    let shouldResume = options.contains(.shouldResume)
                    
                    self.reactivateSession()
                    self.onInterruption?(shouldResume)
                }
            }
        }
        
        // Media services reset (rare but catastrophic — must rebuild engine).
        mediaResetObserver = NotificationCenter.default.addObserver(
            forName: AVAudioSession.mediaServicesWereResetNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.configureSession()
                // The AudioEngineManager should also reinitialize.
            }
        }
    }
    
    deinit {
        if let observer = routeChangeObserver {
            NotificationCenter.default.removeObserver(observer)
        }
        if let observer = interruptionObserver {
            NotificationCenter.default.removeObserver(observer)
        }
        if let observer = mediaResetObserver {
            NotificationCenter.default.removeObserver(observer)
        }
    }
}
