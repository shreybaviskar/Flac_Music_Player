//
//  QueueManager.swift
//  AuraPlayer
//
//  Manages the playback queue, shuffle modes (Fisher-Yates, album-based,
//  artist-based, weighted), repeat modes, and track navigation.
//
//  Integrates with PlaybackController via callbacks — the QueueManager
//  decides WHAT to play, the PlaybackController handles HOW to play it.
//

import Foundation
import Combine

// MARK: - Shuffle Mode

/// The 4 shuffle algorithms supported by the queue.
enum ShuffleMode: String, CaseIterable, Identifiable {
    /// Standard Fisher-Yates permutation — true random, zero repetition.
    case random = "Random"
    
    /// Shuffle albums, then play each album's tracks in order.
    case albumBased = "Album Shuffle"
    
    /// Shuffle artists, then shuffle tracks within each artist.
    case artistBased = "Artist Shuffle"
    
    /// Weighted random — less-played tracks are more likely to be picked.
    case weighted = "Smart Shuffle"
    
    var id: String { rawValue }
    
    var iconName: String {
        switch self {
        case .random:      return "shuffle"
        case .albumBased:  return "square.stack"
        case .artistBased: return "person.2"
        case .weighted:    return "brain"
        }
    }
}

// MARK: - QueueManager

/// Owns the playback queue and all sequencing logic.
///
/// The QueueManager is the single source of truth for:
/// - The current queue of tracks (original and shuffled)
/// - The current playback index
/// - Shuffle state and algorithm
/// - Repeat mode
/// - Navigation history (for accurate "previous" in shuffle mode)
///
/// It does NOT own audio playback — it tells `PlaybackController` what
/// track to play via the `onPlayTrack` callback.
@MainActor
final class QueueManager: ObservableObject {
    
    static let shared = QueueManager()
    
    // MARK: - Published State
    
    /// The queue as the user sees it (may be shuffled).
    @Published private(set) var queue: [Track] = []
    
    /// Index of the currently playing track within `queue`.
    @Published private(set) var currentIndex: Int = 0
    
    /// Whether shuffle is enabled.
    @Published var isShuffleEnabled: Bool = false {
        didSet { handleShuffleToggle() }
    }
    
    /// The active shuffle algorithm.
    @Published var shuffleMode: ShuffleMode = .random
    
    /// The active repeat mode.
    @Published var repeatMode: RepeatMode = .off
    
    /// The currently playing track (derived from queue + index).
    @Published private(set) var currentTrack: Track?
    
    /// Whether the queue has a next track available.
    @Published private(set) var hasNext: Bool = false
    
    /// Whether the queue has a previous track available.
    @Published private(set) var hasPrevious: Bool = false
    
    // MARK: - Original Queue
    
    /// The unshuffled queue — preserved so we can restore order when shuffle is toggled off.
    private var originalQueue: [Track] = []
    
    /// The original index of the current track in `originalQueue`.
    private var originalIndex: Int = 0
    
    // MARK: - Navigation History
    
    /// History stack for shuffle mode — allows accurate "previous" navigation
    /// without repeating the Fisher-Yates sequence backwards.
    private var navigationHistory: [Int] = []
    
    /// Maximum history depth.
    private let maxHistoryDepth = 200
    
    // MARK: - Callbacks
    
    /// Called when the QueueManager wants to play a specific track.
    /// The PlaybackController listens to this.
    var onPlayTrack: ((Track) -> Void)?
    
    /// Called when the queue becomes empty or playback should stop.
    var onQueueExhausted: (() -> Void)?
    
    // MARK: - Combine
    
    private var cancellables = Set<AnyCancellable>()
    
    // MARK: - Init
    
    private init() {
        // Avoid touching PlaybackController.shared during singleton initialization.
        // PlaybackController establishes queue callbacks on its side.
    }
    
    // MARK: - Queue Loading
    
    /// Loads a new queue and starts playing from a specific index.
    ///
    /// - Parameters:
    ///   - tracks: The tracks to queue (in their natural order).
    ///   - startIndex: The index to start playing from.
    func loadQueue(tracks: [Track], startIndex: Int = 0) {
        guard !tracks.isEmpty else { return }
        
        let safeIndex = max(0, min(startIndex, tracks.count - 1))
        
        originalQueue = tracks
        originalIndex = safeIndex
        navigationHistory = []
        
        if isShuffleEnabled {
            // Shuffle but keep the selected track first.
            let selectedTrack = tracks[safeIndex]
            queue = shuffleTracks(tracks, preserving: selectedTrack)
            currentIndex = 0
        } else {
            queue = tracks
            currentIndex = safeIndex
        }
        
        updateDerivedState()
        playCurrentTrack()
    }
    
    /// Appends tracks to the end of the current queue.
    func appendToQueue(tracks: [Track]) {
        originalQueue.append(contentsOf: tracks)
        queue.append(contentsOf: tracks)
        updateDerivedState()
    }
    
    /// Inserts a track to play next (after the current track).
    func playNext(track: Track) {
        let insertIndex = currentIndex + 1
        queue.insert(track, at: min(insertIndex, queue.count))
        originalQueue.append(track)
        updateDerivedState()
    }
    
    /// Adds a track to the end of the queue ("Play Later").
    func playLater(track: Track) {
        queue.append(track)
        originalQueue.append(track)
        updateDerivedState()
    }
    
    /// Removes a track from the queue by index.
    func removeFromQueue(at index: Int) {
        guard index >= 0, index < queue.count else { return }
        
        let removedTrack = queue.remove(at: index)
        originalQueue.removeAll { $0.id == removedTrack.id }
        
        // Adjust current index if needed.
        if index < currentIndex {
            currentIndex -= 1
        } else if index == currentIndex {
            // Current track was removed — play the next one.
            currentIndex = min(currentIndex, queue.count - 1)
            if !queue.isEmpty {
                playCurrentTrack()
            } else {
                onQueueExhausted?()
            }
        }
        
        updateDerivedState()
    }
    
    /// Moves a track within the queue (for drag-to-reorder).
    func moveTrack(from source: IndexSet, to destination: Int) {
        queue.move(fromOffsets: source, toOffset: destination)
        
        // Recalculate current index.
        if let currentTrack {
            currentIndex = queue.firstIndex(where: { $0.id == currentTrack.id }) ?? 0
        }
        
        updateDerivedState()
    }
    
    /// Clears the queue and stops playback.
    func clearQueue() {
        queue = []
        originalQueue = []
        currentIndex = 0
        navigationHistory = []
        currentTrack = nil
        updateDerivedState()
        onQueueExhausted?()
    }
    
    // MARK: - Navigation
    
    /// Advances to the next track.
    func advanceToNext() {
        guard !queue.isEmpty else {
            onQueueExhausted?()
            return
        }
        
        // Repeat One: replay the same track.
        if repeatMode == .one {
            playCurrentTrack()
            return
        }
        
        // Push current index to history.
        pushHistory(currentIndex)
        
        let nextIndex = currentIndex + 1
        
        if nextIndex < queue.count {
            // Normal advance.
            currentIndex = nextIndex
            playCurrentTrack()
        } else {
            // End of queue.
            if repeatMode == .all {
                // Repeat All: wrap to start. Re-shuffle if enabled.
                if isShuffleEnabled {
                    let current = queue[currentIndex]
                    queue = shuffleTracks(queue, preserving: nil)
                    currentIndex = 0
                    // Avoid repeating the last track as the first of the new shuffle.
                    if queue.first?.id == current.id, queue.count > 1 {
                        queue.swapAt(0, 1)
                    }
                } else {
                    currentIndex = 0
                }
                playCurrentTrack()
            } else {
                // Repeat Off: stop.
                onQueueExhausted?()
            }
        }
    }
    
    /// Goes back to the previous track.
    ///
    /// Behavior:
    /// - If current time > 3 seconds, restart the current track.
    /// - If in shuffle mode, pop from navigation history.
    /// - Otherwise, go to the previous index.
    func goToPrevious() {
        // If we're more than 3 seconds in, restart the current track.
        if PlaybackController.shared.currentTime > 3 {
            PlaybackController.shared.seek(to: 0)
            return
        }
        
        if isShuffleEnabled, let previousIndex = popHistory() {
            // Shuffle: go back through history.
            currentIndex = previousIndex
        } else {
            // Linear: go to previous index.
            if currentIndex > 0 {
                currentIndex -= 1
            } else if repeatMode == .all {
                currentIndex = queue.count - 1
            } else {
                // At the beginning with no repeat — restart current.
                PlaybackController.shared.seek(to: 0)
                return
            }
        }
        
        playCurrentTrack()
    }
    
    /// Jumps to a specific index in the queue.
    func jumpToIndex(_ index: Int) {
        guard index >= 0, index < queue.count else { return }
        pushHistory(currentIndex)
        currentIndex = index
        playCurrentTrack()
    }
    
    /// Jumps to a specific track in the queue.
    func jumpToTrack(_ track: Track) {
        if let index = queue.firstIndex(where: { $0.id == track.id }) {
            jumpToIndex(index)
        }
    }
    
    // MARK: - Repeat Mode
    
    /// Cycles through repeat modes: off → all → one → off.
    func cycleRepeatMode() {
        switch repeatMode {
        case .off:  repeatMode = .all
        case .all:  repeatMode = .one
        case .one:  repeatMode = .off
        }
    }
    
    var repeatModeIcon: String {
        switch repeatMode {
        case .off:  return "repeat"
        case .all:  return "repeat"
        case .one:  return "repeat.1"
        }
    }
    
    var isRepeatActive: Bool {
        repeatMode != .off
    }
    
    // MARK: - Shuffle Toggle
    
    private func handleShuffleToggle() {
        guard !queue.isEmpty, let current = currentTrack else { return }
        
        if isShuffleEnabled {
            // Shuffle: preserve the current track at position 0.
            queue = shuffleTracks(queue, preserving: current)
            currentIndex = 0
            navigationHistory = [0]
        } else {
            // Unshuffle: restore original order, find current track.
            queue = originalQueue
            currentIndex = originalQueue.firstIndex(where: { $0.id == current.id }) ?? 0
            navigationHistory = []
        }
        
        updateDerivedState()
    }
    
    // MARK: - Shuffle Algorithms
    
    /// Shuffles tracks using the currently selected shuffle mode.
    ///
    /// - Parameters:
    ///   - tracks: The tracks to shuffle.
    ///   - preservedTrack: If provided, this track will be placed at index 0.
    /// - Returns: The shuffled array.
    private func shuffleTracks(_ tracks: [Track], preserving preservedTrack: Track?) -> [Track] {
        switch shuffleMode {
        case .random:
            return fisherYatesShuffle(tracks, preserving: preservedTrack)
        case .albumBased:
            return albumBasedShuffle(tracks, preserving: preservedTrack)
        case .artistBased:
            return artistBasedShuffle(tracks, preserving: preservedTrack)
        case .weighted:
            return weightedShuffle(tracks, preserving: preservedTrack)
        }
    }
    
    /// **Fisher-Yates** (Knuth) shuffle — O(n), guaranteed uniform distribution,
    /// every permutation equally likely, zero repetition.
    ///
    /// This is the gold standard for unbiased shuffling.
    private func fisherYatesShuffle(_ tracks: [Track], preserving preservedTrack: Track?) -> [Track] {
        var array = tracks
        
        // Classic Fisher-Yates: iterate from the end, swap each element
        // with a randomly chosen element from the unshuffled portion.
        for i in stride(from: array.count - 1, through: 1, by: -1) {
            let j = Int.random(in: 0...i)
            if i != j {
                array.swapAt(i, j)
            }
        }
        
        // Move the preserved track to index 0 if specified.
        if let preserved = preservedTrack,
           let idx = array.firstIndex(where: { $0.id == preserved.id }), idx != 0 {
            array.swapAt(0, idx)
        }
        
        return array
    }
    
    /// **Album-based shuffle**: Shuffle the order of albums, then play each
    /// album's tracks in their natural (disc/track number) order.
    ///
    /// This preserves the artistic flow within albums while randomizing
    /// which album comes next.
    private func albumBasedShuffle(_ tracks: [Track], preserving preservedTrack: Track?) -> [Track] {
        // Group by album title.
        let albumGroups = Dictionary(grouping: tracks) { $0.albumTitle }
        
        // Shuffle the album order using Fisher-Yates.
        var albumKeys = Array(albumGroups.keys)
        for i in stride(from: albumKeys.count - 1, through: 1, by: -1) {
            let j = Int.random(in: 0...i)
            if i != j { albumKeys.swapAt(i, j) }
        }
        
        // Build the result: albums in shuffled order, tracks sorted within each.
        var result: [Track] = []
        for key in albumKeys {
            if let albumTracks = albumGroups[key] {
                let sorted = albumTracks.sorted { lhs, rhs in
                    let ld = lhs.discNumber ?? 1, rd = rhs.discNumber ?? 1
                    if ld != rd { return ld < rd }
                    let lt = lhs.trackNumber ?? 0, rt = rhs.trackNumber ?? 0
                    return lt < rt
                }
                result.append(contentsOf: sorted)
            }
        }
        
        // Move the preserved track's album to the front.
        if let preserved = preservedTrack {
            let preservedAlbum = preserved.albumTitle
            let albumTracks = result.filter { $0.albumTitle == preservedAlbum }
            let otherTracks = result.filter { $0.albumTitle != preservedAlbum }
            result = albumTracks + otherTracks
        }
        
        return result
    }
    
    /// **Artist-based shuffle**: Shuffle the order of artists, then shuffle
    /// tracks within each artist.
    private func artistBasedShuffle(_ tracks: [Track], preserving preservedTrack: Track?) -> [Track] {
        // Group by artist.
        let artistGroups = Dictionary(grouping: tracks) { $0.artistName }
        
        // Shuffle artist order.
        var artistKeys = Array(artistGroups.keys)
        for i in stride(from: artistKeys.count - 1, through: 1, by: -1) {
            let j = Int.random(in: 0...i)
            if i != j { artistKeys.swapAt(i, j) }
        }
        
        // Build result: artists shuffled, tracks within each artist shuffled.
        var result: [Track] = []
        for key in artistKeys {
            if var artistTracks = artistGroups[key] {
                // Fisher-Yates shuffle within artist.
                for i in stride(from: artistTracks.count - 1, through: 1, by: -1) {
                    let j = Int.random(in: 0...i)
                    if i != j { artistTracks.swapAt(i, j) }
                }
                result.append(contentsOf: artistTracks)
            }
        }
        
        // Move preserved track to front.
        if let preserved = preservedTrack,
           let idx = result.firstIndex(where: { $0.id == preserved.id }), idx != 0 {
            result.swapAt(0, idx)
        }
        
        return result
    }
    
    /// **Weighted shuffle**: Tracks with fewer plays get higher probability.
    /// Uses inverse play count weighting with reservoir-style selection.
    ///
    /// This creates a "discovery" mode that surfaces less-played tracks
    /// without completely excluding frequently-played ones.
    private func weightedShuffle(_ tracks: [Track], preserving preservedTrack: Track?) -> [Track] {
        var pool = tracks
        var result: [Track] = []
        
        while !pool.isEmpty {
            // Calculate weights: inverse of play count, with a floor of 1.
            let weights = pool.map { track -> Double in
                Double(max(1, 100 - track.playCount * 10))
            }
            
            let totalWeight = weights.reduce(0, +)
            let randomValue = Double.random(in: 0..<totalWeight)
            
            // Weighted random selection.
            var cumulative: Double = 0
            var selectedIndex = 0
            
            for (index, weight) in weights.enumerated() {
                cumulative += weight
                if randomValue < cumulative {
                    selectedIndex = index
                    break
                }
            }
            
            result.append(pool.remove(at: selectedIndex))
        }
        
        // Move preserved track to front.
        if let preserved = preservedTrack,
           let idx = result.firstIndex(where: { $0.id == preserved.id }), idx != 0 {
            result.swapAt(0, idx)
        }
        
        return result
    }
    
    // MARK: - History Stack
    
    private func pushHistory(_ index: Int) {
        navigationHistory.append(index)
        if navigationHistory.count > maxHistoryDepth {
            navigationHistory.removeFirst()
        }
    }
    
    private func popHistory() -> Int? {
        navigationHistory.popLast()
    }
    
    // MARK: - Private Helpers
    
    private func playCurrentTrack() {
        guard currentIndex >= 0, currentIndex < queue.count else {
            onQueueExhausted?()
            return
        }
        
        let track = queue[currentIndex]
        currentTrack = track
        updateDerivedState()
        onPlayTrack?(track)
    }
    
    private func updateDerivedState() {
        if queue.isEmpty {
            hasNext = false
            hasPrevious = false
            currentTrack = nil
            return
        }
        
        currentTrack = (currentIndex >= 0 && currentIndex < queue.count) ? queue[currentIndex] : nil
        
        hasNext = currentIndex < queue.count - 1 || repeatMode == .all
        hasPrevious = currentIndex > 0 || repeatMode == .all || !navigationHistory.isEmpty
    }
    
    // MARK: - Queue Info (for UI)
    
    /// Tracks remaining after the current track.
    var upcomingTracks: [Track] {
        guard currentIndex + 1 < queue.count else { return [] }
        return Array(queue[(currentIndex + 1)...])
    }
    
    /// Number of tracks in the queue.
    var trackCount: Int { queue.count }
    
    /// Total duration of the remaining queue.
    var remainingDuration: TimeInterval {
        upcomingTracks.reduce(0) { $0 + $1.duration }
    }
    
    /// Formatted remaining duration.
    var formattedRemainingDuration: String {
        let totalMinutes = Int(remainingDuration) / 60
        if totalMinutes >= 60 {
            return "\(totalMinutes / 60) hr \(totalMinutes % 60) min"
        }
        return "\(totalMinutes) min"
    }
}
