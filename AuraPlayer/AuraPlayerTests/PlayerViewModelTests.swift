//
//  PlayerViewModelTests.swift
//  AuraPlayerTests
//
//  Unit tests for the PlayerViewModel class bridging PlaybackController,
//  QueueManager, and active state to the player UI.
//

import XCTest
import SwiftUI
import Combine
import SwiftData
@testable import AuraPlayer

@MainActor
final class PlayerViewModelTests: XCTestCase {
    
    private var sut: PlayerViewModel!
    private var queueManager: QueueManager!
    private var playbackController: PlaybackController!
    
    // MARK: - Helpers
    
    private func makeTrack(
        title: String = "Test Track",
        duration: TimeInterval = 180,
        sampleRate: Double = 44100,
        bitDepth: Int = 16,
        codec: AudioCodec = .flac
    ) -> Track {
        Track(
            filePath: "/test/\(title).flac",
            fileExtension: "flac",
            title: title,
            duration: duration,
            sampleRate: sampleRate,
            bitDepth: bitDepth,
            channelCount: 2,
            codec: codec
        )
    }
    
    // MARK: - Setup & Teardown
    
    override func setUp() async throws {
        try await super.setUp()
        
        // Reset singletons to default values
        queueManager = QueueManager.shared
        queueManager.clearQueue()
        queueManager.isShuffleEnabled = false
        queueManager.repeatMode = .off
        
        playbackController = PlaybackController.shared
        playbackController.stop()
        
        sut = PlayerViewModel()
    }
    
    override func tearDown() async throws {
        playbackController.stop()
        queueManager.clearQueue()
        
        sut = nil
        playbackController = nil
        queueManager = nil
        
        try await super.tearDown()
    }
    
    // MARK: - Initial State
    
    func test_initialState_isCorrect() {
        XCTAssertNil(sut.currentTrack)
        XCTAssertFalse(sut.isPlaying)
        XCTAssertFalse(sut.isPaused)
        XCTAssertEqual(sut.currentTime, 0)
        XCTAssertEqual(sut.duration, 0)
        XCTAssertEqual(sut.playbackProgress, 0)
        XCTAssertEqual(sut.volume, 1.0)
        
        XCTAssertFalse(sut.isNowPlayingExpanded)
        XCTAssertFalse(sut.showingEqualizer)
        XCTAssertFalse(sut.showingQueue)
        XCTAssertFalse(sut.showingLyrics)
        XCTAssertFalse(sut.isSeeking)
        XCTAssertEqual(sut.seekPosition, 0)
        
        XCTAssertTrue(sut.isEQEnabled)
        XCTAssertEqual(sut.preampGain, 0)
        XCTAssertEqual(sut.eqGains.count, 10)
    }
    
    // MARK: - Seeking
    
    func test_seeking_stateChanges_areCorrect() {
        sut.duration = 200
        sut.playbackProgress = 0.25
        
        sut.beginSeeking()
        XCTAssertTrue(sut.isSeeking)
        XCTAssertEqual(sut.seekPosition, 0.25)
        
        sut.updateSeekPosition(0.5)
        XCTAssertEqual(sut.seekPosition, 0.5)
        XCTAssertEqual(sut.currentTime, 100) // 0.5 * 200
        
        sut.endSeeking()
        XCTAssertFalse(sut.isSeeking)
    }
    
    // MARK: - EQ Controls
    
    func test_applyEQPreset_updatesViewModelState() {
        let preset = EQPreset(
            name: "Vocal Boost",
            isBuiltIn: false,
            bands: (0..<10).map { EQBand(frequency: EQFrequency.allCases[$0].rawValue, gain: Float($0), bandwidth: 1.0) },
            preampGain: 3.5,
            isEnabled: true
        )
        
        sut.applyEQPreset(preset)
        
        XCTAssertEqual(sut.activeEQPreset?.name, "Vocal Boost")
        XCTAssertEqual(sut.preampGain, 3.5)
        XCTAssertEqual(sut.eqGains, [0, 1, 2, 3, 4, 5, 6, 7, 8, 9])
        XCTAssertTrue(sut.isEQEnabled)
    }
    
    func test_setEQBand_updatesGainValue() {
        sut.setEQBand(index: 3, gain: 4.5)
        XCTAssertEqual(sut.eqGains[3], 4.5)
        
        sut.setEQBand(index: 12, gain: 5.0) // Out of bounds should be ignored safely
        XCTAssertEqual(sut.eqGains.count, 10)
    }
    
    func test_setPreampGain_updatesGain() {
        sut.setPreampGain(-2.5)
        XCTAssertEqual(sut.preampGain, -2.5)
    }
    
    func test_toggleEQ_togglesEnabledState() {
        XCTAssertTrue(sut.isEQEnabled)
        sut.toggleEQ()
        XCTAssertFalse(sut.isEQEnabled)
        sut.toggleEQ()
        XCTAssertTrue(sut.isEQEnabled)
    }
    
    func test_resetEQ_resetsAllGainsAndActivePreset() {
        let preset = EQPreset(
            name: "Bass",
            isBuiltIn: true,
            bands: EQPreset.flatBands(),
            preampGain: 2.0
        )
        sut.applyEQPreset(preset)
        sut.setEQBand(index: 0, gain: 6.0)
        
        sut.resetEQ()
        
        XCTAssertNil(sut.activeEQPreset)
        XCTAssertEqual(sut.preampGain, 0)
        XCTAssertEqual(sut.eqGains, Array(repeating: 0, count: 10))
    }
    
    // MARK: - Visualizer
    
    func test_visualizer_activation_togglesState() {
        XCTAssertFalse(sut.isVisualizerActive)
        sut.startVisualizer()
        XCTAssertTrue(sut.isVisualizerActive)
        sut.stopVisualizer()
        XCTAssertFalse(sut.isVisualizerActive)
    }
    
    // MARK: - Queue Passthrough Actions
    
    func test_queueActions_forwardToQueueManager() {
        let track = makeTrack(title: "Track A")
        let tracks = [track, makeTrack(title: "Track B")]
        
        queueManager.loadQueue(tracks: tracks, startIndex: 0)
        XCTAssertEqual(queueManager.queue.count, 2)
        
        sut.toggleShuffle()
        XCTAssertEqual(sut.isShuffleEnabled, queueManager.isShuffleEnabled)
        
        sut.setShuffleMode(.albumBased)
        XCTAssertEqual(sut.shuffleMode, .albumBased)
        
        sut.cycleRepeatMode()
        XCTAssertEqual(sut.repeatMode, queueManager.repeatMode)
    }
    
    // MARK: - Format Helpers
    
    func test_formattedTimes_areCorrectlyFormatted() {
        sut.duration = 245 // 4 min 5 sec
        sut.currentTime = 62 // 1 min 2 sec
        
        XCTAssertEqual(sut.formattedDuration, "4:05")
        XCTAssertEqual(sut.formattedCurrentTime, "1:02")
        XCTAssertEqual(sut.formattedRemainingTime, "-3:03")
    }
}
