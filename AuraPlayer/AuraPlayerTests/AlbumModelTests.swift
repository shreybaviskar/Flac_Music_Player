//
//  AlbumModelTests.swift
//  AuraPlayerTests
//
//  Unit tests for the Album model and its computed properties.
//

import XCTest
@testable import AuraPlayer

final class AlbumModelTests: XCTestCase {

    // MARK: - Helpers

    private func makeTrack(
        title: String = "Track",
        duration: TimeInterval = 180,
        sampleRate: Double = 44100,
        bitDepth: Int = 16,
        codec: AudioCodec = .flac,
        trackNumber: Int? = nil,
        discNumber: Int? = nil
    ) -> Track {
        Track(
            filePath: "/music/\(title).flac",
            fileExtension: "flac",
            title: title,
            duration: duration,
            sampleRate: sampleRate,
            bitDepth: bitDepth,
            codec: codec,
            trackNumber: trackNumber,
            discNumber: discNumber
        )
    }

    private func makeAlbum(
        title: String = "Test Album",
        artistName: String = "Test Artist",
        year: Int? = nil,
        tracks: [Track] = []
    ) -> Album {
        Album(
            title: title,
            artistName: artistName,
            year: year,
            tracks: tracks
        )
    }

    // MARK: - Empty Album

    func test_emptyAlbum_totalDuration_isZero() {
        let album = makeAlbum()
        XCTAssertEqual(album.totalDuration, 0)
    }

    func test_emptyAlbum_trackCount_isZero() {
        let album = makeAlbum()
        XCTAssertEqual(album.trackCount, 0)
    }

    func test_emptyAlbum_formattedDuration_isZeroMin() {
        let album = makeAlbum()
        XCTAssertEqual(album.formattedDuration, "0 min")
    }

    func test_emptyAlbum_isLossless_isFalse() {
        let album = makeAlbum()
        XCTAssertFalse(album.isLossless, "Empty album should not be lossless")
    }

    func test_emptyAlbum_isHiRes_isFalse() {
        let album = makeAlbum()
        XCTAssertFalse(album.isHiRes)
    }

    // MARK: - totalDuration

    func test_totalDuration_withTracks_sumsDurations() {
        let tracks = [
            makeTrack(title: "A", duration: 120),
            makeTrack(title: "B", duration: 180),
            makeTrack(title: "C", duration: 60)
        ]
        let album = makeAlbum(tracks: tracks)
        XCTAssertEqual(album.totalDuration, 360)
    }

    func test_totalDuration_singleTrack_returnsThatDuration() {
        let track = makeTrack(duration: 245)
        let album = makeAlbum(tracks: [track])
        XCTAssertEqual(album.totalDuration, 245)
    }

    // MARK: - trackCount

    func test_trackCount_multiTracks_returnsCorrectCount() {
        let tracks = [
            makeTrack(title: "A"),
            makeTrack(title: "B"),
            makeTrack(title: "C")
        ]
        let album = makeAlbum(tracks: tracks)
        XCTAssertEqual(album.trackCount, 3)
    }

    // MARK: - formattedDuration

    func test_formattedDuration_lessThan60Min_returnsMinutes() {
        // 3 tracks × 180s = 540s = 9 min
        let tracks = [
            makeTrack(title: "A", duration: 180),
            makeTrack(title: "B", duration: 180),
            makeTrack(title: "C", duration: 180)
        ]
        let album = makeAlbum(tracks: tracks)
        XCTAssertEqual(album.formattedDuration, "9 min")
    }

    func test_formattedDuration_exactly60Min_returnsHrMin() {
        let tracks = [
            makeTrack(title: "A", duration: 3600)
        ]
        let album = makeAlbum(tracks: tracks)
        XCTAssertEqual(album.formattedDuration, "1 hr 0 min")
    }

    func test_formattedDuration_moreThan60Min_returnsHrAndMin() {
        // 4500s = 75 min = 1 hr 15 min
        let tracks = [
            makeTrack(title: "A", duration: 4500)
        ]
        let album = makeAlbum(tracks: tracks)
        XCTAssertEqual(album.formattedDuration, "1 hr 15 min")
    }

    func test_formattedDuration_multiHours_formatsCorrectly() {
        // 9000s = 150 min = 2 hr 30 min
        let tracks = [
            makeTrack(title: "A", duration: 9000)
        ]
        let album = makeAlbum(tracks: tracks)
        XCTAssertEqual(album.formattedDuration, "2 hr 30 min")
    }

    // MARK: - sortedTracks

    func test_sortedTracks_sortsByDiscThenTrackNumber() {
        let t1 = makeTrack(title: "D2T1", trackNumber: 1, discNumber: 2)
        let t2 = makeTrack(title: "D1T2", trackNumber: 2, discNumber: 1)
        let t3 = makeTrack(title: "D1T1", trackNumber: 1, discNumber: 1)
        let t4 = makeTrack(title: "D2T2", trackNumber: 2, discNumber: 2)

        let album = makeAlbum(tracks: [t1, t2, t3, t4])
        let sorted = album.sortedTracks

        XCTAssertEqual(sorted[0].title, "D1T1")
        XCTAssertEqual(sorted[1].title, "D1T2")
        XCTAssertEqual(sorted[2].title, "D2T1")
        XCTAssertEqual(sorted[3].title, "D2T2")
    }

    func test_sortedTracks_nilDiscNumber_defaultsToDisc1() {
        let t1 = makeTrack(title: "No Disc", trackNumber: 2, discNumber: nil)
        let t2 = makeTrack(title: "Disc 1", trackNumber: 1, discNumber: 1)

        let album = makeAlbum(tracks: [t1, t2])
        let sorted = album.sortedTracks

        // Both have disc 1 (nil defaults to 1), so sort by track number
        XCTAssertEqual(sorted[0].title, "Disc 1")
        XCTAssertEqual(sorted[1].title, "No Disc")
    }

    func test_sortedTracks_nilTrackNumber_defaultsToZero() {
        let t1 = makeTrack(title: "No Track Num", trackNumber: nil, discNumber: 1)
        let t2 = makeTrack(title: "Track 1", trackNumber: 1, discNumber: 1)

        let album = makeAlbum(tracks: [t1, t2])
        let sorted = album.sortedTracks

        XCTAssertEqual(sorted[0].title, "No Track Num")
        XCTAssertEqual(sorted[1].title, "Track 1")
    }

    // MARK: - isHiRes

    func test_isHiRes_oneHiResTrack_returnsTrue() {
        let tracks = [
            makeTrack(title: "Standard", sampleRate: 44100, bitDepth: 16, codec: .flac),
            makeTrack(title: "HiRes", sampleRate: 96000, bitDepth: 24, codec: .flac)
        ]
        let album = makeAlbum(tracks: tracks)
        XCTAssertTrue(album.isHiRes)
    }

    func test_isHiRes_allStandardLossless_returnsFalse() {
        let tracks = [
            makeTrack(title: "A", sampleRate: 44100, bitDepth: 16, codec: .flac),
            makeTrack(title: "B", sampleRate: 44100, bitDepth: 16, codec: .flac)
        ]
        let album = makeAlbum(tracks: tracks)
        XCTAssertFalse(album.isHiRes)
    }

    func test_isHiRes_allMp3_returnsFalse() {
        let tracks = [
            makeTrack(title: "A", sampleRate: 96000, bitDepth: 24, codec: .mp3)
        ]
        let album = makeAlbum(tracks: tracks)
        XCTAssertFalse(album.isHiRes)
    }

    // MARK: - isLossless

    func test_isLossless_allFlac_returnsTrue() {
        let tracks = [
            makeTrack(title: "A", codec: .flac),
            makeTrack(title: "B", codec: .flac)
        ]
        let album = makeAlbum(tracks: tracks)
        XCTAssertTrue(album.isLossless)
    }

    func test_isLossless_mixedCodecs_returnsFalse() {
        let tracks = [
            makeTrack(title: "A", codec: .flac),
            makeTrack(title: "B", codec: .mp3)
        ]
        let album = makeAlbum(tracks: tracks)
        XCTAssertFalse(album.isLossless)
    }

    func test_isLossless_allMp3_returnsFalse() {
        let tracks = [
            makeTrack(title: "A", codec: .mp3)
        ]
        let album = makeAlbum(tracks: tracks)
        XCTAssertFalse(album.isLossless)
    }

    func test_isLossless_mixedLossless_returnsTrue() {
        let tracks = [
            makeTrack(title: "A", codec: .flac),
            makeTrack(title: "B", codec: .alac),
            makeTrack(title: "C", codec: .wav)
        ]
        let album = makeAlbum(tracks: tracks)
        XCTAssertTrue(album.isLossless)
    }

    // MARK: - subtitle

    func test_subtitle_withYear_lossless_formatsCorrectly() {
        let tracks = [
            makeTrack(title: "A", codec: .flac),
            makeTrack(title: "B", codec: .flac)
        ]
        let album = makeAlbum(year: 2023, tracks: tracks)
        XCTAssertEqual(album.subtitle, "2023 · 2 songs · Lossless")
    }

    func test_subtitle_withoutYear_lossless_formatsCorrectly() {
        let tracks = [
            makeTrack(title: "A", codec: .flac),
            makeTrack(title: "B", codec: .flac)
        ]
        let album = makeAlbum(year: nil, tracks: tracks)
        XCTAssertEqual(album.subtitle, "2 songs · Lossless")
    }

    func test_subtitle_singleSong_usesSingularForm() {
        let tracks = [makeTrack(title: "A", codec: .flac)]
        let album = makeAlbum(year: 2024, tracks: tracks)
        XCTAssertEqual(album.subtitle, "2024 · 1 song · Lossless")
    }

    func test_subtitle_hiRes_showsHiRes() {
        let tracks = [
            makeTrack(title: "A", sampleRate: 96000, bitDepth: 24, codec: .flac)
        ]
        let album = makeAlbum(year: 2024, tracks: tracks)
        XCTAssertEqual(album.subtitle, "2024 · 1 song · Hi-Res")
    }

    func test_subtitle_mp3_noQualityLabel() {
        let tracks = [
            makeTrack(title: "A", codec: .mp3),
            makeTrack(title: "B", codec: .mp3)
        ]
        let album = makeAlbum(year: 2020, tracks: tracks)
        XCTAssertEqual(album.subtitle, "2020 · 2 songs")
    }

    func test_subtitle_emptyAlbum_noYear() {
        let album = makeAlbum(year: nil)
        XCTAssertEqual(album.subtitle, "0 songs")
    }

    func test_subtitle_emptyAlbum_withYear() {
        let album = makeAlbum(year: 2023)
        XCTAssertEqual(album.subtitle, "2023 · 0 songs")
    }
}
