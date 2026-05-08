//
//  PlaybackController.swift
//  AuraPlayer
//
//  High-level playback controller that bridges the AudioEngineManager
//  with SwiftData Track models, manages Now Playing info on the lock
//  screen, and handles remote command center events.
//

import Foundation
import AVFoundation
import MediaPlayer
import SwiftData
import Combine
import UIKit

// MARK: - PlaybackController

/// The top-level playback controller that the UI interacts with.
///
/// Sits above `AudioEngineManager` and adds:
/// - Track model integration (resolves bookmarks, starts security-scoped access)
/// - MPNowPlayingInfoCenter updates (lock screen, Control Center, AirPlay)
/// - MPRemoteCommandCenter handling (play, pause, skip, seek)
/// - Gapless playback preparation (pre-loads next track)
/// - Play count tracking
@MainActor
final class PlaybackController: ObservableObject {
    
    static let shared = PlaybackController()
    
    // MARK: - Dependencies
    
    private let engine = AudioEngineManager.shared
    private let session = AudioSessionManager.shared
    private let fileManager = FileSystemManager.shared
    
    // MARK: - Published State
    
    @Published private(set) var currentTrack: Track?
    @Published private(set) var isPlaying: Bool = false
    @Published private(set) var isPaused: Bool = false
    @Published var currentTime: TimeInterval = 0
    @Published var duration: TimeInterval = 0
    @Published var playbackProgress: Double = 0
    @Published private(set) var outputRoute: AudioRouteInfo = .builtInSpeaker
    @Published private(set) var currentSampleRate: Double = 44100
    @Published private(set) var currentBitDepth: Int = 16
    
    // MARK: - Security-Scoped Access
    
    /// The currently accessed security-scoped URL.
    /// Must be stopped when playback ends or track changes.
    private var accessedURL: URL?
    
    // MARK: - Combine
    
    private var cancellables = Set<AnyCancellable>()
    
    // MARK: - Callbacks
    
    /// Called when the current track finishes and the next track should play.
    var onTrackFinished: (() -> Void)?
    
    // MARK: - Init
    
    private init() {
        setupBindings()
        setupRemoteCommands()
        setupSessionCallbacks()
        setupQueueManagerBinding()
    }
    
    /// Connects QueueManager's play callback to this controller.
    private func setupQueueManagerBinding() {
        QueueManager.shared.onPlayTrack = { [weak self] track in
            Task { @MainActor in
                self?.play(track: track)
            }
        }
        
        QueueManager.shared.onQueueExhausted = { [weak self] in
            Task { @MainActor in
                self?.stop()
            }
        }
    }
    
    // MARK: - Bindings
    
    private func setupBindings() {
        // Forward engine state to our published properties.
        engine.$playbackState
            .receive(on: DispatchQueue.main)
            .sink { [weak self] state in
                self?.isPlaying = state == .playing
                self?.isPaused = state == .paused
            }
            .store(in: &cancellables)
        
        engine.$currentTime
            .receive(on: DispatchQueue.main)
            .assign(to: &$currentTime)
        
        engine.$duration
            .receive(on: DispatchQueue.main)
            .assign(to: &$duration)
        
        engine.$playbackProgress
            .receive(on: DispatchQueue.main)
            .assign(to: &$playbackProgress)
        
        engine.$currentSampleRate
            .receive(on: DispatchQueue.main)
            .assign(to: &$currentSampleRate)
        
        engine.$currentBitDepth
            .receive(on: DispatchQueue.main)
            .assign(to: &$currentBitDepth)
        
        session.$currentRoute
            .receive(on: DispatchQueue.main)
            .assign(to: &$outputRoute)
        
        // Handle track completion → advance queue.
        engine.onTrackCompleted = { [weak self] in
            Task { @MainActor in
                self?.handleTrackCompletion()
            }
        }
    }
    
    // MARK: - Session Callbacks
    
    private func setupSessionCallbacks() {
        // Handle route changes (e.g. DAC plugged in → reconfigure engine).
        session.onRouteChanged = { [weak self] newRoute in
            Task { @MainActor in
                guard let self else { return }
                self.outputRoute = newRoute
                
                // Reconfigure engine for new output format.
                if newRoute.isExternalDAC || newRoute.sampleRate != self.currentSampleRate {
                    self.engine.reconfigureEngine()
                }
            }
        }
        
        // Handle interruptions (phone call, Siri).
        session.onInterruption = { [weak self] shouldResume in
            Task { @MainActor in
                guard let self else { return }
                if shouldResume && self.isPaused {
                    self.resume()
                } else if !shouldResume && self.isPlaying {
                    self.pause()
                }
            }
        }
    }
    
    // MARK: - Playback API
    
    /// Plays a Track model entity.
    ///
    /// Resolves the bookmark, starts security-scoped access, and hands
    /// the URL to the engine.
    func play(track: Track) {
        // Stop accessing the previous file.
        stopSecurityAccess()
        
        // Resolve the file URL from bookmark data.
        guard let bookmarkData = track.bookmarkData,
              let url = fileManager.startAccessing(bookmarkData) else {
            // Fallback: try the raw file path.
            let fallbackURL = URL(fileURLWithPath: track.filePath)
            if FileManager.default.fileExists(atPath: track.filePath) {
                currentTrack = track
                engine.loadAndPlay(url: fallbackURL)
                updateNowPlayingInfo()
                return
            }
            print("[Playback] Cannot resolve file for track: \(track.title)")
            return
        }
        
        accessedURL = url
        currentTrack = track
        engine.loadAndPlay(url: url)
        updateNowPlayingInfo()
    }
    
    func pause() {
        engine.pause()
        updateNowPlayingInfo()
    }
    
    func resume() {
        engine.resume()
        updateNowPlayingInfo()
    }
    
    func togglePlayPause() {
        if isPlaying {
            pause()
        } else if isPaused {
            resume()
        }
    }
    
    func stop() {
        engine.stop()
        stopSecurityAccess()
        currentTrack = nil
        updateNowPlayingInfo()
    }
    
    /// Seeks to a normalized position (0.0 – 1.0).
    func seek(to progress: Double) {
        engine.seek(to: progress)
        updateNowPlayingInfo()
    }
    
    /// Seeks to an absolute time in seconds.
    func seek(toTime time: TimeInterval) {
        engine.seek(toTime: time)
        updateNowPlayingInfo()
    }
    
    // MARK: - EQ Passthrough
    
    func applyEQPreset(_ preset: EQPreset) {
        engine.applyEQPreset(preset)
    }
    
    func setEQBand(index: Int, gain: Float) {
        engine.setEQBand(index: index, gain: gain)
    }
    
    func resetEQ() {
        engine.resetEQ()
    }
    
    func setEQEnabled(_ enabled: Bool) {
        engine.setEQEnabled(enabled)
    }
    
    // MARK: - Volume
    
    func setVolume(_ volume: Float) {
        engine.setVolume(volume)
    }
    
    var volume: Float { engine.volume }
    
    // MARK: - Track Completion
    
    private func handleTrackCompletion() {
        // Increment play count on the completed track.
        if let track = currentTrack {
            track.playCount += 1
            track.lastPlayedDate = Date()
        }
        
        stopSecurityAccess()
        
        // Notify the queue manager to advance.
        onTrackFinished?()
    }
    
    // MARK: - Security-Scoped Access
    
    private func stopSecurityAccess() {
        if let url = accessedURL {
            fileManager.stopAccessing(url)
            accessedURL = nil
        }
    }
    
    // MARK: - Now Playing Info (Lock Screen / Control Center)
    
    private func updateNowPlayingInfo() {
        var info: [String: Any] = [
            MPMediaItemPropertyPlaybackDuration: duration,
            MPNowPlayingInfoPropertyElapsedPlaybackTime: currentTime,
            MPNowPlayingInfoPropertyPlaybackRate: isPlaying ? 1.0 : 0.0
        ]
        
        if let track = currentTrack {
            info[MPMediaItemPropertyTitle] = track.title
            info[MPMediaItemPropertyArtist] = track.artistName
            info[MPMediaItemPropertyAlbumTitle] = track.albumTitle
            
            // Add artwork if available.
            if let artworkData = track.artworkData,
               let image = UIImage(data: artworkData) {
                let artwork = MPMediaItemArtwork(boundsSize: image.size) { _ in image }
                info[MPMediaItemPropertyArtwork] = artwork
            }
            
            // Audio quality info.
            info[MPMediaItemPropertyAssetURL] = track.filePath
        }
        
        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
    }
    
    // MARK: - Remote Command Center (Lock Screen Controls)
    
    private func setupRemoteCommands() {
        let center = MPRemoteCommandCenter.shared()
        
        // Play
        center.playCommand.isEnabled = true
        center.playCommand.addTarget { [weak self] _ in
            Task { @MainActor in
                self?.resume()
            }
            return .success
        }
        
        // Pause
        center.pauseCommand.isEnabled = true
        center.pauseCommand.addTarget { [weak self] _ in
            Task { @MainActor in
                self?.pause()
            }
            return .success
        }
        
        // Toggle Play/Pause
        center.togglePlayPauseCommand.isEnabled = true
        center.togglePlayPauseCommand.addTarget { [weak self] _ in
            Task { @MainActor in
                self?.togglePlayPause()
            }
            return .success
        }
        
        // Next Track
        center.nextTrackCommand.isEnabled = true
        center.nextTrackCommand.addTarget { _ in
            Task { @MainActor in
                QueueManager.shared.advanceToNext()
            }
            return .success
        }
        
        // Previous Track
        center.previousTrackCommand.isEnabled = true
        center.previousTrackCommand.addTarget { _ in
            Task { @MainActor in
                QueueManager.shared.goToPrevious()
            }
            return .success
        }
        
        // Seek (scrubbing on lock screen)
        center.changePlaybackPositionCommand.isEnabled = true
        center.changePlaybackPositionCommand.addTarget { [weak self] event in
            guard let positionEvent = event as? MPChangePlaybackPositionCommandEvent else {
                return .commandFailed
            }
            Task { @MainActor in
                self?.seek(toTime: positionEvent.positionTime)
            }
            return .success
        }
    }
}
