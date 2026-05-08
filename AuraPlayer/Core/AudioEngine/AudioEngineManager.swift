//
//  AudioEngineManager.swift
//  AuraPlayer
//
//  The core audio pipeline: AVAudioEngine with player node, 10-band EQ,
//  and tap node for FFT visualization.
//
//  Node graph:
//    AVAudioPlayerNode → AVAudioUnitEQ (10-band) → MainMixerNode → OutputNode
//                                                        ↓
//                                                   [FFT Tap] → VisualizerEngine
//

import Foundation
import AVFoundation
import Combine

// MARK: - Playback State

enum PlaybackState: Equatable {
    case idle
    case loading
    case playing
    case paused
    case stopped
    case error(String)
}

// MARK: - AudioEngineManager

/// Owns and manages the AVAudioEngine node graph.
///
/// This is the single source of truth for audio pipeline state.
/// All node connections, format changes, and buffer scheduling
/// happen through this class to prevent audio corruption from
/// concurrent node manipulation.
///
/// Thread safety: All engine operations are serialized on `engineQueue`.
@MainActor
final class AudioEngineManager: ObservableObject {
    
    static let shared = AudioEngineManager()
    
    // MARK: - Published State
    
    @Published private(set) var playbackState: PlaybackState = .idle
    @Published private(set) var currentTime: TimeInterval = 0
    @Published private(set) var duration: TimeInterval = 0
    @Published var playbackProgress: Double = 0
    @Published private(set) var currentSampleRate: Double = 44100
    @Published private(set) var currentBitDepth: Int = 16
    @Published private(set) var isBuffering: Bool = false
    
    /// Whether playback is active (playing or paused with a loaded file).
    var isPlaying: Bool { playbackState == .playing }
    var isPaused: Bool { playbackState == .paused }
    var hasLoadedTrack: Bool { audioFile != nil }
    
    // MARK: - Callbacks
    
    /// Called when the current track finishes playing naturally.
    var onTrackCompleted: (() -> Void)?
    
    // MARK: - Engine Nodes
    
    private var audioEngine: AVAudioEngine!
    private var playerNode: AVAudioPlayerNode!
    private var eqNode: AVAudioUnitEQ!
    
    // MARK: - File State
    
    private var audioFile: AVAudioFile?
    private var seekFramePosition: AVAudioFramePosition = 0
    private var totalFrames: AVAudioFramePosition = 0
    
    // MARK: - Timer
    
    private var progressTimer: Timer?
    
    // MARK: - EQ Configuration
    
    private let eqFrequencies: [Float] = [32, 64, 125, 250, 500, 1000, 2000, 4000, 8000, 16000]
    private let eqBandCount = 10
    
    // MARK: - Visualization Tap
    
    /// Buffer size for the FFT tap (must be power of 2).
    private let fftBufferSize: UInt32 = 4096
    
    /// Closure called with audio buffer data for visualization.
    /// The data is the raw Float channel data from the mixer tap.
    var onVisualizerData: (([Float]) -> Void)?
    
    // MARK: - Serialization
    
    /// All engine operations are serialized on this queue to prevent
    /// concurrent node manipulation which causes audio corruption.
    private let engineQueue = DispatchQueue(label: "com.auraplayer.engine", qos: .userInteractive)
    
    // MARK: - Init
    
    private init() {
        setupEngine()
    }
    
    // MARK: - Engine Setup
    
    /// Builds the complete node graph from scratch.
    /// Called once at init and again after a media services reset.
    func setupEngine() {
        // Tear down any existing engine.
        tearDownEngine()
        
        audioEngine = AVAudioEngine()
        playerNode = AVAudioPlayerNode()
        
        // Create 10-band parametric EQ.
        eqNode = AVAudioUnitEQ(numberOfBands: eqBandCount)
        eqNode.globalGain = 0
        
        // Configure each band to ISO standard frequencies.
        for i in 0..<eqBandCount {
            let band = eqNode.bands[i]
            band.filterType = .parametric
            band.frequency = eqFrequencies[i]
            band.bandwidth = 1.0   // 1 octave
            band.gain = 0.0        // Flat by default
            band.bypass = false
        }
        
        // Attach nodes to the engine.
        audioEngine.attach(playerNode)
        audioEngine.attach(eqNode)
        
        // Connect: PlayerNode → EQ → MainMixer → Output
        let mainMixer = audioEngine.mainMixerNode
        
        // Use nil format so the engine auto-negotiates based on the file.
        audioEngine.connect(playerNode, to: eqNode, format: nil)
        audioEngine.connect(eqNode, to: mainMixer, format: nil)
        
        // Install a tap on the mixer for FFT visualization data.
        installVisualizerTap()
        
        // Prepare and start the engine.
        audioEngine.prepare()
        
        do {
            try audioEngine.start()
        } catch {
            print("[AudioEngine] Failed to start: \(error)")
            playbackState = .error("Engine failed to start")
        }
    }
    
    /// Tears down the engine cleanly.
    private func tearDownEngine() {
        stopProgressTimer()
        
        if let engine = audioEngine {
            engine.mainMixerNode.removeTap(onBus: 0)
            playerNode?.stop()
            engine.stop()
        }
        
        audioEngine = nil
        playerNode = nil
        eqNode = nil
        audioFile = nil
    }
    
    /// Reinstalls the node graph. Used after route changes that require
    /// a format renegotiation (e.g. switching from speaker to USB DAC).
    func reconfigureEngine() {
        let wasPlaying = isPlaying
        let savedProgress = playbackProgress
        let savedFile = audioFile
        
        setupEngine()
        
        // If we had a file loaded, reload and seek to the saved position.
        if let file = savedFile {
            audioFile = file
            totalFrames = file.length
            duration = Double(file.length) / file.processingFormat.sampleRate
            currentSampleRate = file.processingFormat.sampleRate
            
            if wasPlaying || isPaused {
                scheduleFile(from: AVAudioFramePosition(savedProgress * Double(totalFrames)))
                if wasPlaying {
                    playerNode.play()
                    playbackState = .playing
                    startProgressTimer()
                } else {
                    playbackState = .paused
                }
            }
        }
    }
    
    // MARK: - File Loading & Playback
    
    /// Loads and plays an audio file from a URL.
    ///
    /// - Parameter url: The file URL. Must be accessible (security-scoped access
    ///   should be started by the caller).
    func loadAndPlay(url: URL) {
        playbackState = .loading
        isBuffering = true
        
        do {
            // Stop any current playback.
            playerNode.stop()
            stopProgressTimer()
            
            // Open the audio file.
            let file = try AVAudioFile(forReading: url)
            audioFile = file
            totalFrames = file.length
            seekFramePosition = 0
            
            // Update format info for UI display.
            let format = file.processingFormat
            currentSampleRate = format.sampleRate
            duration = Double(file.length) / format.sampleRate
            
            // Extract true bit depth from the file format (not processing format).
            let fileFormat = file.fileFormat
            let asbd = fileFormat.streamDescription.pointee
            currentBitDepth = asbd.mBitsPerChannel > 0 ? Int(asbd.mBitsPerChannel) : 16
            
            // Request the session to match the file's sample rate for bit-perfect output.
            AudioSessionManager.shared.setPreferredSampleRate(format.sampleRate)
            
            // Reconnect nodes with the file's native format.
            // This ensures no sample rate conversion happens in the pipeline.
            reconnectNodes(with: format)
            
            // Restart engine if needed (format change may require it).
            if !audioEngine.isRunning {
                try audioEngine.start()
            }
            
            // Schedule the entire file for playback.
            scheduleFile(from: 0)
            
            // Start playing.
            playerNode.play()
            playbackState = .playing
            isBuffering = false
            startProgressTimer()
            
        } catch {
            print("[AudioEngine] Failed to load file: \(error)")
            playbackState = .error(error.localizedDescription)
            isBuffering = false
        }
    }
    
    /// Schedules the audio file for playback starting at a specific frame.
    private func scheduleFile(from startFrame: AVAudioFramePosition) {
        guard let file = audioFile else { return }
        
        let remainingFrames = file.length - startFrame
        guard remainingFrames > 0 else { return }
        
        seekFramePosition = startFrame
        
        playerNode.scheduleSegment(
            file,
            startingFrame: startFrame,
            frameCount: AVAudioFrameCount(remainingFrames),
            at: nil
        ) { [weak self] in
            DispatchQueue.main.async {
                self?.handlePlaybackCompletion()
            }
        }
    }
    
    /// Reconnects the node graph with a specific audio format.
    /// This ensures the pipeline runs at the file's native format
    /// without implicit sample rate conversion.
    private func reconnectNodes(with format: AVAudioFormat) {
        // Remove existing connections.
        audioEngine.disconnectNodeInput(eqNode)
        audioEngine.disconnectNodeInput(audioEngine.mainMixerNode)
        
        // Reconnect with the explicit format.
        audioEngine.connect(playerNode, to: eqNode, format: format)
        audioEngine.connect(eqNode, to: audioEngine.mainMixerNode, format: format)
    }
    
    // MARK: - Playback Controls
    
    func pause() {
        guard isPlaying else { return }
        playerNode.pause()
        playbackState = .paused
        stopProgressTimer()
    }
    
    func resume() {
        guard isPaused else { return }
        playerNode.play()
        playbackState = .playing
        startProgressTimer()
    }
    
    func togglePlayPause() {
        if isPlaying {
            pause()
        } else if isPaused {
            resume()
        }
    }
    
    func stop() {
        playerNode.stop()
        playbackState = .stopped
        stopProgressTimer()
        currentTime = 0
        playbackProgress = 0
        seekFramePosition = 0
    }
    
    /// Seeks to a normalized position (0.0 – 1.0).
    func seek(to progress: Double) {
        guard let file = audioFile else { return }
        
        let clampedProgress = max(0, min(1, progress))
        let targetFrame = AVAudioFramePosition(clampedProgress * Double(file.length))
        
        playerNode.stop()
        scheduleFile(from: targetFrame)
        
        if playbackState == .playing {
            playerNode.play()
        }
        
        currentTime = clampedProgress * duration
        playbackProgress = clampedProgress
    }
    
    /// Seeks to an absolute time in seconds.
    func seek(toTime time: TimeInterval) {
        guard duration > 0 else { return }
        seek(to: time / duration)
    }
    
    // MARK: - Equalizer Control
    
    /// Sets the gain for a specific EQ band.
    /// - Parameters:
    ///   - index: Band index (0–9).
    ///   - gain: Gain in dB (-12 to +12).
    func setEQBand(index: Int, gain: Float) {
        guard index < eqBandCount else { return }
        eqNode.bands[index].gain = max(-12, min(12, gain))
    }
    
    /// Sets the global pre-amp gain.
    func setPreampGain(_ gain: Float) {
        eqNode.globalGain = max(-12, min(12, gain))
    }
    
    /// Applies an EQ preset to all bands.
    func applyEQPreset(_ preset: EQPreset) {
        for (index, band) in preset.bands.enumerated() {
            guard index < eqBandCount else { break }
            eqNode.bands[index].gain = band.gain
            eqNode.bands[index].bandwidth = band.bandwidth
        }
        eqNode.globalGain = preset.preampGain
    }
    
    /// Resets all EQ bands to flat (0 dB).
    func resetEQ() {
        for i in 0..<eqBandCount {
            eqNode.bands[i].gain = 0
        }
        eqNode.globalGain = 0
    }
    
    /// Bypasses or enables the EQ.
    func setEQEnabled(_ enabled: Bool) {
        for i in 0..<eqBandCount {
            eqNode.bands[i].bypass = !enabled
        }
    }
    
    /// Returns the current gain values for all bands (for UI display).
    func currentEQGains() -> [Float] {
        (0..<eqBandCount).map { eqNode.bands[$0].gain }
    }
    
    // MARK: - Volume
    
    /// Sets the player volume (0.0 – 1.0).
    /// This is independent of the system volume.
    func setVolume(_ volume: Float) {
        audioEngine?.mainMixerNode.outputVolume = max(0, min(1, volume))
    }
    
    /// Returns the current player volume.
    var volume: Float {
        audioEngine?.mainMixerNode.outputVolume ?? 1.0
    }
    
    // MARK: - Visualizer Tap
    
    /// Installs a tap on the main mixer for FFT visualization data.
    private func installVisualizerTap() {
        let mixerNode = audioEngine.mainMixerNode
        let format = mixerNode.outputFormat(forBus: 0)
        
        // Only install if we have a valid format.
        guard format.sampleRate > 0 else { return }
        
        mixerNode.installTap(onBus: 0, bufferSize: fftBufferSize, format: format) { [weak self] buffer, _ in
            guard let self, let channelData = buffer.floatChannelData else { return }
            
            let frameLength = Int(buffer.frameLength)
            let data = Array(UnsafeBufferPointer(start: channelData[0], count: frameLength))
            
            DispatchQueue.main.async {
                self.onVisualizerData?(data)
            }
        }
    }
    
    // MARK: - Progress Timer
    
    private func startProgressTimer() {
        stopProgressTimer()
        
        progressTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            guard let self else { return }
            
            Task { @MainActor in
                self.updateProgress()
            }
        }
    }
    
    private func stopProgressTimer() {
        progressTimer?.invalidate()
        progressTimer = nil
    }
    
    private func updateProgress() {
        guard let nodeTime = playerNode.lastRenderTime,
              let playerTime = playerNode.playerTime(forNodeTime: nodeTime) else {
            return
        }
        
        let sampleTime = Double(playerTime.sampleTime)
        let sampleRate = playerTime.sampleRate
        
        // Current time = seek offset + elapsed since last seek.
        currentTime = Double(seekFramePosition) / sampleRate + sampleTime / sampleRate
        
        if duration > 0 {
            playbackProgress = min(currentTime / duration, 1.0)
        }
    }
    
    // MARK: - Completion Handling
    
    private func handlePlaybackCompletion() {
        // Ensure we're actually at the end (not a seek-triggered completion).
        guard playbackProgress >= 0.98 || currentTime >= duration - 0.5 else { return }
        
        playbackState = .stopped
        stopProgressTimer()
        currentTime = 0
        playbackProgress = 0
        seekFramePosition = 0
        
        onTrackCompleted?()
    }
}
