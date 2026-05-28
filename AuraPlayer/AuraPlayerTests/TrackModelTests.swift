//
//  TrackModelTests.swift
//  AuraPlayerTests
//
//  Unit tests for the Track model and its computed properties.
//

import XCTest
@testable import AuraPlayer

final class TrackModelTests: XCTestCase {

    // MARK: - Helpers

    /// Creates a Track with sensible defaults, allowing callers to override only what they need.
    private func makeTrack(
        title: String = "Test Song",
        filePath: String = "/music/test.flac",
        fileExtension: String = "flac",
        duration: TimeInterval = 0,
        sampleRate: Double = 44100,
        bitDepth: Int = 16,
        codec: AudioCodec = .flac,
        trackNumber: Int? = nil,
        discNumber: Int? = nil
    ) -> Track {
        Track(
            filePath: filePath,
            fileExtension: fileExtension,
            title: title,
            trackNumber: trackNumber,
            discNumber: discNumber,
            duration: duration,
            sampleRate: sampleRate,
            bitDepth: bitDepth,
            codec: codec
        )
    }

    // MARK: - Initialization

    func test_init_defaultValues_areCorrect() {
        let track = Track(filePath: "/music/song.flac", fileExtension: "flac", title: "My Song")

        XCTAssertEqual(track.artistName, "Unknown Artist")
        XCTAssertEqual(track.albumTitle, "Unknown Album")
        XCTAssertNil(track.genre)
        XCTAssertNil(track.composer)
        XCTAssertNil(track.year)
        XCTAssertNil(track.trackNumber)
        XCTAssertNil(track.discNumber)
        XCTAssertNil(track.lyrics)
        XCTAssertEqual(track.duration, 0)
        XCTAssertEqual(track.sampleRate, 44100)
        XCTAssertEqual(track.bitDepth, 16)
        XCTAssertEqual(track.channelCount, 2)
        XCTAssertEqual(track.codec, .mp3)
        XCTAssertNil(track.bitrate)
        XCTAssertNil(track.artworkData)
        XCTAssertEqual(track.playCount, 0)
        XCTAssertNil(track.lastPlayedDate)
        XCTAssertFalse(track.isFavorite)
        XCTAssertEqual(track.fileSize, 0)
        XCTAssertNil(track.bookmarkData)
    }

    func test_init_customValues_areStoredCorrectly() {
        let track = Track(
            filePath: "/music/test.flac",
            fileExtension: "flac",
            fileSize: 50_000_000,
            title: "High Res Track",
            artistName: "Artist",
            albumTitle: "Album",
            genre: "Jazz",
            composer: "Composer",
            year: 2024,
            trackNumber: 3,
            discNumber: 1,
            lyrics: "La la la",
            duration: 300,
            sampleRate: 96000,
            bitDepth: 24,
            channelCount: 2,
            codec: .flac,
            bitrate: nil,
            playCount: 5,
            isFavorite: true
        )

        XCTAssertEqual(track.title, "High Res Track")
        XCTAssertEqual(track.artistName, "Artist")
        XCTAssertEqual(track.albumTitle, "Album")
        XCTAssertEqual(track.genre, "Jazz")
        XCTAssertEqual(track.composer, "Composer")
        XCTAssertEqual(track.year, 2024)
        XCTAssertEqual(track.trackNumber, 3)
        XCTAssertEqual(track.discNumber, 1)
        XCTAssertEqual(track.lyrics, "La la la")
        XCTAssertEqual(track.duration, 300)
        XCTAssertEqual(track.sampleRate, 96000)
        XCTAssertEqual(track.bitDepth, 24)
        XCTAssertEqual(track.codec, .flac)
        XCTAssertEqual(track.fileSize, 50_000_000)
        XCTAssertEqual(track.playCount, 5)
        XCTAssertTrue(track.isFavorite)
    }

    // MARK: - formattedDuration

    func test_formattedDuration_zeroSeconds_returnsZeroColon00() {
        let track = makeTrack(duration: 0)
        XCTAssertEqual(track.formattedDuration, "0:00")
    }

    func test_formattedDuration_62Seconds_returns1Colon02() {
        let track = makeTrack(duration: 62)
        XCTAssertEqual(track.formattedDuration, "1:02")
    }

    func test_formattedDuration_3661Seconds_returns61Colon01() {
        let track = makeTrack(duration: 3661)
        XCTAssertEqual(track.formattedDuration, "61:01")
    }

    func test_formattedDuration_59Seconds_returns0Colon59() {
        let track = makeTrack(duration: 59)
        XCTAssertEqual(track.formattedDuration, "0:59")
    }

    func test_formattedDuration_60Seconds_returns1Colon00() {
        let track = makeTrack(duration: 60)
        XCTAssertEqual(track.formattedDuration, "1:00")
    }

    func test_formattedDuration_singleDigitSeconds_padded() {
        let track = makeTrack(duration: 65)
        XCTAssertEqual(track.formattedDuration, "1:05")
    }

    // MARK: - qualityLabel

    func test_qualityLabel_24bit96kHzFLAC_formatsCorrectly() {
        let track = makeTrack(sampleRate: 96000, bitDepth: 24, codec: .flac)
        XCTAssertEqual(track.qualityLabel, "24-bit / 96 kHz FLAC")
    }

    func test_qualityLabel_16bit44100HzFLAC_formatsCorrectly() {
        let track = makeTrack(sampleRate: 44100, bitDepth: 16, codec: .flac)
        XCTAssertEqual(track.qualityLabel, "16-bit / 44.1 kHz FLAC")
    }

    func test_qualityLabel_16bit48kHzMP3_formatsCorrectly() {
        let track = makeTrack(sampleRate: 48000, bitDepth: 16, codec: .mp3)
        XCTAssertEqual(track.qualityLabel, "16-bit / 48 kHz MP3")
    }

    func test_qualityLabel_32bit192kHzWAV_formatsCorrectly() {
        let track = makeTrack(sampleRate: 192000, bitDepth: 32, codec: .wav)
        XCTAssertEqual(track.qualityLabel, "32-bit / 192 kHz WAV")
    }

    func test_qualityLabel_24bit88200HzALAC_formatsDecimalCorrectly() {
        let track = makeTrack(sampleRate: 88200, bitDepth: 24, codec: .alac)
        XCTAssertEqual(track.qualityLabel, "24-bit / 88.2 kHz ALAC")
    }

    // MARK: - isLossless

    func test_isLossless_flac_returnsTrue() {
        let track = makeTrack(codec: .flac)
        XCTAssertTrue(track.isLossless)
    }

    func test_isLossless_alac_returnsTrue() {
        let track = makeTrack(codec: .alac)
        XCTAssertTrue(track.isLossless)
    }

    func test_isLossless_wav_returnsTrue() {
        let track = makeTrack(codec: .wav)
        XCTAssertTrue(track.isLossless)
    }

    func test_isLossless_mp3_returnsFalse() {
        let track = makeTrack(codec: .mp3)
        XCTAssertFalse(track.isLossless)
    }

    // MARK: - isHiRes

    func test_isHiRes_losslessHighSampleRate_returnsTrue() {
        let track = makeTrack(sampleRate: 96000, bitDepth: 16, codec: .flac)
        XCTAssertTrue(track.isHiRes)
    }

    func test_isHiRes_losslessHighBitDepth_returnsTrue() {
        let track = makeTrack(sampleRate: 44100, bitDepth: 24, codec: .flac)
        XCTAssertTrue(track.isHiRes)
    }

    func test_isHiRes_losslessBothHigh_returnsTrue() {
        let track = makeTrack(sampleRate: 192000, bitDepth: 32, codec: .alac)
        XCTAssertTrue(track.isHiRes)
    }

    func test_isHiRes_losslessStandardQuality_returnsFalse() {
        let track = makeTrack(sampleRate: 44100, bitDepth: 16, codec: .flac)
        XCTAssertFalse(track.isHiRes)
    }

    func test_isHiRes_mp3HighSampleRate_returnsFalse() {
        let track = makeTrack(sampleRate: 96000, bitDepth: 24, codec: .mp3)
        XCTAssertFalse(track.isHiRes, "MP3 should never be Hi-Res even with high sample rate")
    }

    func test_isHiRes_wavHighSampleRate_returnsTrue() {
        let track = makeTrack(sampleRate: 96000, bitDepth: 24, codec: .wav)
        XCTAssertTrue(track.isHiRes)
    }

    // MARK: - qualityBadge

    func test_qualityBadge_hiRes_returnsHIRES() {
        let track = makeTrack(sampleRate: 96000, bitDepth: 24, codec: .flac)
        XCTAssertEqual(track.qualityBadge, "HI-RES")
    }

    func test_qualityBadge_losslessNotHiRes_returnsLOSSLESS() {
        let track = makeTrack(sampleRate: 44100, bitDepth: 16, codec: .flac)
        XCTAssertEqual(track.qualityBadge, "LOSSLESS")
    }

    func test_qualityBadge_mp3_returnsLOSSLESS() {
        // MP3 is not lossless or hi-res, but qualityBadge just checks isHiRes
        let track = makeTrack(codec: .mp3)
        XCTAssertEqual(track.qualityBadge, "LOSSLESS")
    }

    // MARK: - AudioCodec.from(extension:)

    func test_audioCodec_fromExtension_flac_returnsFLAC() {
        XCTAssertEqual(AudioCodec.from(extension: "flac"), .flac)
    }

    func test_audioCodec_fromExtension_FLAC_uppercase_returnsFLAC() {
        XCTAssertEqual(AudioCodec.from(extension: "FLAC"), .flac)
    }

    func test_audioCodec_fromExtension_mp3_returnsMP3() {
        XCTAssertEqual(AudioCodec.from(extension: "mp3"), .mp3)
    }

    func test_audioCodec_fromExtension_wav_returnsWAV() {
        XCTAssertEqual(AudioCodec.from(extension: "wav"), .wav)
    }

    func test_audioCodec_fromExtension_m4a_returnsALAC() {
        XCTAssertEqual(AudioCodec.from(extension: "m4a"), .alac)
    }

    func test_audioCodec_fromExtension_caf_returnsALAC() {
        XCTAssertEqual(AudioCodec.from(extension: "caf"), .alac)
    }

    func test_audioCodec_fromExtension_unknown_returnsNil() {
        XCTAssertNil(AudioCodec.from(extension: "ogg"))
    }

    func test_audioCodec_fromExtension_emptyString_returnsNil() {
        XCTAssertNil(AudioCodec.from(extension: ""))
    }

    func test_audioCodec_fromExtension_mixedCase_returnsFLAC() {
        XCTAssertEqual(AudioCodec.from(extension: "Flac"), .flac)
    }

    // MARK: - AudioCodec CaseIterable

    func test_audioCodec_allCases_containsFourCodecs() {
        XCTAssertEqual(AudioCodec.allCases.count, 4)
        XCTAssertTrue(AudioCodec.allCases.contains(.flac))
        XCTAssertTrue(AudioCodec.allCases.contains(.alac))
        XCTAssertTrue(AudioCodec.allCases.contains(.wav))
        XCTAssertTrue(AudioCodec.allCases.contains(.mp3))
    }

    // MARK: - AudioCodec rawValue

    func test_audioCodec_rawValues_areUppercase() {
        XCTAssertEqual(AudioCodec.flac.rawValue, "FLAC")
        XCTAssertEqual(AudioCodec.alac.rawValue, "ALAC")
        XCTAssertEqual(AudioCodec.wav.rawValue, "WAV")
        XCTAssertEqual(AudioCodec.mp3.rawValue, "MP3")
    }

    // MARK: - RepeatMode

    func test_repeatMode_allCases_exist() {
        // Verify all three RepeatMode cases compile and have the correct raw values
        XCTAssertEqual(RepeatMode.off.rawValue, "off")
        XCTAssertEqual(RepeatMode.all.rawValue, "all")
        XCTAssertEqual(RepeatMode.one.rawValue, "one")
    }

    func test_repeatMode_codable_roundTrip() throws {
        let encoder = JSONEncoder()
        let decoder = JSONDecoder()

        for mode in [RepeatMode.off, .all, .one] {
            let data = try encoder.encode(mode)
            let decoded = try decoder.decode(RepeatMode.self, from: data)
            XCTAssertEqual(decoded, mode)
        }
    }
}
