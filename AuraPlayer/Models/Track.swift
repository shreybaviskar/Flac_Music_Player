//
//  Track.swift
//  AuraPlayer
//
//  SwiftData entity representing a single audio track.
//

import Foundation
import SwiftData
import SwiftUI

/// Supported audio codecs for the player pipeline.
enum AudioCodec: String, Codable, CaseIterable {
    case flac  = "FLAC"
    case alac  = "ALAC"
    case wav   = "WAV"
    case mp3   = "MP3"
    
    /// Returns the codec for a given file extension, or nil if unsupported.
    static func from(extension ext: String) -> AudioCodec? {
        switch ext.lowercased() {
        case "flac":        return .flac
        case "m4a", "caf":  return .alac   // ALAC is typically in m4a/caf containers
        case "wav":         return .wav
        case "mp3":         return .mp3
        default:            return nil
        }
    }
}

/// Represents the repeat mode for playback.
enum RepeatMode: String, Codable {
    case off
    case all
    case one
}

@Model
final class Track {
    
    // MARK: - Identity
    
    /// A stable identifier derived from the file's bookmark data.
    /// Using a UUID instead of the file path because paths can change
    /// when volumes are remounted or the app is reinstalled.
    @Attribute(.unique)
    var id: UUID
    
    // MARK: - File Reference
    
    /// Security-scoped bookmark data for the file.
    /// This is the canonical way to persist file access across app launches
    /// when using UIDocumentPickerViewController.
    var bookmarkData: Data?
    
    /// The last-known absolute file path (for display / debugging).
    /// Not used for file access — always resolve from `bookmarkData`.
    var filePath: String
    
    /// The file extension (lowercase), e.g. "flac", "mp3".
    var fileExtension: String
    
    /// File size in bytes — useful for library stats.
    var fileSize: Int64
    
    // MARK: - Metadata (ID3 / Vorbis)
    
    var title: String
    var artistName: String
    var albumTitle: String
    var genre: String?
    var composer: String?
    var year: Int?
    var trackNumber: Int?
    var discNumber: Int?
    var lyrics: String?
    
    // MARK: - Audio Properties
    
    /// Duration in seconds.
    var duration: TimeInterval
    
    /// Native sample rate in Hz (e.g. 44100, 96000, 192000).
    var sampleRate: Double
    
    /// Bit depth (e.g. 16, 24, 32).
    var bitDepth: Int
    
    /// Number of audio channels (1 = mono, 2 = stereo).
    var channelCount: Int
    
    /// Detected codec.
    var codec: AudioCodec
    
    /// Bitrate in kbps (relevant for lossy formats like MP3).
    var bitrate: Int?
    
    // MARK: - Album Art
    
    /// Embedded album art stored as raw image data (JPEG/PNG).
    /// Stored as an external attribute to keep the main table lean.
    @Attribute(.externalStorage)
    var artworkData: Data?
    
    // MARK: - Library Metadata
    
    /// When this track was first imported into the library.
    var dateAdded: Date
    
    /// Number of times this track has been fully played.
    var playCount: Int
    
    /// The last time this track was played.
    var lastPlayedDate: Date?
    
    /// User's favorite flag.
    var isFavorite: Bool
    
    // MARK: - Relationships
    
    /// The album this track belongs to (optional — singles may not have one).
    @Relationship(inverse: \Album.tracks)
    var album: Album?
    
    /// Playlists that contain this track.
    @Relationship(inverse: \Playlist.tracks)
    var playlists: [Playlist]
    
    // MARK: - Initializer
    
    init(
        id: UUID = UUID(),
        filePath: String,
        fileExtension: String,
        fileSize: Int64 = 0,
        bookmarkData: Data? = nil,
        title: String,
        artistName: String = "Unknown Artist",
        albumTitle: String = "Unknown Album",
        genre: String? = nil,
        composer: String? = nil,
        year: Int? = nil,
        trackNumber: Int? = nil,
        discNumber: Int? = nil,
        lyrics: String? = nil,
        duration: TimeInterval = 0,
        sampleRate: Double = 44100,
        bitDepth: Int = 16,
        channelCount: Int = 2,
        codec: AudioCodec = .mp3,
        bitrate: Int? = nil,
        artworkData: Data? = nil,
        dateAdded: Date = Date(),
        playCount: Int = 0,
        lastPlayedDate: Date? = nil,
        isFavorite: Bool = false,
        album: Album? = nil,
        playlists: [Playlist] = []
    ) {
        self.id = id
        self.filePath = filePath
        self.fileExtension = fileExtension
        self.fileSize = fileSize
        self.bookmarkData = bookmarkData
        self.title = title
        self.artistName = artistName
        self.albumTitle = albumTitle
        self.genre = genre
        self.composer = composer
        self.year = year
        self.trackNumber = trackNumber
        self.discNumber = discNumber
        self.lyrics = lyrics
        self.duration = duration
        self.sampleRate = sampleRate
        self.bitDepth = bitDepth
        self.channelCount = channelCount
        self.codec = codec
        self.bitrate = bitrate
        self.artworkData = artworkData
        self.dateAdded = dateAdded
        self.playCount = playCount
        self.lastPlayedDate = lastPlayedDate
        self.isFavorite = isFavorite
        self.album = album
        self.playlists = playlists
    }
}

// MARK: - Convenience Computed Properties

extension Track {
    
    /// Formatted duration string (e.g. "3:42").
    var formattedDuration: String {
        let minutes = Int(duration) / 60
        let seconds = Int(duration) % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
    
    /// Human-readable audio quality label (e.g. "24-bit / 96 kHz FLAC").
    var qualityLabel: String {
        let sampleRateKHz = sampleRate / 1000.0
        let sampleRateStr = sampleRateKHz.truncatingRemainder(dividingBy: 1) == 0
            ? String(format: "%.0f", sampleRateKHz)
            : String(format: "%.1f", sampleRateKHz)
        return "\(bitDepth)-bit / \(sampleRateStr) kHz \(codec.rawValue)"
    }
    
    /// Whether this track is lossless.
    var isLossless: Bool {
        switch codec {
        case .flac, .alac, .wav: return true
        case .mp3:               return false
        }
    }
    
    /// Whether this track qualifies as Hi-Res (> 44.1 kHz or > 16-bit).
    var isHiRes: Bool {
        isLossless && (sampleRate > 44100 || bitDepth > 16)
    }
    
    /// Resolves the file URL from stored bookmark data.
    /// Returns nil if the bookmark is stale or missing.
    func resolveFileURL() -> URL? {
        guard let bookmarkData else { return nil }
        
        var isStale = false
        guard let url = try? URL(
            resolvingBookmarkData: bookmarkData,
            options: [],
            relativeTo: nil,
            bookmarkDataIsStale: &isStale
        ) else {
            return nil
        }
        
        // If stale, the caller should re-create the bookmark.
        // We still return the URL because it may still be valid.
        return url
    }
    
    /// Short badge string for UI.
    var qualityBadge: String {
        isHiRes ? "HI-RES" : "LOSSLESS"
    }
    
    /// Color associated with the quality level.
    var qualityColor: Color {
        isHiRes ? .auraWarning : .auraSuccess
    }
}
