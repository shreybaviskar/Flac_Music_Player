//
//  PlayerViewModel.swift
//  AuraPlayer
//
//  ViewModel bridging PlaybackController, QueueManager, and VisualizerEngine
//  with the Now Playing UI. Provides formatted state, artwork color extraction,
//  and EQ preset management.
//

import Foundation
import SwiftUI
import SwiftData
import Combine

// MARK: - PlayerViewModel

@MainActor
final class PlayerViewModel: ObservableObject {
    
    // MARK: - Dependencies
    
    private let playbackController = PlaybackController.shared
    private let queueManager = QueueManager.shared
    private let visualizer = VisualizerEngine.shared
    
    // MARK: - Published State (Playback)
    
    @Published private(set) var currentTrack: Track?
    @Published private(set) var isPlaying: Bool = false
    @Published private(set) var isPaused: Bool = false
    @Published var currentTime: TimeInterval = 0
    @Published var duration: TimeInterval = 0
    @Published var playbackProgress: Double = 0
    
    // MARK: - Published State (Audio Info)
    
    @Published private(set) var sampleRate: Double = 44100
    @Published private(set) var bitDepth: Int = 16
    @Published private(set) var outputRoute: AudioRouteInfo = .builtInSpeaker
    
    // MARK: - Published State (Queue)
    
    @Published private(set) var isShuffleEnabled: Bool = false
    @Published private(set) var repeatMode: RepeatMode = .off
    @Published private(set) var shuffleMode: ShuffleMode = .random
    @Published private(set) var hasNext: Bool = false
    @Published private(set) var hasPrevious: Bool = false
    @Published private(set) var upcomingTracks: [Track] = []
    
    // MARK: - Published State (UI)
    
    /// Whether the Now Playing sheet is expanded.
    @Published var isNowPlayingExpanded: Bool = false
    
    /// Whether the EQ panel is showing.
    @Published var showingEqualizer: Bool = false
    
    /// Whether the queue panel is showing.
    @Published var showingQueue: Bool = false
    
    /// Whether the user is actively dragging the seek slider.
    @Published var isSeeking: Bool = false
    
    /// The seek position while dragging (0.0 – 1.0).
    @Published var seekPosition: Double = 0
    
    /// Whether the lyrics sheet is showing.
    @Published var showingLyrics: Bool = false
    
    // MARK: - Published State (Artwork Colors)
    
    /// Dominant colors extracted from the current track's album art.
    /// Used for the dynamic background gradient.
    @Published var artworkColors: [Color] = [.purple.opacity(0.6), .black]
    
    /// Primary artwork color (for accents).
    @Published var primaryArtworkColor: Color = .purple
    
    // MARK: - Published State (EQ)
    
    @Published var activeEQPreset: EQPreset?
    @Published var eqGains: [Float] = Array(repeating: 0, count: 10)
    @Published var isEQEnabled: Bool = true
    @Published var preampGain: Float = 0
    
    // MARK: - Published State (Visualizer)
    
    @Published var visualizerBars: [Float] = []
    @Published var isVisualizerActive: Bool = false
    
    // MARK: - Volume
    
    @Published var volume: Float = 1.0 {
        didSet { playbackController.setVolume(volume) }
    }
    
    // MARK: - Combine
    
    private var cancellables = Set<AnyCancellable>()
    
    // MARK: - Init
    
    init() {
        setupBindings()
    }
    
    // MARK: - Bindings
    
    private func setupBindings() {
        // Playback state.
        playbackController.$currentTrack
            .receive(on: DispatchQueue.main)
            .sink { [weak self] track in
                self?.currentTrack = track
                self?.extractArtworkColors(from: track)
            }
            .store(in: &cancellables)
        
        playbackController.$isPlaying
            .receive(on: DispatchQueue.main)
            .assign(to: &$isPlaying)
        
        playbackController.$isPaused
            .receive(on: DispatchQueue.main)
            .assign(to: &$isPaused)
        
        playbackController.$currentTime
            .receive(on: DispatchQueue.main)
            .sink { [weak self] time in
                guard let self, !self.isSeeking else { return }
                self.currentTime = time
            }
            .store(in: &cancellables)
        
        playbackController.$duration
            .receive(on: DispatchQueue.main)
            .assign(to: &$duration)
        
        playbackController.$playbackProgress
            .receive(on: DispatchQueue.main)
            .sink { [weak self] progress in
                guard let self, !self.isSeeking else { return }
                self.playbackProgress = progress
            }
            .store(in: &cancellables)
        
        playbackController.$currentSampleRate
            .receive(on: DispatchQueue.main)
            .assign(to: &$sampleRate)
        
        playbackController.$currentBitDepth
            .receive(on: DispatchQueue.main)
            .assign(to: &$bitDepth)
        
        playbackController.$outputRoute
            .receive(on: DispatchQueue.main)
            .assign(to: &$outputRoute)
        
        // Queue state.
        queueManager.$isShuffleEnabled
            .receive(on: DispatchQueue.main)
            .assign(to: &$isShuffleEnabled)
        
        queueManager.$repeatMode
            .receive(on: DispatchQueue.main)
            .assign(to: &$repeatMode)
        
        queueManager.$shuffleMode
            .receive(on: DispatchQueue.main)
            .assign(to: &$shuffleMode)
        
        queueManager.$hasNext
            .receive(on: DispatchQueue.main)
            .assign(to: &$hasNext)
        
        queueManager.$hasPrevious
            .receive(on: DispatchQueue.main)
            .assign(to: &$hasPrevious)
        
        queueManager.$queue
            .receive(on: DispatchQueue.main)
            .map { [weak self] _ in
                self?.queueManager.upcomingTracks ?? []
            }
            .assign(to: &$upcomingTracks)
        
        // Visualizer.
        visualizer.$bars
            .receive(on: DispatchQueue.main)
            .assign(to: &$visualizerBars)
    }
    
    // MARK: - Playback Controls
    
    func togglePlayPause() {
        playbackController.togglePlayPause()
    }
    
    func play() {
        playbackController.resume()
    }
    
    func pause() {
        playbackController.pause()
    }
    
    func nextTrack() {
        queueManager.advanceToNext()
    }
    
    func previousTrack() {
        queueManager.goToPrevious()
    }
    
    func stop() {
        playbackController.stop()
    }
    
    // MARK: - Queue Management
    
    func playNext(track: Track) {
        queueManager.playNext(track: track)
    }
    
    func playLater(track: Track) {
        queueManager.playLater(track: track)
    }
    
    func jumpToQueueTrack(_ track: Track) {
        queueManager.jumpToTrack(track)
    }
    
    /// Removes tracks from the upcoming queue.
    /// Offsets are relative to `upcomingTracks`, so we map them to the full queue.
    func removeFromQueue(at offsets: IndexSet) {
        let baseIndex = queueManager.currentIndex + 1
        let mappedOffsets = offsets.map { $0 + baseIndex }.sorted(by: >)
        
        for index in mappedOffsets {
            queueManager.removeFromQueue(at: index)
        }
    }
    
    /// Moves tracks within the upcoming queue.
    /// Indices are relative to `upcomingTracks`.
    func moveQueueTrack(from source: IndexSet, to destination: Int) {
        let baseIndex = queueManager.currentIndex + 1
        let mappedSource = IndexSet(source.map { $0 + baseIndex })
        let mappedDestination = destination + baseIndex
        
        queueManager.moveTrack(from: mappedSource, to: mappedDestination)
    }
    
    // MARK: - Seeking
    
    /// Called when the user begins dragging the seek slider.
    func beginSeeking() {
        isSeeking = true
        seekPosition = playbackProgress
    }
    
    /// Called as the user drags the seek slider.
    func updateSeekPosition(_ position: Double) {
        seekPosition = max(0, min(1, position))
        currentTime = seekPosition * duration
    }
    
    /// Called when the user releases the seek slider.
    func endSeeking() {
        playbackController.seek(to: seekPosition)
        isSeeking = false
    }
    
    // MARK: - Shuffle & Repeat
    
    func toggleShuffle() {
        queueManager.isShuffleEnabled.toggle()
    }
    
    func setShuffleMode(_ mode: ShuffleMode) {
        queueManager.shuffleMode = mode
        // Re-shuffle if already enabled.
        if queueManager.isShuffleEnabled {
            queueManager.isShuffleEnabled = false
            queueManager.isShuffleEnabled = true
        }
    }
    
    func cycleRepeatMode() {
        queueManager.cycleRepeatMode()
    }
    

    
    // MARK: - EQ Controls
    
    func applyEQPreset(_ preset: EQPreset) {
        activeEQPreset = preset
        eqGains = preset.bands.map(\.gain)
        preampGain = preset.preampGain
        isEQEnabled = preset.isEnabled
        
        playbackController.applyEQPreset(preset)
    }
    
    func setEQBand(index: Int, gain: Float) {
        guard index < eqGains.count else { return }
        eqGains[index] = gain
        playbackController.setEQBand(index: index, gain: gain)
    }
    
    func setPreampGain(_ gain: Float) {
        preampGain = gain
        AudioEngineManager.shared.setPreampGain(gain)
    }
    
    func toggleEQ() {
        isEQEnabled.toggle()
        playbackController.setEQEnabled(isEQEnabled)
    }
    
    func resetEQ() {
        eqGains = Array(repeating: 0, count: 10)
        preampGain = 0
        playbackController.resetEQ()
        activeEQPreset = nil
    }
    
    /// Saves current EQ gains as a new custom preset.
    func saveCustomPreset(
        name: String,
        modelContext: ModelContext
    ) -> EQPreset {
        let bands = eqGains.enumerated().map { index, gain in
            EQBand(
                frequency: EQFrequency.allCases[index].rawValue,
                gain: gain,
                bandwidth: 1.0
            )
        }
        
        let preset = EQPreset(
            name: name,
            isBuiltIn: false,
            iconName: "slider.horizontal.3",
            bands: bands,
            preampGain: preampGain,
            isEnabled: isEQEnabled
        )
        
        modelContext.insert(preset)
        try? modelContext.save()
        activeEQPreset = preset
        
        return preset
    }
    
    /// Updates an existing custom preset with current gains.
    func updatePreset(_ preset: EQPreset) {
        for (index, gain) in eqGains.enumerated() {
            guard index < preset.bands.count else { break }
            preset.bands[index].gain = gain
        }
        preset.preampGain = preampGain
        preset.isEnabled = isEQEnabled
        preset.dateModified = Date()
    }
    
    /// Deletes a custom EQ preset.
    func deletePreset(_ preset: EQPreset, modelContext: ModelContext) {
        guard !preset.isBuiltIn else { return }
        modelContext.delete(preset)
        try? modelContext.save()
        
        if activeEQPreset?.id == preset.id {
            resetEQ()
        }
    }
    
    // MARK: - Visualizer
    
    func startVisualizer() {
        isVisualizerActive = true
        visualizer.start()
    }
    
    func stopVisualizer() {
        isVisualizerActive = false
        visualizer.stop()
    }
    
    // MARK: - Artwork Color Extraction
    
    /// Extracts dominant colors from album artwork for the dynamic gradient background.
    /// Uses Core Graphics pixel sampling for performance.
    private func extractArtworkColors(from track: Track?) {
        guard let artworkData = track?.artworkData,
              let image = UIImage(data: artworkData),
              let cgImage = image.cgImage else {
            // Fallback gradient.
            withAnimation(.easeInOut(duration: 0.6)) {
                artworkColors = [.purple.opacity(0.6), .black]
                primaryArtworkColor = .purple
            }
            return
        }
        
        // Sample colors from the artwork on a background queue.
        Task {
            let colors = await Task.detached(priority: .userInitiated) {
                return Self.extractColors(from: cgImage)
            }.value
            
            withAnimation(.easeInOut(duration: 0.8)) {
                self.artworkColors = colors.gradient
                self.primaryArtworkColor = colors.primary
            }
        }
    }
    
    /// Samples pixels from a CGImage to extract dominant colors.
    nonisolated private static func extractColors(from cgImage: CGImage) -> (primary: Color, gradient: [Color]) {
        let width = 10
        let height = 10
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        
        var pixelData = [UInt8](repeating: 0, count: width * height * 4)
        
        guard let context = CGContext(
            data: &pixelData,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width * 4,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            return (primary: .purple, gradient: [.purple.opacity(0.6), .black])
        }
        
        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))
        
        // Accumulate color components.
        var totalR: Double = 0, totalG: Double = 0, totalB: Double = 0
        var darkR: Double = 0, darkG: Double = 0, darkB: Double = 0
        var darkCount = 0
        let pixelCount = width * height
        
        for i in 0..<pixelCount {
            let offset = i * 4
            let r = Double(pixelData[offset]) / 255.0
            let g = Double(pixelData[offset + 1]) / 255.0
            let b = Double(pixelData[offset + 2]) / 255.0
            
            totalR += r; totalG += g; totalB += b
            
            // Collect darker pixels for the gradient bottom.
            let brightness = (r + g + b) / 3.0
            if brightness < 0.4 {
                darkR += r; darkG += g; darkB += b
                darkCount += 1
            }
        }
        
        let avgR = totalR / Double(pixelCount)
        let avgG = totalG / Double(pixelCount)
        let avgB = totalB / Double(pixelCount)
        
        let primary = Color(red: avgR, green: avgG, blue: avgB)
        
        let darkAvgR = darkCount > 0 ? darkR / Double(darkCount) : avgR * 0.3
        let darkAvgG = darkCount > 0 ? darkG / Double(darkCount) : avgG * 0.3
        let darkAvgB = darkCount > 0 ? darkB / Double(darkCount) : avgB * 0.3
        
        let gradientTop = Color(red: avgR * 0.7, green: avgG * 0.7, blue: avgB * 0.7)
        let gradientBottom = Color(red: darkAvgR * 0.4, green: darkAvgG * 0.4, blue: darkAvgB * 0.4)
        
        return (primary: primary, gradient: [gradientTop, gradientBottom, .black])
    }
    
    // MARK: - Formatted Properties
    
    /// Formatted current time (e.g. "2:35").
    var formattedCurrentTime: String {
        formatTime(isSeeking ? seekPosition * duration : currentTime)
    }
    
    /// Formatted total duration (e.g. "4:12").
    var formattedDuration: String {
        formatTime(duration)
    }
    
    /// Formatted remaining time (e.g. "-1:37").
    var formattedRemainingTime: String {
        let remaining = duration - (isSeeking ? seekPosition * duration : currentTime)
        return "-\(formatTime(remaining))"
    }
    
    /// Audio quality label for the current track.
    var qualityLabel: String {
        guard let track = currentTrack else { return "" }
        return track.qualityLabel
    }
    
    /// Quality badge text.
    var qualityBadge: String {
        guard let track = currentTrack else { return "" }
        return track.qualityBadge
    }
    
    /// Quality badge color.
    var qualityBadgeColor: Color {
        guard let track = currentTrack else { return .gray }
        return track.qualityColor
    }
    
    /// Whether the current track has artwork.
    var hasArtwork: Bool {
        currentTrack?.artworkData != nil
    }
    
    /// The current track's artwork as a UIImage.
    var artworkImage: UIImage? {
        guard let data = currentTrack?.artworkData else { return nil }
        return UIImage(data: data)
    }
    
    /// Output route description.
    var outputRouteLabel: String {
        outputRoute.qualityLabel
    }
    
    // MARK: - Helpers
    
    private func formatTime(_ time: TimeInterval) -> String {
        let totalSeconds = max(0, Int(time))
        let minutes = totalSeconds / 60
        let seconds = totalSeconds % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
}
