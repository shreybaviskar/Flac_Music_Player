//
//  LibraryViewModel.swift
//  AuraPlayer
//
//  ViewModel bridging the SwiftData library (Track, Album, Playlist)
//  with the UI. Handles search, sort, filter, import, and CRUD.
//

import Foundation
import SwiftData
import SwiftUI
import Combine

// MARK: - Sort Options

enum TrackSortOption: String, CaseIterable, Identifiable {
    case title       = "Title"
    case artist      = "Artist"
    case album       = "Album"
    case dateAdded   = "Date Added"
    case duration    = "Duration"
    case playCount   = "Play Count"
    
    var id: String { rawValue }
}

enum AlbumSortOption: String, CaseIterable, Identifiable {
    case title     = "Title"
    case artist    = "Artist"
    case year      = "Year"
    case dateAdded = "Date Added"
    case trackCount = "Track Count"
    
    var id: String { rawValue }
}

// MARK: - Library Tab

enum LibraryTab: String, CaseIterable, Identifiable {
    case songs     = "Songs"
    case albums    = "Albums"
    case artists   = "Artists"
    case playlists = "Playlists"
    case favorites = "Favorites"
    
    var id: String { rawValue }
    
    var iconName: String {
        switch self {
        case .songs:     return "music.note"
        case .albums:    return "square.stack"
        case .artists:   return "music.mic"
        case .playlists: return "music.note.list"
        case .favorites: return "heart.fill"
        }
    }
}

// MARK: - LibraryViewModel

@MainActor
final class LibraryViewModel: ObservableObject {
    
    // MARK: - Published State
    
    /// The active library tab.
    @Published var selectedTab: LibraryTab = .songs
    
    /// Current search query.
    @Published var searchText: String = ""
    
    /// Sort option for songs view.
    @Published var trackSortOption: TrackSortOption = .title
    
    /// Sort option for albums view.
    @Published var albumSortOption: AlbumSortOption = .title
    
    /// Whether sort is ascending.
    @Published var sortAscending: Bool = true
    
    /// Whether the folder picker is showing.
    @Published var showingFolderPicker: Bool = false
    
    /// Whether an import is in progress.
    @Published var isImporting: Bool = false
    
    /// Import result alert.
    @Published var showImportResult: Bool = false
    @Published var importResultMessage: String = ""
    
    /// Library stats.
    @Published var totalTracks: Int = 0
    @Published var totalAlbums: Int = 0
    @Published var totalArtists: Int = 0
    @Published var totalDuration: TimeInterval = 0
    
    // MARK: - Dependencies
    
    let importer = LibraryImporter()
    
    // MARK: - Debounced Search
    
    private var searchCancellable: AnyCancellable?
    @Published var debouncedSearchText: String = ""
    
    init() {
        // Debounce search to avoid re-querying on every keystroke.
        searchCancellable = $searchText
            .debounce(for: .milliseconds(300), scheduler: DispatchQueue.main)
            .removeDuplicates()
            .assign(to: \.debouncedSearchText, on: self)
    }
    
    // MARK: - SwiftData Descriptors
    
    /// Builds a FetchDescriptor for tracks with current search/sort applied.
    func trackDescriptor() -> FetchDescriptor<Track> {
        var descriptor = FetchDescriptor<Track>()
        
        // Search predicate.
        if !debouncedSearchText.isEmpty {
            let query = debouncedSearchText
            descriptor.predicate = #Predicate<Track> { track in
                track.title.localizedStandardContains(query) ||
                track.artistName.localizedStandardContains(query) ||
                track.albumTitle.localizedStandardContains(query)
            }
        }
        
        // Sort.
        let ascending = sortAscending
        switch trackSortOption {
        case .title:
            descriptor.sortBy = [SortDescriptor(\.title, order: ascending ? .forward : .reverse)]
        case .artist:
            descriptor.sortBy = [
                SortDescriptor(\.artistName, order: ascending ? .forward : .reverse),
                SortDescriptor(\.title, order: .forward)
            ]
        case .album:
            descriptor.sortBy = [
                SortDescriptor(\.albumTitle, order: ascending ? .forward : .reverse),
                SortDescriptor(\.trackNumber, order: .forward)
            ]
        case .dateAdded:
            descriptor.sortBy = [SortDescriptor(\.dateAdded, order: ascending ? .forward : .reverse)]
        case .duration:
            descriptor.sortBy = [SortDescriptor(\.duration, order: ascending ? .forward : .reverse)]
        case .playCount:
            descriptor.sortBy = [SortDescriptor(\.playCount, order: ascending ? .forward : .reverse)]
        }
        
        return descriptor
    }
    
    /// Builds a FetchDescriptor for favorite tracks.
    func favoritesDescriptor() -> FetchDescriptor<Track> {
        var descriptor = FetchDescriptor<Track>(
            predicate: #Predicate<Track> { $0.isFavorite }
        )
        descriptor.sortBy = [SortDescriptor(\.title, order: .forward)]
        return descriptor
    }
    
    /// Builds a FetchDescriptor for albums.
    func albumDescriptor() -> FetchDescriptor<Album> {
        var descriptor = FetchDescriptor<Album>()
        
        if !debouncedSearchText.isEmpty {
            let query = debouncedSearchText
            descriptor.predicate = #Predicate<Album> { album in
                album.title.localizedStandardContains(query) ||
                album.artistName.localizedStandardContains(query)
            }
        }
        
        let ascending = sortAscending
        switch albumSortOption {
        case .title:
            descriptor.sortBy = [SortDescriptor(\.title, order: ascending ? .forward : .reverse)]
        case .artist:
            descriptor.sortBy = [SortDescriptor(\.artistName, order: ascending ? .forward : .reverse)]
        case .year:
            descriptor.sortBy = [SortDescriptor(\.year, order: ascending ? .forward : .reverse)]
        case .dateAdded:
            descriptor.sortBy = [SortDescriptor(\.dateAdded, order: ascending ? .forward : .reverse)]
        case .trackCount:
            descriptor.sortBy = [SortDescriptor(\.title, order: .forward)]
        }
        
        return descriptor
    }
    
    /// Builds a FetchDescriptor for playlists.
    func playlistDescriptor() -> FetchDescriptor<Playlist> {
        var descriptor = FetchDescriptor<Playlist>()
        descriptor.sortBy = [SortDescriptor(\.dateModified, order: .reverse)]
        
        if !debouncedSearchText.isEmpty {
            let query = debouncedSearchText
            descriptor.predicate = #Predicate<Playlist> { playlist in
                playlist.name.localizedStandardContains(query)
            }
        }
        
        return descriptor
    }
    
    // MARK: - Artist Grouping
    
    /// Groups tracks by artist name for the Artists tab.
    func groupTracksByArtist(_ tracks: [Track]) -> [(name: String, tracks: [Track])] {
        let grouped = Dictionary(grouping: tracks) { $0.artistName }
        return grouped
            .map { (name: $0.key, tracks: $0.value) }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }
    
    // MARK: - Import Actions
    
    /// Imports a user-selected folder into the library.
    func importFolder(_ folderURL: URL, modelContext: ModelContext) {
        isImporting = true
        
        Task {
            do {
                let count = try await importer.importFolder(folderURL, into: modelContext)
                
                importResultMessage = count > 0
                    ? "Imported \(count) track\(count == 1 ? "" : "s")"
                    : "No new tracks found"
                
                if importer.lastSkippedCount > 0 {
                    importResultMessage += " (\(importer.lastSkippedCount) already in library)"
                }
                
                updateStats(modelContext: modelContext)
                showImportResult = true
                
            } catch {
                importResultMessage = "Import failed: \(error.localizedDescription)"
                showImportResult = true
            }
            
            isImporting = false
        }
    }
    
    /// Re-scans all saved folders for new files.
    func rescanLibrary(modelContext: ModelContext) {
        isImporting = true
        
        Task {
            do {
                let count = try await importer.rescanSavedFolders(into: modelContext)
                
                importResultMessage = count > 0
                    ? "Found \(count) new track\(count == 1 ? "" : "s")"
                    : "Library is up to date"
                
                updateStats(modelContext: modelContext)
                showImportResult = true
                
            } catch {
                importResultMessage = "Rescan failed: \(error.localizedDescription)"
                showImportResult = true
            }
            
            isImporting = false
        }
    }
    
    /// Removes orphaned tracks (files that no longer exist).
    func pruneOrphanedTracks(modelContext: ModelContext) {
        let removed = importer.pruneOrphanedTracks(from: modelContext)
        if removed > 0 {
            importResultMessage = "Removed \(removed) orphaned track\(removed == 1 ? "" : "s")"
            updateStats(modelContext: modelContext)
            showImportResult = true
        }
    }
    
    // MARK: - Library Stats
    
    func updateStats(modelContext: ModelContext) {
        let trackDescriptor = FetchDescriptor<Track>()
        let albumDescriptor = FetchDescriptor<Album>()
        
        totalTracks = (try? modelContext.fetchCount(trackDescriptor)) ?? 0
        totalAlbums = (try? modelContext.fetchCount(albumDescriptor)) ?? 0
        
        // Count unique artists.
        if let tracks = try? modelContext.fetch(trackDescriptor) {
            totalArtists = Set(tracks.map(\.artistName)).count
            totalDuration = tracks.reduce(0) { $0 + $1.duration }
        }
    }
    
    /// Formatted total library duration.
    var formattedTotalDuration: String {
        let hours = Int(totalDuration) / 3600
        let minutes = (Int(totalDuration) % 3600) / 60
        if hours > 0 {
            return "\(hours) hr \(minutes) min"
        }
        return "\(minutes) min"
    }
    
    // MARK: - Playback Actions
    
    /// Plays all tracks starting from a specific track.
    func playAllTracks(_ tracks: [Track], startingFrom track: Track) {
        guard let startIndex = tracks.firstIndex(where: { $0.id == track.id }) else { return }
        QueueManager.shared.loadQueue(tracks: tracks, startIndex: startIndex)
    }
    
    /// Shuffles and plays all tracks.
    func shuffleAll(_ tracks: [Track]) {
        guard !tracks.isEmpty else { return }
        QueueManager.shared.isShuffleEnabled = true
        QueueManager.shared.loadQueue(tracks: tracks, startIndex: 0)
    }
    
    /// Plays an entire album.
    func playAlbum(_ album: Album) {
        let tracks = album.sortedTracks
        guard !tracks.isEmpty else { return }
        QueueManager.shared.loadQueue(tracks: tracks, startIndex: 0)
    }
    
    /// Plays an entire playlist.
    func playPlaylist(_ playlist: Playlist) {
        let tracks = playlist.orderedTracks
        guard !tracks.isEmpty else { return }
        QueueManager.shared.loadQueue(tracks: tracks, startIndex: 0)
    }
    
    // MARK: - Track Actions
    
    func toggleFavorite(_ track: Track) {
        track.isFavorite.toggle()
    }
    
    func deleteTrack(_ track: Track, modelContext: ModelContext) {
        modelContext.delete(track)
        try? modelContext.save()
    }
    
    // MARK: - Playlist CRUD
    
    func createPlaylist(name: String, tracks: [Track] = [], modelContext: ModelContext) -> Playlist {
        let playlist = Playlist(
            name: name,
            trackOrder: tracks.map(\.id),
            tracks: tracks
        )
        modelContext.insert(playlist)
        try? modelContext.save()
        return playlist
    }
    
    func deletePlaylist(_ playlist: Playlist, modelContext: ModelContext) {
        modelContext.delete(playlist)
        try? modelContext.save()
    }
    
    func renamePlaylist(_ playlist: Playlist, to newName: String) {
        playlist.name = newName
        playlist.dateModified = Date()
    }
    
    func addTrackToPlaylist(_ track: Track, playlist: Playlist) {
        playlist.addTrack(track)
    }
    
    func removeTrackFromPlaylist(_ track: Track, playlist: Playlist) {
        playlist.removeTrack(track)
    }
    
    // MARK: - EQ Preset Initialization
    
    /// Seeds the database with factory EQ presets if none exist.
    func seedEQPresetsIfNeeded(modelContext: ModelContext) {
        let descriptor = FetchDescriptor<EQPreset>()
        let count = (try? modelContext.fetchCount(descriptor)) ?? 0
        
        guard count == 0 else { return }
        
        for preset in EQPreset.allFactoryPresets {
            modelContext.insert(preset)
        }
        try? modelContext.save()
    }
}
