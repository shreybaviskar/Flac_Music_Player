//
//  Album.swift
//  AuraPlayer
//
//  SwiftData entity representing an album (a collection of tracks
//  grouped by album title + artist).
//

import Foundation
import SwiftData

@Model
final class Album {
    
    // MARK: - Identity
    
    @Attribute(.unique)
    var id: UUID
    
    // MARK: - Metadata
    
    /// Album title as read from the track metadata.
    var title: String
    
    /// Primary artist / "Album Artist" field.
    var artistName: String
    
    /// Release year (extracted from the first track's metadata).
    var year: Int?
    
    /// Genre of the album (inherited from the majority of its tracks).
    var genre: String?
    
    // MARK: - Album Art
    
    /// Album artwork stored as raw image data.
    /// Typically pulled from the first track that has embedded art.
    @Attribute(.externalStorage)
    var artworkData: Data?
    
    // MARK: - Relationships
    
    /// All tracks that belong to this album, ordered by disc/track number.
    var tracks: [Track]
    
    // MARK: - Library Metadata
    
    var dateAdded: Date
    
    // MARK: - Initializer
    
    init(
        id: UUID = UUID(),
        title: String,
        artistName: String = "Unknown Artist",
        year: Int? = nil,
        genre: String? = nil,
        artworkData: Data? = nil,
        tracks: [Track] = [],
        dateAdded: Date = Date()
    ) {
        self.id = id
        self.title = title
        self.artistName = artistName
        self.year = year
        self.genre = genre
        self.artworkData = artworkData
        self.tracks = tracks
        self.dateAdded = dateAdded
    }
}

// MARK: - Convenience

extension Album {
    
    /// Total duration of all tracks in the album.
    var totalDuration: TimeInterval {
        tracks.reduce(0) { $0 + $1.duration }
    }
    
    /// Formatted total duration (e.g. "42 min").
    var formattedDuration: String {
        let totalMinutes = Int(totalDuration) / 60
        if totalMinutes >= 60 {
            let hours = totalMinutes / 60
            let mins = totalMinutes % 60
            return "\(hours) hr \(mins) min"
        }
        return "\(totalMinutes) min"
    }
    
    /// Number of tracks in the album.
    var trackCount: Int {
        tracks.count
    }
    
    /// Tracks sorted by disc number then track number.
    var sortedTracks: [Track] {
        tracks.sorted { lhs, rhs in
            let lDisc = lhs.discNumber ?? 1
            let rDisc = rhs.discNumber ?? 1
            if lDisc != rDisc { return lDisc < rDisc }
            
            let lTrack = lhs.trackNumber ?? 0
            let rTrack = rhs.trackNumber ?? 0
            return lTrack < rTrack
        }
    }
    
    /// Whether this album contains any Hi-Res tracks.
    var isHiRes: Bool {
        tracks.contains { $0.isHiRes }
    }
    
    /// Whether all tracks in this album are lossless.
    var isLossless: Bool {
        !tracks.isEmpty && tracks.allSatisfy { $0.isLossless }
    }
    
    /// A human-readable subtitle, e.g. "2023 · 12 songs · Lossless".
    var subtitle: String {
        var parts: [String] = []
        if let year { parts.append("\(year)") }
        parts.append("\(trackCount) song\(trackCount == 1 ? "" : "s")")
        if isHiRes {
            parts.append("Hi-Res")
        } else if isLossless {
            parts.append("Lossless")
        }
        return parts.joined(separator: " · ")
    }
}
