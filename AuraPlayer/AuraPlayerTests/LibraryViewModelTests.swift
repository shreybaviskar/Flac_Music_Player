//
//  LibraryViewModelTests.swift
//  AuraPlayerTests
//
//  Unit tests for the LibraryViewModel class, validating SwiftData FetchDescriptors,
//  sorting logic, grouping by artist, stats updates, and playlist operations.
//

import XCTest
import SwiftData
@testable import AuraPlayer

final class LibraryViewModelTests: XCTestCase {
    
    private var sut: LibraryViewModel!
    private var container: ModelContainer!
    private var context: ModelContext!
    
    // MARK: - Setup & Teardown
    
    @MainActor
    override func setUp() async throws {
        try await super.setUp()
        
        // Build in-memory SwiftData container
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        container = try ModelContainer(
            for: Track.self, Album.self, Playlist.self, EQPreset.self,
            configurations: config
        )
        context = container.mainContext
        
        sut = LibraryViewModel()
    }
    
    @MainActor
    override func tearDown() async throws {
        sut = nil
        context = nil
        container = nil
        
        try await super.tearDown()
    }
    
    // MARK: - Helpers
    
    private func createDummyTrack(title: String, artist: String = "Artist X", album: String = "Album Y", isFavorite: Bool = false) -> Track {
        let track = Track(
            filePath: "/music/\(title).flac",
            fileExtension: "flac",
            title: title,
            artistName: artist,
            albumTitle: album,
            duration: 180,
            sampleRate: 44100,
            bitDepth: 16,
            channelCount: 2,
            codec: .flac,
            isFavorite: isFavorite
        )
        context.insert(track)
        return track
    }
    
    // MARK: - Sorting and Predicates
    
    func test_trackDescriptor_withSearchText_setsCorrectPredicate() {
        sut.searchText = "Heavy"
        sut.debouncedSearchText = "Heavy" // Manually set to skip Combine debounce latency in tests
        
        let descriptor = sut.trackDescriptor()
        
        XCTAssertNotNil(descriptor.predicate)
    }
    
    func test_trackDescriptor_sortByTitleAscending() {
        sut.trackSortOption = .title
        sut.sortAscending = true
        
        let descriptor = sut.trackDescriptor()
        XCTAssertEqual(descriptor.sortBy.count, 1)
    }
    
    func test_trackDescriptor_sortByArtistDescending() {
        sut.trackSortOption = .artist
        sut.sortAscending = false
        
        let descriptor = sut.trackDescriptor()
        XCTAssertEqual(descriptor.sortBy.count, 2)
    }
    
    func test_albumDescriptor_withSearchText() {
        sut.searchText = "Acoustic"
        sut.debouncedSearchText = "Acoustic"
        
        let descriptor = sut.albumDescriptor()
        XCTAssertNotNil(descriptor.predicate)
    }
    
    func test_favoritesDescriptor_filtersOnlyFavorites() throws {
        _ = createDummyTrack(title: "Track A", isFavorite: true)
        _ = createDummyTrack(title: "Track B", isFavorite: false)
        try context.save()
        
        let descriptor = sut.favoritesDescriptor()
        let favorites = try context.fetch(descriptor)
        
        XCTAssertEqual(favorites.count, 1)
        XCTAssertEqual(favorites.first?.title, "Track A")
    }
    
    // MARK: - Artist Grouping
    
    func test_groupTracksByArtist_groupsAndSortsCorrectly() {
        let t1 = Track(filePath: "/1", fileExtension: "flac", title: "Song 1", artistName: "Zola")
        let t2 = Track(filePath: "/2", fileExtension: "flac", title: "Song 2", artistName: "Abba")
        let t3 = Track(filePath: "/3", fileExtension: "flac", title: "Song 3", artistName: "Abba")
        
        let grouped = sut.groupTracksByArtist([t1, t2, t3])
        
        XCTAssertEqual(grouped.count, 2)
        XCTAssertEqual(grouped[0].name, "Abba")
        XCTAssertEqual(grouped[0].tracks.count, 2)
        XCTAssertEqual(grouped[1].name, "Zola")
        XCTAssertEqual(grouped[1].tracks.count, 1)
    }
    
    // MARK: - Playlist Operations
    
    func test_createPlaylist_insertsAndSaves() throws {
        let track = createDummyTrack(title: "Gold")
        
        let playlist = sut.createPlaylist(name: "Vibe playlist", tracks: [track], modelContext: context)
        
        XCTAssertEqual(playlist.name, "Vibe playlist")
        XCTAssertEqual(playlist.trackCount, 1)
        XCTAssertEqual(playlist.tracks.first?.title, "Gold")
        
        // Fetch to confirm persistence
        let fetched = try context.fetch(FetchDescriptor<Playlist>())
        XCTAssertEqual(fetched.count, 1)
        XCTAssertEqual(fetched.first?.name, "Vibe playlist")
    }
    
    func test_renamePlaylist_updatesNameAndModifiedDate() {
        let playlist = Playlist(name: "Old Name")
        let oldModifiedDate = playlist.dateModified
        
        sut.renamePlaylist(playlist, to: "New Name")
        
        XCTAssertEqual(playlist.name, "New Name")
        XCTAssertGreaterThanOrEqual(playlist.dateModified, oldModifiedDate)
    }
    
    func test_deletePlaylist_removesFromContext() throws {
        let playlist = Playlist(name: "Delete Me")
        context.insert(playlist)
        try context.save()
        
        sut.deletePlaylist(playlist, modelContext: context)
        try context.save()
        
        let fetched = try context.fetch(FetchDescriptor<Playlist>())
        XCTAssertTrue(fetched.isEmpty)
    }
    
    // MARK: - Library Stats
    
    func test_updateStats_recalculatesTotals() throws {
        let t1 = createDummyTrack(title: "T1", artist: "Artist A")
        let t2 = createDummyTrack(title: "T2", artist: "Artist B")
        
        // Link to Dummy Album
        let album = Album(title: "Dummy Album", artistName: "Artist A", tracks: [t1, t2])
        context.insert(album)
        t1.album = album
        t2.album = album
        
        try context.save()
        
        sut.updateStats(modelContext: context)
        
        XCTAssertEqual(sut.totalTracks, 2)
        XCTAssertEqual(sut.totalAlbums, 1)
        XCTAssertEqual(sut.totalArtists, 2)
        XCTAssertEqual(sut.totalDuration, 360) // 180 + 180
    }
    
    // MARK: - EQ Presets Seeding
    
    func test_seedEQPresetsIfNeeded_seedsEightPresets() throws {
        sut.seedEQPresetsIfNeeded(modelContext: context)
        
        let count = try context.fetchCount(FetchDescriptor<EQPreset>())
        XCTAssertEqual(count, 8)
        
        // Calling again should not create duplicates
        sut.seedEQPresetsIfNeeded(modelContext: context)
        let newCount = try context.fetchCount(FetchDescriptor<EQPreset>())
        XCTAssertEqual(newCount, 8)
    }
}
