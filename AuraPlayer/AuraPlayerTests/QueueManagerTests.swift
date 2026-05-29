//
//  QueueManagerTests.swift
//  AuraPlayerTests
//
//  Tests for QueueManager — the singleton that owns the playback queue,
//  shuffle algorithms, repeat modes, and track navigation.
//
//  Because QueueManager is a @MainActor singleton with a private init,
//  all tests operate on `QueueManager.shared` directly. State is reset
//  in setUp() via clearQueue() and callback overrides to prevent
//  real PlaybackController interaction.
//

import XCTest
@testable import AuraPlayer

final class QueueManagerTests: XCTestCase {
    
    // MARK: - Properties
    
    private var sut: QueueManager!
    
    /// Tracks captured by the overridden `onPlayTrack` callback.
    private var playedTracks: [Track] = []
    
    /// Whether `onQueueExhausted` was called.
    private var queueExhaustedCalled = false
    
    // MARK: - Test Helpers
    
    /// Creates a simple Track for testing without needing a ModelContainer.
    /// Track is a @Model class but its stored properties can be set directly.
    private func makeTrack(
        title: String,
        artist: String = "Artist",
        album: String = "Album",
        duration: TimeInterval = 180,
        trackNumber: Int? = nil,
        discNumber: Int? = nil,
        playCount: Int = 0
    ) -> Track {
        Track(
            filePath: "/test/\(title).flac",
            fileExtension: "flac",
            title: title,
            artistName: artist,
            albumTitle: album,
            trackNumber: trackNumber,
            discNumber: discNumber,
            duration: duration,
            sampleRate: 44100,
            bitDepth: 16,
            channelCount: 2,
            codec: .flac,
            playCount: playCount
        )
    }
    
    /// Creates an array of N tracks with sequential titles.
    private func makeTracks(count: Int, artist: String = "Artist", album: String = "Album") -> [Track] {
        (1...count).map { i in
            makeTrack(title: "Track \(i)", artist: artist, album: album, duration: TimeInterval(i * 60))
        }
    }
    
    // MARK: - setUp / tearDown
    
    @MainActor
    override func setUp() async throws {
        try await super.setUp()
        
        sut = QueueManager.shared
        playedTracks = []
        queueExhaustedCalled = false
        
        // Reset the shared singleton to a clean state.
        sut.clearQueue()
        sut.isShuffleEnabled = false
        sut.shuffleMode = .random
        sut.repeatMode = .off
        
        // Override callbacks to avoid hitting the real PlaybackController.
        sut.onPlayTrack = { [weak self] track in
            self?.playedTracks.append(track)
        }
        sut.onQueueExhausted = { [weak self] in
            self?.queueExhaustedCalled = true
        }
    }
    
    @MainActor
    override func tearDown() async throws {
        sut.clearQueue()
        sut.onPlayTrack = nil
        sut.onQueueExhausted = nil
        sut = nil
        try await super.tearDown()
    }
    
    // MARK: - loadQueue Tests
    
    @MainActor
    func test_loadQueue_withTracks_setsQueueAndCurrentTrack() async {
        let tracks = makeTracks(count: 5)
        
        sut.loadQueue(tracks: tracks, startIndex: 0)
        
        XCTAssertEqual(sut.queue.count, 5)
        XCTAssertEqual(sut.currentIndex, 0)
        XCTAssertEqual(sut.currentTrack?.title, "Track 1")
        XCTAssertEqual(playedTracks.count, 1)
        XCTAssertEqual(playedTracks.first?.title, "Track 1")
    }
    
    @MainActor
    func test_loadQueue_withStartIndex_playsCorrectTrack() async {
        let tracks = makeTracks(count: 5)
        
        sut.loadQueue(tracks: tracks, startIndex: 2)
        
        XCTAssertEqual(sut.currentIndex, 2)
        XCTAssertEqual(sut.currentTrack?.title, "Track 3")
        XCTAssertEqual(playedTracks.first?.title, "Track 3")
    }
    
    @MainActor
    func test_loadQueue_emptyArray_doesNothing() async {
        // Load some initial data
        let tracks = makeTracks(count: 3)
        sut.loadQueue(tracks: tracks)
        
        let previousTrack = sut.currentTrack
        let previousCount = sut.queue.count
        
        // Attempt to load empty
        sut.loadQueue(tracks: [])
        
        // State should be unchanged
        XCTAssertEqual(sut.queue.count, previousCount)
        XCTAssertEqual(sut.currentTrack?.id, previousTrack?.id)
    }
    
    @MainActor
    func test_loadQueue_startIndexBeyondBounds_clampsToLastTrack() async {
        let tracks = makeTracks(count: 3)
        
        sut.loadQueue(tracks: tracks, startIndex: 100)
        
        // Should clamp to tracks.count - 1 = 2
        XCTAssertEqual(sut.currentIndex, 2)
        XCTAssertEqual(sut.currentTrack?.title, "Track 3")
    }
    
    @MainActor
    func test_loadQueue_negativeStartIndex_clampsToZero() async {
        let tracks = makeTracks(count: 3)
        
        sut.loadQueue(tracks: tracks, startIndex: -5)
        
        XCTAssertEqual(sut.currentIndex, 0)
        XCTAssertEqual(sut.currentTrack?.title, "Track 1")
    }
    
    @MainActor
    func test_loadQueue_setsHasNextAndHasPrevious() async {
        let tracks = makeTracks(count: 3)
        
        sut.loadQueue(tracks: tracks, startIndex: 1)
        
        XCTAssertTrue(sut.hasNext, "Middle track should have next")
        XCTAssertTrue(sut.hasPrevious, "Middle track should have previous")
    }
    
    @MainActor
    func test_loadQueue_atStart_hasNextButNotPrevious() async {
        let tracks = makeTracks(count: 3)
        sut.repeatMode = .off
        
        sut.loadQueue(tracks: tracks, startIndex: 0)
        
        XCTAssertTrue(sut.hasNext)
        XCTAssertFalse(sut.hasPrevious)
    }
    
    @MainActor
    func test_loadQueue_atEnd_hasPreviousButNotNext() async {
        let tracks = makeTracks(count: 3)
        sut.repeatMode = .off
        
        sut.loadQueue(tracks: tracks, startIndex: 2)
        
        XCTAssertFalse(sut.hasNext)
        XCTAssertTrue(sut.hasPrevious)
    }
    
    @MainActor
    func test_loadQueue_singleTrack_noNextNoPrevious() async {
        let tracks = makeTracks(count: 1)
        sut.repeatMode = .off
        
        sut.loadQueue(tracks: tracks)
        
        XCTAssertFalse(sut.hasNext)
        XCTAssertFalse(sut.hasPrevious)
    }
    
    // MARK: - appendToQueue Tests
    
    @MainActor
    func test_appendToQueue_addsTracksToEnd() async {
        let initial = makeTracks(count: 2)
        sut.loadQueue(tracks: initial)
        
        let additional = [makeTrack(title: "Extra 1"), makeTrack(title: "Extra 2")]
        sut.appendToQueue(tracks: additional)
        
        XCTAssertEqual(sut.queue.count, 4)
        XCTAssertEqual(sut.queue[2].title, "Extra 1")
        XCTAssertEqual(sut.queue[3].title, "Extra 2")
    }
    
    @MainActor
    func test_appendToQueue_doesNotChangeCurrentTrack() async {
        let initial = makeTracks(count: 2)
        sut.loadQueue(tracks: initial)
        let currentBefore = sut.currentTrack
        
        sut.appendToQueue(tracks: [makeTrack(title: "Extra")])
        
        XCTAssertEqual(sut.currentTrack?.id, currentBefore?.id)
        XCTAssertEqual(sut.currentIndex, 0)
    }
    
    // MARK: - playNext Tests
    
    @MainActor
    func test_playNext_insertsAfterCurrentTrack() async {
        let tracks = makeTracks(count: 3)
        sut.loadQueue(tracks: tracks) // currentIndex = 0
        
        let nextTrack = makeTrack(title: "Play Next Track")
        sut.playNext(track: nextTrack)
        
        XCTAssertEqual(sut.queue.count, 4)
        XCTAssertEqual(sut.queue[1].title, "Play Next Track")
        // Original track 2 should now be at index 2
        XCTAssertEqual(sut.queue[2].title, "Track 2")
    }
    
    @MainActor
    func test_playNext_whenAtLastIndex_insertsAtEnd() async {
        let tracks = makeTracks(count: 2)
        sut.loadQueue(tracks: tracks, startIndex: 1) // currentIndex = 1
        
        let nextTrack = makeTrack(title: "Play Next Track")
        sut.playNext(track: nextTrack)
        
        XCTAssertEqual(sut.queue.count, 3)
        XCTAssertEqual(sut.queue[2].title, "Play Next Track")
    }
    
    // MARK: - playLater Tests
    
    @MainActor
    func test_playLater_appendsToEnd() async {
        let tracks = makeTracks(count: 2)
        sut.loadQueue(tracks: tracks)
        
        let laterTrack = makeTrack(title: "Later Track")
        sut.playLater(track: laterTrack)
        
        XCTAssertEqual(sut.queue.count, 3)
        XCTAssertEqual(sut.queue.last?.title, "Later Track")
    }
    
    // MARK: - removeFromQueue Tests
    
    @MainActor
    func test_removeFromQueue_removesTrackAtIndex() async {
        let tracks = makeTracks(count: 3)
        sut.loadQueue(tracks: tracks)
        
        sut.removeFromQueue(at: 1)
        
        XCTAssertEqual(sut.queue.count, 2)
        XCTAssertEqual(sut.queue[0].title, "Track 1")
        XCTAssertEqual(sut.queue[1].title, "Track 3")
    }
    
    @MainActor
    func test_removeFromQueue_beforeCurrentIndex_adjustsIndex() async {
        let tracks = makeTracks(count: 4)
        sut.loadQueue(tracks: tracks, startIndex: 2) // playing Track 3
        
        sut.removeFromQueue(at: 0) // remove Track 1 (before current)
        
        // currentIndex was 2, should now be 1
        XCTAssertEqual(sut.currentIndex, 1)
        XCTAssertEqual(sut.currentTrack?.title, "Track 3")
    }
    
    @MainActor
    func test_removeFromQueue_atCurrentIndex_playsNextTrack() async {
        let tracks = makeTracks(count: 3)
        sut.loadQueue(tracks: tracks, startIndex: 1) // playing Track 2
        playedTracks = [] // clear initial play
        
        sut.removeFromQueue(at: 1) // remove current track
        
        // Should play the track that is now at index 1
        XCTAssertEqual(sut.queue.count, 2)
        XCTAssertFalse(playedTracks.isEmpty, "Should trigger playback of next track")
    }
    
    @MainActor
    func test_removeFromQueue_invalidIndex_doesNothing() async {
        let tracks = makeTracks(count: 3)
        sut.loadQueue(tracks: tracks)
        
        sut.removeFromQueue(at: -1)
        XCTAssertEqual(sut.queue.count, 3)
        
        sut.removeFromQueue(at: 10)
        XCTAssertEqual(sut.queue.count, 3)
    }
    
    @MainActor
    func test_removeFromQueue_lastTrack_callsOnQueueExhausted() async {
        let tracks = makeTracks(count: 1)
        sut.loadQueue(tracks: tracks)
        queueExhaustedCalled = false
        
        sut.removeFromQueue(at: 0)
        
        XCTAssertTrue(sut.queue.isEmpty)
        XCTAssertTrue(queueExhaustedCalled)
    }
    
    // MARK: - clearQueue Tests
    
    @MainActor
    func test_clearQueue_emptiesEverything() async {
        let tracks = makeTracks(count: 5)
        sut.loadQueue(tracks: tracks, startIndex: 2)
        queueExhaustedCalled = false
        
        sut.clearQueue()
        
        XCTAssertTrue(sut.queue.isEmpty)
        XCTAssertEqual(sut.currentIndex, 0)
        XCTAssertNil(sut.currentTrack)
        XCTAssertFalse(sut.hasNext)
        XCTAssertFalse(sut.hasPrevious)
        XCTAssertTrue(queueExhaustedCalled)
    }
    
    // MARK: - advanceToNext Tests
    
    @MainActor
    func test_advanceToNext_incrementsIndexAndPlaysNext() async {
        let tracks = makeTracks(count: 3)
        sut.loadQueue(tracks: tracks) // starts at 0
        playedTracks = []
        
        sut.advanceToNext()
        
        XCTAssertEqual(sut.currentIndex, 1)
        XCTAssertEqual(sut.currentTrack?.title, "Track 2")
        XCTAssertEqual(playedTracks.count, 1)
        XCTAssertEqual(playedTracks.first?.title, "Track 2")
    }
    
    @MainActor
    func test_advanceToNext_atEndWithRepeatAll_wrapsToStart() async {
        let tracks = makeTracks(count: 3)
        sut.loadQueue(tracks: tracks, startIndex: 2) // at last track
        sut.repeatMode = .all
        playedTracks = []
        
        sut.advanceToNext()
        
        XCTAssertEqual(sut.currentIndex, 0)
        XCTAssertEqual(sut.currentTrack?.title, "Track 1")
    }
    
    @MainActor
    func test_advanceToNext_atEndWithRepeatOff_callsOnQueueExhausted() async {
        let tracks = makeTracks(count: 3)
        sut.loadQueue(tracks: tracks, startIndex: 2) // at last track
        sut.repeatMode = .off
        queueExhaustedCalled = false
        
        sut.advanceToNext()
        
        XCTAssertTrue(queueExhaustedCalled)
    }
    
    @MainActor
    func test_advanceToNext_withRepeatOne_replaysCurrentTrack() async {
        let tracks = makeTracks(count: 3)
        sut.loadQueue(tracks: tracks, startIndex: 1) // playing Track 2
        sut.repeatMode = .one
        playedTracks = []
        
        sut.advanceToNext()
        
        // Should replay the same track
        XCTAssertEqual(sut.currentIndex, 1)
        XCTAssertEqual(sut.currentTrack?.title, "Track 2")
        XCTAssertEqual(playedTracks.count, 1)
        XCTAssertEqual(playedTracks.first?.title, "Track 2")
    }
    
    @MainActor
    func test_advanceToNext_emptyQueue_callsOnQueueExhausted() async {
        queueExhaustedCalled = false
        
        sut.advanceToNext()
        
        XCTAssertTrue(queueExhaustedCalled)
    }
    
    @MainActor
    func test_advanceToNext_multipleAdvancements_traversesEntireQueue() async {
        let tracks = makeTracks(count: 4)
        sut.loadQueue(tracks: tracks) // starts at 0
        playedTracks = []
        
        sut.advanceToNext() // -> 1
        sut.advanceToNext() // -> 2
        sut.advanceToNext() // -> 3
        
        XCTAssertEqual(sut.currentIndex, 3)
        XCTAssertEqual(sut.currentTrack?.title, "Track 4")
        XCTAssertEqual(playedTracks.count, 3)
    }
    
    // MARK: - cycleRepeatMode Tests
    
    @MainActor
    func test_cycleRepeatMode_offToAllToOneToOff() async {
        sut.repeatMode = .off
        
        sut.cycleRepeatMode()
        XCTAssertEqual(sut.repeatMode, .all)
        
        sut.cycleRepeatMode()
        XCTAssertEqual(sut.repeatMode, .one)
        
        sut.cycleRepeatMode()
        XCTAssertEqual(sut.repeatMode, .off)
    }
    
    @MainActor
    func test_cycleRepeatMode_fullCycleReturnsToOriginal() async {
        sut.repeatMode = .off
        
        sut.cycleRepeatMode() // .all
        sut.cycleRepeatMode() // .one
        sut.cycleRepeatMode() // .off
        
        XCTAssertEqual(sut.repeatMode, .off)
    }
    
    // MARK: - jumpToIndex Tests
    
    @MainActor
    func test_jumpToIndex_validIndex_jumpsAndPlays() async {
        let tracks = makeTracks(count: 5)
        sut.loadQueue(tracks: tracks) // starts at 0
        playedTracks = []
        
        sut.jumpToIndex(3)
        
        XCTAssertEqual(sut.currentIndex, 3)
        XCTAssertEqual(sut.currentTrack?.title, "Track 4")
        XCTAssertEqual(playedTracks.count, 1)
        XCTAssertEqual(playedTracks.first?.title, "Track 4")
    }
    
    @MainActor
    func test_jumpToIndex_invalidNegativeIndex_doesNothing() async {
        let tracks = makeTracks(count: 3)
        sut.loadQueue(tracks: tracks) // starts at 0
        playedTracks = []
        
        sut.jumpToIndex(-1)
        
        XCTAssertEqual(sut.currentIndex, 0)
        XCTAssertTrue(playedTracks.isEmpty)
    }
    
    @MainActor
    func test_jumpToIndex_indexBeyondBounds_doesNothing() async {
        let tracks = makeTracks(count: 3)
        sut.loadQueue(tracks: tracks) // starts at 0
        playedTracks = []
        
        sut.jumpToIndex(10)
        
        XCTAssertEqual(sut.currentIndex, 0)
        XCTAssertTrue(playedTracks.isEmpty)
    }
    
    // MARK: - jumpToTrack Tests
    
    @MainActor
    func test_jumpToTrack_existingTrack_jumpsToIt() async {
        let tracks = makeTracks(count: 5)
        sut.loadQueue(tracks: tracks)
        playedTracks = []
        
        let targetTrack = tracks[3]
        sut.jumpToTrack(targetTrack)
        
        XCTAssertEqual(sut.currentIndex, 3)
        XCTAssertEqual(sut.currentTrack?.id, targetTrack.id)
    }
    
    @MainActor
    func test_jumpToTrack_nonExistentTrack_doesNothing() async {
        let tracks = makeTracks(count: 3)
        sut.loadQueue(tracks: tracks)
        playedTracks = []
        
        let outsideTrack = makeTrack(title: "Not In Queue")
        sut.jumpToTrack(outsideTrack)
        
        XCTAssertEqual(sut.currentIndex, 0)
        XCTAssertTrue(playedTracks.isEmpty)
    }
    
    // MARK: - upcomingTracks Tests
    
    @MainActor
    func test_upcomingTracks_returnsTracksAfterCurrent() async {
        let tracks = makeTracks(count: 5)
        sut.loadQueue(tracks: tracks, startIndex: 1) // playing Track 2
        
        let upcoming = sut.upcomingTracks
        
        XCTAssertEqual(upcoming.count, 3)
        XCTAssertEqual(upcoming[0].title, "Track 3")
        XCTAssertEqual(upcoming[1].title, "Track 4")
        XCTAssertEqual(upcoming[2].title, "Track 5")
    }
    
    @MainActor
    func test_upcomingTracks_atLastTrack_returnsEmpty() async {
        let tracks = makeTracks(count: 3)
        sut.loadQueue(tracks: tracks, startIndex: 2)
        
        XCTAssertTrue(sut.upcomingTracks.isEmpty)
    }
    
    @MainActor
    func test_upcomingTracks_atFirstTrack_returnsAllExceptFirst() async {
        let tracks = makeTracks(count: 4)
        sut.loadQueue(tracks: tracks, startIndex: 0)
        
        XCTAssertEqual(sut.upcomingTracks.count, 3)
    }
    
    // MARK: - trackCount Tests
    
    @MainActor
    func test_trackCount_returnsCorrectCount() async {
        let tracks = makeTracks(count: 7)
        sut.loadQueue(tracks: tracks)
        
        XCTAssertEqual(sut.trackCount, 7)
    }
    
    @MainActor
    func test_trackCount_afterRemoval_returnsUpdatedCount() async {
        let tracks = makeTracks(count: 5)
        sut.loadQueue(tracks: tracks)
        
        sut.removeFromQueue(at: 2)
        
        XCTAssertEqual(sut.trackCount, 4)
    }
    
    @MainActor
    func test_trackCount_emptyQueue_returnsZero() async {
        XCTAssertEqual(sut.trackCount, 0)
    }
    
    // MARK: - remainingDuration Tests
    
    @MainActor
    func test_remainingDuration_calculatesCorrectly() async {
        // Track durations: 60, 120, 180, 240, 300
        let tracks = makeTracks(count: 5)
        sut.loadQueue(tracks: tracks, startIndex: 0)
        
        // Upcoming is tracks 2-5: 120 + 180 + 240 + 300 = 840
        XCTAssertEqual(sut.remainingDuration, 840, accuracy: 0.01)
    }
    
    @MainActor
    func test_remainingDuration_atLastTrack_isZero() async {
        let tracks = makeTracks(count: 3)
        sut.loadQueue(tracks: tracks, startIndex: 2)
        
        XCTAssertEqual(sut.remainingDuration, 0)
    }
    
    // MARK: - formattedRemainingDuration Tests
    
    @MainActor
    func test_formattedRemainingDuration_underOneHour_showsMinutes() async {
        // 3 upcoming tracks at 60s each = 180s = 3 min
        let tracks = [
            makeTrack(title: "T1", duration: 60),
            makeTrack(title: "T2", duration: 60),
            makeTrack(title: "T3", duration: 60),
            makeTrack(title: "T4", duration: 60)
        ]
        sut.loadQueue(tracks: tracks, startIndex: 0)
        
        // Upcoming = T2 + T3 + T4 = 180s = 3 min
        XCTAssertEqual(sut.formattedRemainingDuration, "3 min")
    }
    
    @MainActor
    func test_formattedRemainingDuration_overOneHour_showsHoursAndMinutes() async {
        // Create tracks with enough total duration to exceed 60 min
        let tracks = [
            makeTrack(title: "T1", duration: 60),
            makeTrack(title: "T2", duration: 3600), // 60 min
            makeTrack(title: "T3", duration: 1800)  // 30 min
        ]
        sut.loadQueue(tracks: tracks, startIndex: 0)
        
        // Upcoming = T2 + T3 = 5400s = 90 min = 1 hr 30 min
        XCTAssertEqual(sut.formattedRemainingDuration, "1 hr 30 min")
    }
    
    @MainActor
    func test_formattedRemainingDuration_noDuration_showsZeroMin() async {
        let tracks = [makeTrack(title: "T1", duration: 60)]
        sut.loadQueue(tracks: tracks, startIndex: 0)
        
        // No upcoming tracks
        XCTAssertEqual(sut.formattedRemainingDuration, "0 min")
    }
    
    // MARK: - Repeat Mode + hasNext/hasPrevious Interaction
    
    @MainActor
    func test_repeatAll_atEnd_hasNextIsTrue() async {
        let tracks = makeTracks(count: 3)
        sut.repeatMode = .all
        sut.loadQueue(tracks: tracks, startIndex: 2)
        
        XCTAssertTrue(sut.hasNext, "With repeat all, last track should show hasNext")
    }
    
    @MainActor
    func test_repeatAll_atStart_hasPreviousIsTrue() async {
        let tracks = makeTracks(count: 3)
        sut.repeatMode = .all
        sut.loadQueue(tracks: tracks, startIndex: 0)
        
        XCTAssertTrue(sut.hasPrevious, "With repeat all, first track should show hasPrevious")
    }
    
    // MARK: - moveTrack Tests
    
    @MainActor
    func test_moveTrack_reordersQueue() async {
        let tracks = makeTracks(count: 4)
        sut.loadQueue(tracks: tracks) // [T1, T2, T3, T4], playing T1
        
        // Move T1 (index 0) to after T3 (index 3 destination)
        sut.moveTrack(from: IndexSet(integer: 0), to: 3)
        
        // After move: [T2, T3, T1, T4]
        XCTAssertEqual(sut.queue[0].title, "Track 2")
        XCTAssertEqual(sut.queue[1].title, "Track 3")
        XCTAssertEqual(sut.queue[2].title, "Track 1")
        XCTAssertEqual(sut.queue[3].title, "Track 4")
    }
    
    @MainActor
    func test_moveTrack_updatesCurrentIndex() async {
        let tracks = makeTracks(count: 4)
        sut.loadQueue(tracks: tracks) // playing Track 1 at index 0
        
        let currentTrackId = sut.currentTrack?.id
        
        // Move Track 1 from index 0 to index 3
        sut.moveTrack(from: IndexSet(integer: 0), to: 3)
        
        // currentTrack should still be Track 1, but at new index
        XCTAssertEqual(sut.currentTrack?.id, currentTrackId)
        XCTAssertEqual(sut.currentIndex, 2) // T1 is now at index 2 after move
    }
    
    // MARK: - ShuffleMode Enum Tests
    
    @MainActor
    func test_shuffleMode_allCases() async {
        let allModes = ShuffleMode.allCases
        XCTAssertEqual(allModes.count, 4)
        XCTAssertTrue(allModes.contains(.random))
        XCTAssertTrue(allModes.contains(.albumBased))
        XCTAssertTrue(allModes.contains(.artistBased))
        XCTAssertTrue(allModes.contains(.weighted))
    }
    
    @MainActor
    func test_shuffleMode_rawValues() async {
        XCTAssertEqual(ShuffleMode.random.rawValue, "Random")
        XCTAssertEqual(ShuffleMode.albumBased.rawValue, "Album Shuffle")
        XCTAssertEqual(ShuffleMode.artistBased.rawValue, "Artist Shuffle")
        XCTAssertEqual(ShuffleMode.weighted.rawValue, "Smart Shuffle")
    }
    
    @MainActor
    func test_shuffleMode_iconNames() async {
        XCTAssertEqual(ShuffleMode.random.iconName, "shuffle")
        XCTAssertEqual(ShuffleMode.albumBased.iconName, "square.stack")
        XCTAssertEqual(ShuffleMode.artistBased.iconName, "person.2")
        XCTAssertEqual(ShuffleMode.weighted.iconName, "brain")
    }
    
    // MARK: - RepeatMode Enum Tests
    
    @MainActor
    func test_repeatMode_rawValues() async {
        XCTAssertEqual(RepeatMode.off.rawValue, "off")
        XCTAssertEqual(RepeatMode.all.rawValue, "all")
        XCTAssertEqual(RepeatMode.one.rawValue, "one")
    }
    
    // MARK: - Repeat Mode Icon/State Tests
    
    @MainActor
    func test_repeatModeIcon_off_returnsRepeat() async {
        sut.repeatMode = .off
        XCTAssertEqual(sut.repeatModeIcon, "repeat")
    }
    
    @MainActor
    func test_repeatModeIcon_all_returnsRepeat() async {
        sut.repeatMode = .all
        XCTAssertEqual(sut.repeatModeIcon, "repeat")
    }
    
    @MainActor
    func test_repeatModeIcon_one_returnsRepeatOne() async {
        sut.repeatMode = .one
        XCTAssertEqual(sut.repeatModeIcon, "repeat.1")
    }
    
    @MainActor
    func test_isRepeatActive_offIsFalse() async {
        sut.repeatMode = .off
        XCTAssertFalse(sut.isRepeatActive)
    }
    
    @MainActor
    func test_isRepeatActive_allIsTrue() async {
        sut.repeatMode = .all
        XCTAssertTrue(sut.isRepeatActive)
    }
    
    @MainActor
    func test_isRepeatActive_oneIsTrue() async {
        sut.repeatMode = .one
        XCTAssertTrue(sut.isRepeatActive)
    }
    
    // MARK: - Complex Scenario Tests
    
    @MainActor
    func test_loadQueue_thenAdvanceThroughAll_withRepeatAll_wraps() async {
        let tracks = makeTracks(count: 3)
        sut.repeatMode = .all
        sut.loadQueue(tracks: tracks) // starts at 0
        
        sut.advanceToNext() // -> 1
        sut.advanceToNext() // -> 2
        sut.advanceToNext() // -> 0 (wrap)
        
        XCTAssertEqual(sut.currentIndex, 0)
        XCTAssertEqual(sut.currentTrack?.title, "Track 1")
    }
    
    @MainActor
    func test_playNextThenAdvance_playsInsertedTrack() async {
        let tracks = makeTracks(count: 3)
        sut.loadQueue(tracks: tracks) // starts at index 0
        
        let inserted = makeTrack(title: "Inserted Track")
        sut.playNext(track: inserted) // inserted at index 1
        
        playedTracks = []
        sut.advanceToNext() // should play the inserted track
        
        XCTAssertEqual(sut.currentTrack?.title, "Inserted Track")
    }
    
    @MainActor
    func test_appendThenAdvanceToEnd_playsAppendedTracks() async {
        let tracks = makeTracks(count: 2)
        sut.loadQueue(tracks: tracks, startIndex: 1) // at last track
        
        let appended = [makeTrack(title: "Appended")]
        sut.appendToQueue(tracks: appended)
        
        playedTracks = []
        sut.advanceToNext() // should go to index 2 (appended)
        
        XCTAssertEqual(sut.currentTrack?.title, "Appended")
    }
}
