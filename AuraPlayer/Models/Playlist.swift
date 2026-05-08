//
//  Playlist.swift
//  AuraPlayer
//
//  SwiftData entity representing a user-created playlist.
//

import Foundation
import SwiftData

@Model
final class Playlist {
    
    // MARK: - Identity
    
    @Attribute(.unique)
    var id: UUID
    
    // MARK: - Metadata
    
    /// User-defined playlist name.
    var name: String
    
    /// Optional user description / notes.
    var descriptionText: String?
    
    // MARK: - Artwork
    
    /// Optional custom artwork for the playlist.
    /// If nil, the UI should generate a mosaic from the first 4 track artworks.
    @Attribute(.externalStorage)
    var artworkData: Data?
    
    // MARK: - Track Ordering
    
    /// Ordered list of track IDs that defines the playlist sequence.
    /// We store IDs separately from the relationship because SwiftData
    /// relationships are unordered sets — this array preserves user ordering.
    var trackOrder: [UUID]
    
    // MARK: - Relationships
    
    /// The tracks in this playlist (unordered set — use `trackOrder` for sequence).
    var tracks: [Track]
    
    // MARK: - Timestamps
    
    var dateCreated: Date
    var dateModified: Date
    
    // MARK: - Initializer
    
    init(
        id: UUID = UUID(),
        name: String,
        descriptionText: String? = nil,
        artworkData: Data? = nil,
        trackOrder: [UUID] = [],
        tracks: [Track] = [],
        dateCreated: Date = Date(),
        dateModified: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.descriptionText = descriptionText
        self.artworkData = artworkData
        self.trackOrder = trackOrder
        self.tracks = tracks
        self.dateCreated = dateCreated
        self.dateModified = dateModified
    }
}

// MARK: - Convenience

extension Playlist {
    
    /// Total duration of all tracks in the playlist.
    var totalDuration: TimeInterval {
        tracks.reduce(0) { $0 + $1.duration }
    }
    
    /// Formatted total duration.
    var formattedDuration: String {
        let totalMinutes = Int(totalDuration) / 60
        if totalMinutes >= 60 {
            let hours = totalMinutes / 60
            let mins = totalMinutes % 60
            return "\(hours) hr \(mins) min"
        }
        return "\(totalMinutes) min"
    }
    
    /// Number of tracks.
    var trackCount: Int {
        tracks.count
    }
    
    /// Returns tracks in the user-defined order.
    /// Falls back to the unordered relationship if the order array is stale.
    var orderedTracks: [Track] {
        guard !trackOrder.isEmpty else { return tracks }
        
        let trackLookup = Dictionary(uniqueKeysWithValues: tracks.map { ($0.id, $0) })
        var ordered: [Track] = []
        
        for trackID in trackOrder {
            if let track = trackLookup[trackID] {
                ordered.append(track)
            }
        }
        
        // Append any tracks that exist in the relationship but not in the order array
        // (safety net for data consistency).
        let orderedIDs = Set(trackOrder)
        for track in tracks where !orderedIDs.contains(track.id) {
            ordered.append(track)
        }
        
        return ordered
    }
    
    /// Adds a track to the end of the playlist.
    func addTrack(_ track: Track) {
        if !tracks.contains(where: { $0.id == track.id }) {
            tracks.append(track)
            trackOrder.append(track.id)
            dateModified = Date()
        }
    }
    
    /// Removes a track from the playlist.
    func removeTrack(_ track: Track) {
        tracks.removeAll { $0.id == track.id }
        trackOrder.removeAll { $0 == track.id }
        dateModified = Date()
    }
    
    /// Moves a track within the playlist order.
    func moveTrack(from source: IndexSet, to destination: Int) {
        trackOrder.move(fromOffsets: source, toOffset: destination)
        dateModified = Date()
    }
}
