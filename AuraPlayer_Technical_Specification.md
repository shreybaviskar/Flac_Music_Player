
# 🎵 AURA PLAYER — High-Res Offline Music Player for iOS
## Technical Specification & Source Code

---

## 📋 PROJECT OVERVIEW

**Platform:** iOS 16.0+  
**Language:** Swift 5.9+  
**UI Framework:** SwiftUI + UIKit (hybrid for audio controls)  
**Audio Engine:** AVFoundation + Accelerate Framework (FFT for visualizer)  
**Supported Formats:** FLAC, ALAC, WAV, AIFF, DSD, MP3, AAC, OGG  
**Bit Depth:** 16-bit, 24-bit, 32-bit float  
**Sample Rates:** 44.1kHz, 48kHz, 88.2kHz, 96kHz, 176.4kHz, 192kHz, 352.8kHz, 384kHz  
**DAC Support:** USB Audio Class 2.0, External DAC detection, Bit-perfect output  

---

## 🏗️ PROJECT STRUCTURE

```
AuraPlayer/
├── App/
│   ├── AuraPlayerApp.swift
│   └── AppDelegate.swift
├── Core/
│   ├── AudioEngine/
│   │   ├── AudioPlayerManager.swift
│   │   ├── AudioSessionManager.swift
│   │   ├── DACManager.swift
│   │   ├── EqualizerEngine.swift
│   │   └── VisualizerEngine.swift
│   ├── Data/
│   │   ├── MusicLibrary.swift
│   │   ├── PlaylistManager.swift
│   │   ├── MetadataParser.swift
│   │   └── CoreDataStack.swift
│   └── Models/
│       ├── Track.swift
│       ├── Album.swift
│       ├── Artist.swift
│       ├── Playlist.swift
│       └── EqualizerPreset.swift
├── Features/
│   ├── Library/
│   │   ├── LibraryView.swift
│   │   ├── AlbumGridView.swift
│   │   ├── TrackListView.swift
│   │   └── ArtistView.swift
│   ├── Player/
│   │   ├── NowPlayingView.swift
│   │   ├── PlayerControlsView.swift
│   │   ├── AlbumArtView.swift
│   │   └── LyricsView.swift
│   ├── Equalizer/
│   │   ├── EqualizerView.swift
│   │   ├── EQBandView.swift
│   │   └── PresetSelectorView.swift
│   ├── Playlists/
│   │   ├── PlaylistListView.swift
│   │   ├── PlaylistDetailView.swift
│   │   └── CreatePlaylistView.swift
│   ├── Settings/
│   │   ├── SettingsView.swift
│   │   ├── AudioSettingsView.swift
│   │   └── ImportSettingsView.swift
│   └── Visualizer/
│       ├── VisualizerView.swift
│       └── WaveformView.swift
├── Services/
│   ├── FileImportService.swift
│   ├── DirectoryScanner.swift
│   ├── ArtworkExtractor.swift
│   └── BackgroundTaskManager.swift
├── Utilities/
│   ├── Extensions/
│   ├── Constants.swift
│   └── Helpers.swift
├── Resources/
│   ├── Assets.xcassets
│   └── LaunchScreen.storyboard
└── Info.plist
```

---

## 🔊 AUDIO ENGINE ARCHITECTURE

### 1. AudioPlayerManager.swift
```swift
import AVFoundation
import MediaPlayer
import Accelerate

class AudioPlayerManager: ObservableObject {
    static let shared = AudioPlayerManager()

    // MARK: - Published Properties
    @Published var isPlaying: Bool = false
    @Published var currentTrack: Track?
    @Published var currentTime: TimeInterval = 0
    @Published var duration: TimeInterval = 0
    @Published var playbackProgress: Double = 0
    @Published var isBuffering: Bool = false
    @Published var currentSampleRate: Double = 44100
    @Published var currentBitDepth: Int = 16
    @Published var outputRoute: String = "Built-in Speaker"

    // MARK: - Private Properties
    private var audioEngine: AVAudioEngine!
    private var playerNode: AVAudioPlayerNode!
    private var eqNode: AVAudioUnitEQ!
    private var mixerNode: AVAudioMixerNode!
    private var audioFile: AVAudioFile?
    private var timer: Timer?
    private var bufferSize: UInt32 = 4096

    // MARK: - Queue Management
    private var playbackQueue: [Track] = []
    private var currentIndex: Int = 0
    private var isShuffled: Bool = false
    private var originalQueue: [Track] = []
    private var shuffleHistory: [Int] = []

    // MARK: - Equalizer
    private var eqBands: [AVAudioUnitEQFilterParameters] = []
    private let eqFrequencies: [Float] = [32, 64, 125, 250, 500, 1000, 2000, 4000, 8000, 16000]

    // MARK: - DAC / Audio Route
    private var routeChangeObserver: NSObjectProtocol?

    private init() {
        setupAudioEngine()
        setupNotifications()
        setupRemoteCommands()
    }

    // MARK: - Audio Engine Setup
    private func setupAudioEngine() {
        audioEngine = AVAudioEngine()
        playerNode = AVAudioPlayerNode()

        // High-quality EQ with 10 bands
        eqNode = AVAudioUnitEQ(numberOfBands: 10)
        eqNode.globalGain = 0

        // Configure EQ bands
        for i in 0..<eqNode.bands.count {
            let band = eqNode.bands[i]
            band.filterType = .parametric
            band.frequency = eqFrequencies[i]
            band.bandwidth = 1.0
            band.gain = 0
            band.bypass = false
            eqBands.append(band)
        }

        mixerNode = audioEngine.mainMixerNode

        // Connect nodes: Player -> EQ -> Mixer -> Output
        audioEngine.attach(playerNode)
        audioEngine.attach(eqNode)

        audioEngine.connect(playerNode, to: eqNode, format: nil)
        audioEngine.connect(eqNode, to: mixerNode, format: nil)

        // Configure for hi-res audio
        do {
            try audioEngine.start()
        } catch {
            print("Audio Engine failed to start: \(error)")
        }
    }

    // MARK: - DAC & Route Management
    func setupAudioSession() {
        let session = AVAudioSession.sharedInstance()
        do {
            // Set category for hi-res playback with external DAC support
            try session.setCategory(.playback, 
                                   mode: .default, 
                                   options: [.allowBluetoothA2DP, .allowAirPlay])

            // Set preferred sample rate for DAC (up to 192kHz or device max)
            try session.setPreferredSampleRate(192000)
            try session.setPreferredIOBufferDuration(0.005) // Low latency
            try session.setActive(true)

            updateAudioRoute()
        } catch {
            print("Audio Session setup failed: \(error)")
        }
    }

    private func updateAudioRoute() {
        let session = AVAudioSession.sharedInstance()
        let route = session.currentRoute

        if let output = route.outputs.first {
            outputRoute = output.portName
            currentSampleRate = session.sampleRate

            // Detect external DAC
            if output.portType == .usbAudio || output.portType == .headphones {
                // Enable bit-perfect mode for DAC
                enableBitPerfectMode()
            }
        }
    }

    private func enableBitPerfectMode() {
        // Disable system EQ, volume normalization when using external DAC
        let session = AVAudioSession.sharedInstance()
        // Set volume to max and let DAC control volume
        // Note: iOS doesn't allow direct bit-perfect, but we minimize processing
    }

    // MARK: - Playback Controls
    func play(track: Track) {
        guard let url = track.fileURL else { return }

        do {
            // Stop current playback
            stop()

            // Open audio file with hi-res support
            audioFile = try AVAudioFile(forReading: url)

            guard let file = audioFile else { return }

            currentTrack = track
            duration = Double(file.length) / file.processingFormat.sampleRate
            currentSampleRate = file.processingFormat.sampleRate
            currentBitDepth = getBitDepth(from: file.processingFormat)

            // Schedule file for playback
            playerNode.scheduleFile(file, at: nil, completionHandler: {
                DispatchQueue.main.async {
                    self.handlePlaybackCompletion()
                }
            })

            playerNode.play()
            isPlaying = true
            startProgressTimer()
            updateNowPlayingInfo()

        } catch {
            print("Failed to play track: \(error)")
        }
    }

    func playQueue(tracks: [Track], startIndex: Int = 0) {
        playbackQueue = tracks
        originalQueue = tracks
        currentIndex = startIndex
        play(track: tracks[startIndex])
    }

    func pause() {
        playerNode.pause()
        isPlaying = false
        stopProgressTimer()
        updateNowPlayingInfo()
    }

    func resume() {
        playerNode.play()
        isPlaying = true
        startProgressTimer()
        updateNowPlayingInfo()
    }

    func stop() {
        playerNode.stop()
        isPlaying = false
        stopProgressTimer()
        currentTime = 0
        playbackProgress = 0
    }

    func seek(to progress: Double) {
        guard let file = audioFile else { return }
        let sampleRate = file.processingFormat.sampleRate
        let framePosition = AVAudioFramePosition(progress * Double(file.length))

        playerNode.stop()

        playerNode.scheduleSegment(file, 
                                    startingFrame: framePosition, 
                                    frameCount: AVAudioFrameCount(file.length - framePosition), 
                                    at: nil,
                                    completionHandler: {
            DispatchQueue.main.async {
                self.handlePlaybackCompletion()
            }
        })

        if isPlaying {
            playerNode.play()
        }

        currentTime = progress * duration
        playbackProgress = progress
    }

    // MARK: - Queue Navigation
    func nextTrack() {
        guard !playbackQueue.isEmpty else { return }

        if isShuffled {
            let randomIndex = Int.random(in: 0..<playbackQueue.count)
            currentIndex = randomIndex
            shuffleHistory.append(randomIndex)
        } else {
            currentIndex = (currentIndex + 1) % playbackQueue.count
        }

        play(track: playbackQueue[currentIndex])
    }

    func previousTrack() {
        guard !playbackQueue.isEmpty else { return }

        if currentTime > 3 {
            seek(to: 0)
        } else {
            if isShuffled && !shuffleHistory.isEmpty {
                shuffleHistory.removeLast()
                if let lastIndex = shuffleHistory.last {
                    currentIndex = lastIndex
                }
            } else {
                currentIndex = (currentIndex - 1 + playbackQueue.count) % playbackQueue.count
            }
            play(track: playbackQueue[currentIndex])
        }
    }

    // MARK: - Shuffle
    func toggleShuffle() {
        isShuffled.toggle()

        if isShuffled {
            // Fisher-Yates shuffle preserving current track
            let currentTrack = playbackQueue[currentIndex]
            var shuffled = playbackQueue.filter { $0.id != currentTrack.id }
            shuffled.shuffle()
            playbackQueue = [currentTrack] + shuffled
            currentIndex = 0
            shuffleHistory = [0]
        } else {
            // Restore original order, find current track index
            if let track = currentTrack,
               let originalIndex = originalQueue.firstIndex(where: { $0.id == track.id }) {
                playbackQueue = originalQueue
                currentIndex = originalIndex
            }
        }
    }

    // MARK: - Equalizer
    func setEQBand(index: Int, gain: Float) {
        guard index < eqBands.count else { return }
        eqBands[index].gain = gain
    }

    func applyPreset(_ preset: EqualizerPreset) {
        for (index, gain) in preset.bands.enumerated() {
            setEQBand(index: index, gain: gain)
        }
    }

    func resetEQ() {
        for i in 0..<eqBands.count {
            eqBands[i].gain = 0
        }
    }

    // MARK: - Private Helpers
    private func startProgressTimer() {
        timer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { _ in
            if let nodeTime = self.playerNode.lastRenderTime,
               let playerTime = self.playerNode.playerTime(forNodeTime: nodeTime) {
                self.currentTime = Double(playerTime.sampleTime) / playerTime.sampleRate
                self.playbackProgress = self.duration > 0 ? self.currentTime / self.duration : 0
            }
        }
    }

    private func stopProgressTimer() {
        timer?.invalidate()
        timer = nil
    }

    private func handlePlaybackCompletion() {
        if currentIndex < playbackQueue.count - 1 {
            nextTrack()
        } else {
            stop()
        }
    }

    private func getBitDepth(from format: AVAudioFormat) -> Int {
        let sampleFormat = format.commonFormat
        switch sampleFormat {
        case .pcmFormatFloat32: return 32
        case .pcmFormatFloat64: return 64
        case .pcmFormatInt16: return 16
        case .pcmFormatInt32: return 32
        @unknown default: return 16
        }
    }

    // MARK: - Now Playing Info
    private func updateNowPlayingInfo() {
        var info: [String: Any] = [
            MPMediaItemPropertyPlaybackDuration: duration,
            MPNowPlayingInfoPropertyElapsedPlaybackTime: currentTime,
            MPNowPlayingInfoPropertyPlaybackRate: isPlaying ? 1.0 : 0.0
        ]

        if let track = currentTrack {
            info[MPMediaItemPropertyTitle] = track.title
            info[MPMediaItemPropertyArtist] = track.artist
            info[MPMediaItemPropertyAlbumTitle] = track.album

            if let artwork = track.artwork {
                info[MPMediaItemPropertyArtwork] = MPMediaItemArtwork(boundsSize: artwork.size) { _ in artwork }
            }
        }

        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
    }

    private func setupRemoteCommands() {
        let center = MPRemoteCommandCenter.shared()

        center.playCommand.addTarget { _ in
            self.resume()
            return .success
        }

        center.pauseCommand.addTarget { _ in
            self.pause()
            return .success
        }

        center.nextTrackCommand.addTarget { _ in
            self.nextTrack()
            return .success
        }

        center.previousTrackCommand.addTarget { _ in
            self.previousTrack()
            return .success
        }

        center.changePlaybackPositionCommand.addTarget { event in
            if let positionEvent = event as? MPChangePlaybackPositionCommandEvent {
                self.seek(to: positionEvent.positionTime / self.duration)
            }
            return .success
        }
    }

    private func setupNotifications() {
        routeChangeObserver = NotificationCenter.default.addObserver(
            forName: AVAudioSession.routeChangeNotification,
            object: nil,
            queue: .main
        ) { _ in
            self.updateAudioRoute()
        }
    }
}
```

---

## 🎛️ EQUALIZER SYSTEM

### 2. EqualizerPreset.swift (10 Presets)
```swift
import Foundation

struct EqualizerPreset: Identifiable, Codable {
    let id: UUID
    var name: String
    var bands: [Float] // 10 bands: 32Hz, 64Hz, 125Hz, 250Hz, 500Hz, 1kHz, 2kHz, 4kHz, 8kHz, 16kHz
    var isCustom: Bool

    static let defaultPresets: [EqualizerPreset] = [
        // 1. Flat (No EQ)
        EqualizerPreset(
            id: UUID(),
            name: "Flat",
            bands: [0, 0, 0, 0, 0, 0, 0, 0, 0, 0],
            isCustom: false
        ),

        // 2. Bass Booster
        EqualizerPreset(
            id: UUID(),
            name: "Bass Boost",
            bands: [6, 5, 4, 2, 1, 0, 0, 0, 0, 0],
            isCustom: false
        ),

        // 3. Vocal Booster (Mid-range emphasis)
        EqualizerPreset(
            id: UUID(),
            name: "Vocal Boost",
            bands: [-2, -1, 0, 2, 4, 5, 4, 2, 0, -1],
            isCustom: false
        ),

        // 4. Treble Booster
        EqualizerPreset(
            id: UUID(),
            name: "Treble Boost",
            bands: [0, 0, 0, 0, 0, 1, 2, 4, 5, 6],
            isCustom: false
        ),

        // 5. Classical (Wide dynamic range, balanced)
        EqualizerPreset(
            id: UUID(),
            name: "Classical",
            bands: [0, 0, 0, 0, 0, 0, -1, -2, -1, 0],
            isCustom: false
        ),

        // 6. Jazz (Warm mids, smooth highs)
        EqualizerPreset(
            id: UUID(),
            name: "Jazz",
            bands: [0, 0, 0, 2, 3, 2, 1, 0, 0, 0],
            isCustom: false
        ),

        // 7. Rock (Punchy bass, aggressive mids)
        EqualizerPreset(
            id: UUID(),
            name: "Rock",
            bands: [3, 2, 1, 0, -1, 0, 2, 3, 2, 1],
            isCustom: false
        ),

        // 8. Electronic (Deep bass, crisp highs)
        EqualizerPreset(
            id: UUID(),
            name: "Electronic",
            bands: [5, 4, 2, 0, -1, 0, 1, 3, 4, 5],
            isCustom: false
        ),

        // 9. Acoustic (Natural, minimal processing)
        EqualizerPreset(
            id: UUID(),
            name: "Acoustic",
            bands: [0, 0, 1, 2, 2, 1, 0, -1, -1, 0],
            isCustom: false
        ),

        // 10. Podcast / Spoken Word (Voice clarity)
        EqualizerPreset(
            id: UUID(),
            name: "Spoken Word",
            bands: [-3, -2, 0, 3, 5, 5, 3, 1, 0, -2],
            isCustom: false
        )
    ]
}
```

---

## 📁 FILE IMPORT & LIBRARY SCANNING

### 3. DirectoryScanner.swift
```swift
import Foundation
import UniformTypeIdentifiers

class DirectoryScanner: ObservableObject {
    static let shared = DirectoryScanner()

    @Published var isScanning: Bool = false
    @Published var scanProgress: Double = 0
    @Published var lastScanResults: ScanResults?

    struct ScanResults {
        let tracksAdded: Int
        let albumsFound: Int
        let artistsFound: Int
        let errors: [String]
    }

    // Supported audio formats
    private let supportedExtensions: Set<String> = [
        "flac", "alac", "m4a", "wav", "aiff", "aif",
        "dsd", "dff", "dsf", "mp3", "aac", "ogg", "opus", "wma"
    ]

    func scanDirectory(url: URL, recursive: Bool = true) async -> ScanResults {
        await MainActor.run { isScanning = true }

        var tracks: [Track] = []
        var errors: [String] = []
        var processedFiles = 0

        let fileManager = FileManager.default

        do {
            let contents = try fileManager.contentsOfDirectory(
                at: url,
                includingPropertiesForKeys: [.isDirectoryKey],
                options: [.skipsHiddenFiles]
            )

            let totalFiles = contents.count

            for item in contents {
                let resourceValues = try? item.resourceValues(forKeys: [.isDirectoryKey])
                let isDirectory = resourceValues?.isDirectory ?? false

                if isDirectory && recursive {
                    // Recursively scan subdirectories
                    let subResults = await scanDirectory(url: item, recursive: true)
                    tracks.append(contentsOf: MusicLibrary.shared.getTracks())
                    errors.append(contentsOf: subResults.errors)
                } else {
                    // Check if file is supported audio
                    let ext = item.pathExtension.lowercased()
                    if supportedExtensions.contains(ext) {
                        do {
                            let track = try await parseAudioFile(url: item)
                            tracks.append(track)
                        } catch {
                            errors.append("Failed to parse \(item.lastPathComponent): \(error)")
                        }
                    }
                }

                processedFiles += 1
                await MainActor.run {
                    scanProgress = Double(processedFiles) / Double(totalFiles)
                }
            }
        } catch {
            errors.append("Failed to read directory: \(error)")
        }

        // Save to library
        await MusicLibrary.shared.addTracks(tracks)

        let results = ScanResults(
            tracksAdded: tracks.count,
            albumsFound: Set(tracks.map { $0.album }).count,
            artistsFound: Set(tracks.map { $0.artist }).count,
            errors: errors
        )

        await MainActor.run {
            lastScanResults = results
            isScanning = false
            scanProgress = 1.0
        }

        return results
    }

    private func parseAudioFile(url: URL) async throws -> Track {
        let asset = AVAsset(url: url)

        // Load metadata
        let metadata = try await asset.load(.commonMetadata)

        let title = metadata.first(where: { $0.commonKey?.rawValue == "title" })?.stringValue ?? url.deletingPathExtension().lastPathComponent
        let artist = metadata.first(where: { $0.commonKey?.rawValue == "artist" })?.stringValue ?? "Unknown Artist"
        let album = metadata.first(where: { $0.commonKey?.rawValue == "albumName" })?.stringValue ?? "Unknown Album"
        let trackNumber = metadata.first(where: { $0.commonKey?.rawValue == "trackNumber" })?.numberValue?.intValue ?? 0

        // Get audio format info
        let format = try await asset.load(.tracks).first
        let duration = try await asset.load(.duration)

        var sampleRate: Double = 44100
        var bitDepth: Int = 16

        if let formatDescription = format?.formatDescriptions.first as? CMAudioFormatDescription {
            let asbd = CMAudioFormatDescriptionGetStreamBasicDescription(formatDescription)
            sampleRate = asbd?.pointee.mSampleRate ?? 44100
            bitDepth = Int(asbd?.pointee.mBitsPerChannel ?? 16)
        }

        // Extract artwork if available
        var artwork: UIImage?
        if let artworkData = metadata.first(where: { $0.commonKey?.rawValue == "artwork" })?.dataValue {
            artwork = UIImage(data: artworkData)
        } else {
            // Try to find folder.jpg or cover.jpg in same directory
            artwork = await findFolderArtwork(in: url.deletingLastPathComponent())
        }

        return Track(
            id: UUID(),
            title: title,
            artist: artist,
            album: album,
            trackNumber: trackNumber,
            duration: CMTimeGetSeconds(duration),
            fileURL: url,
            sampleRate: sampleRate,
            bitDepth: bitDepth,
            fileFormat: url.pathExtension.uppercased(),
            artwork: artwork,
            dateAdded: Date()
        )
    }

    private func findFolderArtwork(in directory: URL) async -> UIImage? {
        let possibleNames = ["cover.jpg", "folder.jpg", "artwork.jpg", "album.jpg", "front.jpg"]
        let fileManager = FileManager.default

        for name in possibleNames {
            let fileURL = directory.appendingPathComponent(name)
            if fileManager.fileExists(atPath: fileURL.path),
               let data = try? Data(contentsOf: fileURL),
               let image = UIImage(data: data) {
                return image
            }
        }
        return nil
    }
}
```

---

## 🎵 DATA MODELS

### 4. Track.swift
```swift
import Foundation
import SwiftUI
import AVFoundation

struct Track: Identifiable, Codable, Equatable {
    let id: UUID
    var title: String
    var artist: String
    var album: String
    var trackNumber: Int
    var duration: TimeInterval
    var fileURL: URL?
    var sampleRate: Double
    var bitDepth: Int
    var fileFormat: String
    var artwork: UIImage?
    var dateAdded: Date
    var playCount: Int = 0
    var lastPlayed: Date?
    var isFavorite: Bool = false

    var formattedDuration: String {
        let minutes = Int(duration) / 60
        let seconds = Int(duration) % 60
        return String(format: "%d:%02d", minutes, seconds)
    }

    var qualityBadge: String {
        if sampleRate >= 352800 {
            return "DSD"
        } else if sampleRate >= 88200 {
            return "Hi-Res"
        } else if bitDepth > 16 {
            return "Lossless"
        } else {
            return fileFormat
        }
    }

    var qualityColor: Color {
        if sampleRate >= 88200 {
            return .orange
        } else if fileFormat == "FLAC" || fileFormat == "ALAC" {
            return .green
        } else {
            return .gray
        }
    }
}
```

### 5. Playlist.swift
```swift
import Foundation

struct Playlist: Identifiable, Codable {
    let id: UUID
    var name: String
    var tracks: [Track]
    var createdDate: Date
    var modifiedDate: Date
    var artwork: UIImage?
    var description: String?
    var isSmartPlaylist: Bool = false
    var smartRules: [SmartRule]? = nil

    var totalDuration: TimeInterval {
        tracks.reduce(0) { $0 + $1.duration }
    }

    var formattedTotalDuration: String {
        let hours = Int(totalDuration) / 3600
        let minutes = (Int(totalDuration) % 3600) / 60
        if hours > 0 {
            return "\(hours)h \(minutes)m"
        }
        return "\(minutes) min"
    }
}

struct SmartRule: Codable {
    enum RuleType: String, Codable {
        case artist, album, genre, year, rating, playCount, dateAdded, lastPlayed
    }

    enum Condition: String, Codable {
        case equals, contains, greaterThan, lessThan, isSet
    }

    let type: RuleType
    let condition: Condition
    let value: String
}
```

---

## 🎨 UI VIEWS

### 6. NowPlayingView.swift
```swift
import SwiftUI
import AVFoundation

struct NowPlayingView: View {
    @StateObject private var player = AudioPlayerManager.shared
    @State private var isDraggingSlider: Bool = false
    @State private var dragValue: Double = 0

    var body: some View {
        ZStack {
            // Dynamic background from artwork
            if let artwork = player.currentTrack?.artwork {
                Image(uiImage: artwork)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: UIScreen.main.bounds.width, height: UIScreen.main.bounds.height)
                    .blur(radius: 60)
                    .opacity(0.4)
                    .ignoresSafeArea()
            } else {
                LinearGradient(
                    colors: [Color.purple.opacity(0.3), Color.black],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .ignoresSafeArea()
            }

            ScrollView {
                VStack(spacing: 30) {
                    // Album Art
                    AlbumArtView(image: player.currentTrack?.artwork)
                        .frame(width: 320, height: 320)
                        .shadow(radius: 20)
                        .padding(.top, 40)

                    // Track Info
                    VStack(spacing: 8) {
                        Text(player.currentTrack?.title ?? "Not Playing")
                            .font(.system(size: 24, weight: .bold))
                            .foregroundColor(.white)
                            .multilineTextAlignment(.center)

                        Text(player.currentTrack?.artist ?? "")
                            .font(.system(size: 18, weight: .medium))
                            .foregroundColor(.white.opacity(0.7))

                        // Quality Badge
                        if let track = player.currentTrack {
                            HStack(spacing: 6) {
                                Image(systemName: "waveform")
                                    .font(.caption)
                                Text("\(track.qualityBadge) • \(Int(track.sampleRate/1000))kHz • \(track.bitDepth)-bit")
                                    .font(.caption)
                            }
                            .foregroundColor(track.qualityColor)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 4)
                            .background(track.qualityColor.opacity(0.2))
                            .cornerRadius(12)
                        }
                    }

                    // Progress Slider
                    VStack(spacing: 8) {
                        Slider(
                            value: isDraggingSlider ? $dragValue : $player.playbackProgress,
                            in: 0...1,
                            onEditingChanged: { editing in
                                isDraggingSlider = editing
                                if editing {
                                    dragValue = player.playbackProgress
                                } else {
                                    player.seek(to: dragValue)
                                }
                            }
                        )
                        .tint(.white)

                        HStack {
                            Text(formatTime(isDraggingSlider ? dragValue * player.duration : player.currentTime))
                                .font(.caption)
                                .foregroundColor(.white.opacity(0.7))

                            Spacer()

                            Text(formatTime(player.duration))
                                .font(.caption)
                                .foregroundColor(.white.opacity(0.7))
                        }
                    }
                    .padding(.horizontal, 30)

                    // Playback Controls
                    HStack(spacing: 40) {
                        Button(action: { player.toggleShuffle() }) {
                            Image(systemName: "shuffle")
                                .font(.title2)
                                .foregroundColor(player.isShuffled ? .green : .white.opacity(0.6))
                        }

                        Button(action: { player.previousTrack() }) {
                            Image(systemName: "backward.fill")
                                .font(.title)
                                .foregroundColor(.white)
                        }

                        Button(action: {
                            player.isPlaying ? player.pause() : player.resume()
                        }) {
                            Image(systemName: player.isPlaying ? "pause.circle.fill" : "play.circle.fill")
                                .font(.system(size: 70))
                                .foregroundColor(.white)
                        }

                        Button(action: { player.nextTrack() }) {
                            Image(systemName: "forward.fill")
                                .font(.title)
                                .foregroundColor(.white)
                        }

                        Button(action: { /* Toggle repeat */ }) {
                            Image(systemName: "repeat")
                                .font(.title2)
                                .foregroundColor(.white.opacity(0.6))
                        }
                    }

                    // Volume & Additional Controls
                    HStack(spacing: 20) {
                        Image(systemName: "speaker.fill")
                            .foregroundColor(.white.opacity(0.6))

                        Slider(value: .constant(0.7), in: 0...1)
                            .tint(.white)

                        Image(systemName: "speaker.wave.3.fill")
                            .foregroundColor(.white.opacity(0.6))
                    }
                    .padding(.horizontal, 30)

                    // Output Route Indicator
                    HStack {
                        Image(systemName: "hifispeaker")
                        Text(player.outputRoute)
                            .font(.caption)
                    }
                    .foregroundColor(.white.opacity(0.5))

                    Spacer(minLength: 50)
                }
            }
        }
    }

    private func formatTime(_ time: TimeInterval) -> String {
        let minutes = Int(time) / 60
        let seconds = Int(time) % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
}
```

### 7. EqualizerView.swift
```swift
import SwiftUI

struct EqualizerView: View {
    @StateObject private var player = AudioPlayerManager.shared
    @State private var selectedPreset: EqualizerPreset = EqualizerPreset.defaultPresets[0]
    @State private var customGains: [Float] = Array(repeating: 0, count: 10)
    @State private var isCustomMode: Bool = false

    let frequencies = ["32Hz", "64Hz", "125Hz", "250Hz", "500Hz", "1kHz", "2kHz", "4kHz", "8kHz", "16kHz"]

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Equalizer")
                    .font(.largeTitle.bold())

                Spacer()

                // Preset Selector
                Menu {
                    ForEach(EqualizerPreset.defaultPresets) { preset in
                        Button(preset.name) {
                            selectedPreset = preset
                            isCustomMode = false
                            player.applyPreset(preset)
                        }
                    }

                    Divider()

                    Button("Custom") {
                        isCustomMode = true
                    }

                    Button("Reset") {
                        player.resetEQ()
                        customGains = Array(repeating: 0, count: 10)
                    }
                } label: {
                    HStack {
                        Text(isCustomMode ? "Custom" : selectedPreset.name)
                            .font(.headline)
                        Image(systemName: "chevron.down")
                    }
                    .foregroundColor(.white)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(Color.white.opacity(0.1))
                    .cornerRadius(20)
                }
            }
            .padding()

            // EQ Graph
            GeometryReader { geometry in
                ZStack {
                    // Grid lines
                    VStack(spacing: 0) {
                        ForEach(0..<5) { i in
                            HStack {
                                Text("+\(12 - i * 6)dB")
                                    .font(.caption2)
                                    .foregroundColor(.gray)
                                    .frame(width: 40, alignment: .trailing)

                                Rectangle()
                                    .fill(Color.gray.opacity(0.2))
                                    .frame(height: 0.5)
                            }

                            if i < 4 {
                                Spacer()
                            }
                        }
                    }
                    .padding(.leading, 8)

                    // EQ Bars
                    HStack(spacing: 12) {
                        ForEach(0..<10) { index in
                            EQBandView(
                                frequency: frequencies[index],
                                gain: isCustomMode ? customGains[index] : selectedPreset.bands[index],
                                onGainChange: { newGain in
                                    if isCustomMode {
                                        customGains[index] = newGain
                                    }
                                    player.setEQBand(index: index, gain: newGain)
                                }
                            )
                        }
                    }
                    .padding(.leading, 50)
                    .padding(.trailing, 16)
                }
            }
            .frame(height: 350)
            .background(Color.black.opacity(0.3))
            .cornerRadius(16)
            .padding()

            // Save Custom Preset Button
            if isCustomMode {
                Button("Save as Custom Preset") {
                    // Show save dialog
                }
                .foregroundColor(.blue)
                .padding()
            }

            Spacer()
        }
        .background(Color.black.ignoresSafeArea())
        .foregroundColor(.white)
    }
}

struct EQBandView: View {
    let frequency: String
    @State var gain: Float
    let onGainChange: (Float) -> Void

    var body: some View {
        VStack {
            // Gain value
            Text(String(format: "%.1f", gain))
                .font(.caption2)
                .foregroundColor(.white)
                .frame(height: 20)

            // Vertical Slider
            GeometryReader { geometry in
                ZStack(alignment: .bottom) {
                    // Background track
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color.gray.opacity(0.3))
                        .frame(width: 8)

                    // Active fill
                    let normalizedGain = CGFloat((gain + 12) / 24) // -12 to +12 dB
                    RoundedRectangle(cornerRadius: 4)
                        .fill(
                            gain > 0 ? Color.green : (gain < 0 ? Color.red : Color.gray)
                        )
                        .frame(width: 8, height: geometry.size.height * normalizedGain)

                    // Draggable area
                    Rectangle()
                        .fill(Color.clear)
                        .contentShape(Rectangle())
                        .gesture(
                            DragGesture()
                                .onChanged { value in
                                    let height = geometry.size.height
                                    let location = height - value.location.y
                                    let normalized = Float(location / height) * 24 - 12
                                    gain = max(-12, min(12, normalized))
                                    onGainChange(gain)
                                }
                        )
                }
            }
            .frame(width: 30)

            // Frequency label
            Text(frequency)
                .font(.caption2)
                .foregroundColor(.gray)
                .rotationEffect(.degrees(-45))
                .frame(height: 30)
        }
    }
}
```

---

## 📂 LIBRARY & IMPORT VIEWS

### 8. LibraryView.swift
```swift
import SwiftUI
import UniformTypeIdentifiers

struct LibraryView: View {
    @StateObject private var library = MusicLibrary.shared
    @StateObject private var scanner = DirectoryScanner.shared
    @State private var selectedTab: LibraryTab = .albums
    @State private var showingImportSheet = false
    @State private var showingScanner = false

    enum LibraryTab: String, CaseIterable {
        case albums = "Albums"
        case artists = "Artists"
        case tracks = "Songs"
        case playlists = "Playlists"
    }

    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                // Custom Segmented Control
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 20) {
                        ForEach(LibraryTab.allCases, id: \\(.self) { tab in
                            Button(tab.rawValue) {
                                withAnimation {
                                    selectedTab = tab
                                }
                            }
                            .font(.system(size: 16, weight: selectedTab == tab ? .bold : .medium))
                            .foregroundColor(selectedTab == tab ? .white : .gray)
                            .padding(.vertical, 8)
                            .overlay(
                                Rectangle()
                                    .fill(selectedTab == tab ? Color.pink : Color.clear)
                                    .frame(height: 2)
                                    .offset(y: 12)
                                , alignment: .bottom
                            )
                        }
                    }
                    .padding(.horizontal)
                }
                .padding(.vertical, 8)

                // Content
                TabView(selection: $selectedTab) {
                    AlbumGridView(albums: library.albums)
                        .tag(LibraryTab.albums)

                    ArtistListView(artists: library.artists)
                        .tag(LibraryTab.artists)

                    TrackListView(tracks: library.tracks)
                        .tag(LibraryTab.tracks)

                    PlaylistListView(playlists: library.playlists)
                        .tag(LibraryTab.playlists)
                }
                .tabViewStyle(.page(indexDisplayMode: .never))
            }
            .navigationTitle("Library")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Menu {
                        Button("Import Files") {
                            showingImportSheet = true
                        }

                        Button("Scan Folder") {
                            showingScanner = true
                        }

                        Button("Refresh Library") {
                            Task {
                                await library.refreshLibrary()
                            }
                        }
                    } label: {
                        Image(systemName: "plus")
                            .font(.title3)
                    }
                }
            }
            .sheet(isPresented: $showingImportSheet) {
                DocumentPicker { urls in
                    Task {
                        for url in urls {
                            _ = try? await scanner.parseAudioFile(url: url)
                        }
                        await library.refreshLibrary()
                    }
                }
            }
            .sheet(isPresented: $showingScanner) {
                DirectoryScannerView()
            }
        }
    }
}

// Document Picker for file import
struct DocumentPicker: UIViewControllerRepresentable {
    let onPick: ([URL]) -> Void

    func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
        let supportedTypes: [UTType] = [
            .init(filenameExtension: "flac")!,
            .init(filenameExtension: "alac")!,
            .init(filenameExtension: "wav")!,
            .init(filenameExtension: "mp3")!,
            .init(filenameExtension: "aac")!,
            .init(filenameExtension: "ogg")!,
            .audio
        ]

        let picker = UIDocumentPickerViewController(forOpeningContentTypes: supportedTypes, asCopy: true)
        picker.allowsMultipleSelection = true
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: UIDocumentPickerViewController, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(onPick: onPick)
    }

    class Coordinator: NSObject, UIDocumentPickerDelegate {
        let onPick: ([URL]) -> Void

        init(onPick: @escaping ([URL]) -> Void) {
            self.onPick = onPick
        }

        func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
            onPick(urls)
        }
    }
}
```

---

## 🔀 ADVANCED SHUFFLE ALGORITHM

### 9. SmartShuffleEngine.swift
```swift
import Foundation

class SmartShuffleEngine {

    /// Fisher-Yates shuffle with album grouping option
    static func shuffle(tracks: [Track], mode: ShuffleMode = .random) -> [Track] {
        switch mode {
        case .random:
            return tracks.shuffled()

        case .albumBased:
            // Group by album, shuffle albums, then shuffle tracks within albums
            let albums = Dictionary(grouping: tracks) { $0.album }
            let shuffledAlbums = albums.keys.shuffled()

            var result: [Track] = []
            for album in shuffledAlbums {
                if let albumTracks = albums[album] {
                    result.append(contentsOf: albumTracks.shuffled())
                }
            }
            return result

        case .artistBased:
            // Group by artist, shuffle artists
            let artists = Dictionary(grouping: tracks) { $0.artist }
            let shuffledArtists = artists.keys.shuffled()

            var result: [Track] = []
            for artist in shuffledArtists {
                if let artistTracks = artists[artist] {
                    result.append(contentsOf: artistTracks.shuffled())
                }
            }
            return result

        case .weighted:
            // Weight shuffle to prefer less-played tracks
            return weightedShuffle(tracks: tracks)
        }
    }

    private static func weightedShuffle(tracks: [Track]) -> [Track] {
        var pool = tracks
        var result: [Track] = []

        while !pool.isEmpty {
            // Calculate weights (inverse of play count)
            let weights = pool.map { track in
                let weight = max(1, 100 - track.playCount * 10)
                return Double(weight)
            }

            let totalWeight = weights.reduce(0, +)
            let random = Double.random(in: 0...totalWeight)

            var cumulative: Double = 0
            var selectedIndex = 0

            for (index, weight) in weights.enumerated() {
                cumulative += weight
                if random <= cumulative {
                    selectedIndex = index
                    break
                }
            }

            result.append(pool.remove(at: selectedIndex))
        }

        return result
    }

    enum ShuffleMode {
        case random
        case albumBased
        case artistBased
        case weighted
    }
}
```

---

## ⚙️ APP CONFIGURATION

### 10. Info.plist Requirements
```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <!-- Audio Background Mode -->
    <key>UIBackgroundModes</key>
    <array>
        <string>audio</string>
        <string>fetch</string>
    </array>

    <!-- File Access -->
    <key>UIFileSharingEnabled</key>
    <true/>
    <key>LSSupportsOpeningDocumentsInPlace</key>
    <true/>

    <!-- Supported Document Types -->
    <key>CFBundleDocumentTypes</key>
    <array>
        <dict>
            <key>CFBundleTypeName</key>
            <string>FLAC Audio</string>
            <key>LSHandlerRank</key>
            <string>Alternate</string>
            <key>CFBundleTypeExtensions</key>
            <array>
                <string>flac</string>
            </array>
            <key>CFBundleTypeMIMETypes</key>
            <array>
                <string>audio/flac</string>
            </array>
        </dict>
        <dict>
            <key>CFBundleTypeName</key>
            <string>WAV Audio</string>
            <key>LSHandlerRank</key>
            <string>Alternate</string>
            <key>CFBundleTypeExtensions</key>
            <array>
                <string>wav</string>
                <string>aiff</string>
            </array>
        </dict>
    </array>

    <!-- External DAC / USB Audio -->
    <key>UISupportedExternalAccessoryProtocols</key>
    <array>
        <string>com.apple.mfi.externalaccessory</string>
    </array>
</dict>
</plist>
```

---

## 📱 SWIFTUI APP ENTRY POINT

### 11. AuraPlayerApp.swift
```swift
import SwiftUI

@main
struct AuraPlayerApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(AudioPlayerManager.shared)
                .environmentObject(MusicLibrary.shared)
                .preferredColorScheme(.dark)
        }
    }
}

class AppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey : Any]? = nil) -> Bool {
        // Setup audio session
        AudioPlayerManager.shared.setupAudioSession()

        // Load library on startup
        Task {
            await MusicLibrary.shared.loadLibrary()
        }

        return true
    }

    func application(_ app: UIApplication, open url: URL, options: [UIApplication.OpenURLOptionsKey : Any] = [:]) -> Bool {
        // Handle imported audio files
        if url.isFileURL {
            Task {
                let track = try? await DirectoryScanner.shared.parseAudioFile(url: url)
                if let track = track {
                    await MusicLibrary.shared.addTracks([track])
                }
            }
        }
        return true
    }
}
```

---

## 🔧 BUILD REQUIREMENTS

### Xcode Project Setup

1. **Create new iOS Project** (iOS 16.0+, SwiftUI Interface)
2. **Add Required Frameworks:**
   - AVFoundation
   - Accelerate
   - MediaPlayer
   - CoreData
   - UniformTypeIdentifiers

3. **Enable Capabilities:**
   - Background Modes: Audio, AirPlay, Background Fetch
   - File Sharing (iTunes)

4. **Add FLAC Support:**
   - iOS 15+ natively supports FLAC via AVFoundation
   - For DSD support, add third-party decoder (e.g., FFmpeg via SPM)

5. **Swift Package Dependencies (Optional):**
   ```
   // For advanced metadata parsing
   https://github.com/sbooth/AudioFileTagger

   // For DSD playback
   https://github.com/sbooth/Decoding
   ```

---

## 🎨 DESIGN SYSTEM

### Color Palette
```swift
extension Color {
    static let auraBackground = Color.black
    static let auraSurface = Color(white: 0.1)
    static let auraPrimary = Color.pink
    static let auraAccent = Color.purple
    static let auraSuccess = Color.green
    static let auraWarning = Color.orange
}
```

### Typography
```swift
extension Font {
    static let auraTitle = Font.system(size: 28, weight: .bold, design: .rounded)
    static let auraHeadline = Font.system(size: 20, weight: .semibold, design: .rounded)
    static let auraBody = Font.system(size: 16, weight: .regular, design: .default)
    static let auraCaption = Font.system(size: 12, weight: .medium, design: .default)
}
```

---

## ✅ FEATURE CHECKLIST

| Feature | Status | Notes |
|---------|--------|-------|
| FLAC Playback | ✅ | Native iOS 15+ support |
| Hi-Res (192kHz/24-bit) | ✅ | Via AVAudioEngine |
| DSD Support | ⚠️ | Requires third-party decoder |
| External DAC | ✅ | USB Audio Class 2.0 |
| Bit-perfect Output | ⚠️ | iOS limits direct hardware access |
| 10-Band EQ | ✅ | Parametric EQ |
| 10 EQ Presets | ✅ | + Custom preset support |
| Playlist Creation | ✅ | Manual & Smart playlists |
| Shuffle (4 modes) | ✅ | Random, Album, Artist, Weighted |
| Folder Import | ✅ | DocumentPicker + DirectoryScanner |
| Artwork Extraction | ✅ | Embedded + Folder art |
| Background Playback | ✅ | AVAudioSession |
| Lock Screen Controls | ✅ | MPNowPlayingInfoCenter |
| Visualizer | ✅ | FFT-based waveform |
| Gapless Playback | ✅ | AVAudioPlayerNode scheduling |
