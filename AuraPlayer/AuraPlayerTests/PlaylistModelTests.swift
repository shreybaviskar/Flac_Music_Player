//
//  PlaylistModelTests.swift
//  AuraPlayerTests
//
//  Unit tests for the Playlist model and its computed properties / mutating methods.
//

import XCTest
@testable import AuraPlayer

final class PlaylistModelTests: XCTestCase {

    // MARK: - Helpers

    private func makeTrack(
        id: UUID = UUID(),
        title: String = "Track",
        duration: TimeInterval = 200
    ) -> Track {
        Track(
            id: id,
            filePath: "/music/\(title).flac",
            fileExtension: "flac",
            title: title,
            duration: duration,
            codec: .flac
        )
    }

    private func makePlaylist(
        name: String = "My Playlist",
        trackOrder: [UUID] = [],
        tracks: [Track] = []
    ) -> Playlist {
        Playlist(
            name: name,
            trackOrder: trackOrder,
            tracks: tracks
        )
    }

    // MARK: - Empty Playlist

    func test_emptyPlaylist_trackCount_isZero() {
        let playlist = makePlaylist()
        XCTAssertEqual(playlist.trackCount, 0)
    }

    func test_emptyPlaylist_totalDuration_isZero() {
        let playlist = makePlaylist()
        XCTAssertEqual(playlist.totalDuration, 0)
    }

    func test_emptyPlaylist_formattedDuration_isZeroMin() {
        let playlist = makePlaylist()
        XCTAssertEqual(playlist.formattedDuration, "0 min")
    }

    func test_emptyPlaylist_orderedTracks_isEmpty() {
        let playlist = makePlaylist()
        XCTAssertTrue(playlist.orderedTracks.isEmpty)
    }

    func test_emptyPlaylist_nameIsSet() {
        let playlist = makePlaylist(name: "Chill Vibes")
        XCTAssertEqual(playlist.name, "Chill Vibes")
    }

    // MARK: - totalDuration & formattedDuration

    func test_totalDuration_sumsDurationsOfAllTracks() {
        let t1 = makeTrack(title: "A", duration: 120)
        let t2 = makeTrack(title: "B", duration: 240)
        let playlist = makePlaylist(tracks: [t1, t2])
        XCTAssertEqual(playlist.totalDuration, 360)
    }

    func test_formattedDuration_lessThan60Min_returnsMinutes() {
        // 600s = 10 min
        let t1 = makeTrack(duration: 600)
        let playlist = makePlaylist(tracks: [t1])
        XCTAssertEqual(playlist.formattedDuration, "10 min")
    }

    func test_formattedDuration_moreThan60Min_returnsHrMin() {
        // 5400s = 90 min = 1 hr 30 min
        let t1 = makeTrack(duration: 5400)
        let playlist = makePlaylist(tracks: [t1])
        XCTAssertEqual(playlist.formattedDuration, "1 hr 30 min")
    }

    // MARK: - addTrack

    func test_addTrack_addsToTracksAndTrackOrder() {
        let playlist = makePlaylist()
        let track = makeTrack(title: "New Track")

        playlist.addTrack(track)

        XCTAssertEqual(playlist.trackCount, 1)
        XCTAssertEqual(playlist.tracks.first?.title, "New Track")
        XCTAssertEqual(playlist.trackOrder.count, 1)
        XCTAssertEqual(playlist.trackOrder.first, track.id)
    }

    func test_addTrack_multipleTracks_appendsInOrder() {
        let playlist = makePlaylist()
        let t1 = makeTrack(title: "First")
        let t2 = makeTrack(title: "Second")
        let t3 = makeTrack(title: "Third")

        playlist.addTrack(t1)
        playlist.addTrack(t2)
        playlist.addTrack(t3)

        XCTAssertEqual(playlist.trackCount, 3)
        XCTAssertEqual(playlist.trackOrder, [t1.id, t2.id, t3.id])
    }

    func test_addTrack_duplicate_doesNotAddTwice() {
        let playlist = makePlaylist()
        let track = makeTrack(title: "Duplicate")

        playlist.addTrack(track)
        playlist.addTrack(track)

        XCTAssertEqual(playlist.trackCount, 1)
        XCTAssertEqual(playlist.trackOrder.count, 1)
    }

    func test_addTrack_updatesDateModified() {
        let originalDate = Date.distantPast
        let playlist = Playlist(
            name: "Test",
            dateModified: originalDate
        )
        let track = makeTrack()

        playlist.addTrack(track)

        XCTAssertGreaterThan(playlist.dateModified, originalDate)
    }

    // MARK: - removeTrack

    func test_removeTrack_removesFromTracksAndTrackOrder() {
        let track = makeTrack(title: "Remove Me")
        let playlist = makePlaylist(
            trackOrder: [track.id],
            tracks: [track]
        )

        playlist.removeTrack(track)

        XCTAssertEqual(playlist.trackCount, 0)
        XCTAssertTrue(playlist.trackOrder.isEmpty)
    }

    func test_removeTrack_onlyRemovesTargetTrack() {
        let t1 = makeTrack(title: "Keep")
        let t2 = makeTrack(title: "Remove")
        let playlist = makePlaylist(
            trackOrder: [t1.id, t2.id],
            tracks: [t1, t2]
        )

        playlist.removeTrack(t2)

        XCTAssertEqual(playlist.trackCount, 1)
        XCTAssertEqual(playlist.tracks.first?.title, "Keep")
        XCTAssertEqual(playlist.trackOrder, [t1.id])
    }

    func test_removeTrack_updatesDateModified() {
        let track = makeTrack()
        let originalDate = Date.distantPast
        let playlist = Playlist(
            name: "Test",
            trackOrder: [track.id],
            tracks: [track],
            dateModified: originalDate
        )

        playlist.removeTrack(track)

        XCTAssertGreaterThan(playlist.dateModified, originalDate)
    }

    // MARK: - orderedTracks

    func test_orderedTracks_returnsInTrackOrderSequence() {
        let t1 = makeTrack(title: "Alpha")
        let t2 = makeTrack(title: "Beta")
        let t3 = makeTrack(title: "Gamma")

        // trackOrder is reversed relative to the tracks array
        let playlist = makePlaylist(
            trackOrder: [t3.id, t1.id, t2.id],
            tracks: [t1, t2, t3]
        )

        let ordered = playlist.orderedTracks
        XCTAssertEqual(ordered.count, 3)
        XCTAssertEqual(ordered[0].title, "Gamma")
        XCTAssertEqual(ordered[1].title, "Alpha")
        XCTAssertEqual(ordered[2].title, "Beta")
    }

    func test_orderedTracks_emptyTrackOrder_returnsTracks() {
        let t1 = makeTrack(title: "A")
        let t2 = makeTrack(title: "B")
        let playlist = makePlaylist(trackOrder: [], tracks: [t1, t2])

        let ordered = playlist.orderedTracks
        XCTAssertEqual(ordered.count, 2)
    }

    func test_orderedTracks_staleID_skipsAndAppendsOrphans() {
        let t1 = makeTrack(title: "Exists")
        let t2 = makeTrack(title: "Also Exists")
        let staleID = UUID() // ID not matching any track

        let playlist = makePlaylist(
            trackOrder: [staleID, t1.id],
            tracks: [t1, t2]
        )

        let ordered = playlist.orderedTracks
        // t1 matched from trackOrder, staleID skipped, t2 appended as orphan
        XCTAssertEqual(ordered.count, 2)
        XCTAssertEqual(ordered[0].title, "Exists")
        XCTAssertEqual(ordered[1].title, "Also Exists")
    }

    // MARK: - moveTrack

    func test_moveTrack_reordersTrackOrder() {
        let id1 = UUID()
        let id2 = UUID()
        let id3 = UUID()
        let playlist = makePlaylist(trackOrder: [id1, id2, id3])

        // Move first item to end
        playlist.moveTrack(from: IndexSet(integer: 0), to: 3)

        XCTAssertEqual(playlist.trackOrder, [id2, id3, id1])
    }

    func test_moveTrack_moveLastToFront() {
        let id1 = UUID()
        let id2 = UUID()
        let id3 = UUID()
        let playlist = makePlaylist(trackOrder: [id1, id2, id3])

        // Move last item to front
        playlist.moveTrack(from: IndexSet(integer: 2), to: 0)

        XCTAssertEqual(playlist.trackOrder, [id3, id1, id2])
    }

    func test_moveTrack_updatesDateModified() {
        let id1 = UUID()
        let id2 = UUID()
        let originalDate = Date.distantPast
        let playlist = Playlist(
            name: "Test",
            trackOrder: [id1, id2],
            dateModified: originalDate
        )

        playlist.moveTrack(from: IndexSet(integer: 0), to: 2)

        XCTAssertGreaterThan(playlist.dateModified, originalDate)
    }

    // MARK: - trackCount

    func test_trackCount_reflectsTracksArrayCount() {
        let tracks = [
            makeTrack(title: "A"),
            makeTrack(title: "B"),
            makeTrack(title: "C"),
            makeTrack(title: "D"),
            makeTrack(title: "E")
        ]
        let playlist = makePlaylist(tracks: tracks)
        XCTAssertEqual(playlist.trackCount, 5)
    }

    // MARK: - Initialization Defaults

    func test_init_defaultValues_areCorrect() {
        let playlist = Playlist(name: "Fresh Playlist")

        XCTAssertEqual(playlist.name, "Fresh Playlist")
        XCTAssertNil(playlist.descriptionText)
        XCTAssertNil(playlist.artworkData)
        XCTAssertTrue(playlist.trackOrder.isEmpty)
        XCTAssertTrue(playlist.tracks.isEmpty)
    }
}
