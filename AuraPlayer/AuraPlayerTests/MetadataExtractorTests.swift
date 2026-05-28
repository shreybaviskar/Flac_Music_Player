//
//  MetadataExtractorTests.swift
//  AuraPlayerTests
//
//  Unit tests for MetadataExtractor and ExtractedMetadata types.
//

import XCTest
import AVFoundation
@testable import AuraPlayer

final class MetadataExtractorTests: XCTestCase {
    
    private var sut: MetadataExtractor!
    
    override func setUp() {
        super.setUp()
        sut = MetadataExtractor.shared
    }
    
    override func tearDown() {
        sut = nil
        super.tearDown()
    }
    
    // MARK: - ExtractedMetadata Defaults
    
    func test_extractedMetadata_initialState_isCorrect() {
        let meta = ExtractedMetadata()
        
        XCTAssertNil(meta.title)
        XCTAssertNil(meta.artistName)
        XCTAssertNil(meta.albumTitle)
        XCTAssertNil(meta.albumArtist)
        XCTAssertNil(meta.genre)
        XCTAssertNil(meta.composer)
        XCTAssertNil(meta.year)
        XCTAssertNil(meta.trackNumber)
        XCTAssertNil(meta.trackTotal)
        XCTAssertNil(meta.discNumber)
        XCTAssertNil(meta.discTotal)
        XCTAssertNil(meta.lyrics)
        
        XCTAssertNil(meta.artworkData)
        XCTAssertEqual(meta.duration, 0)
        XCTAssertEqual(meta.sampleRate, 44100)
        XCTAssertEqual(meta.bitDepth, 16)
        XCTAssertEqual(meta.channelCount, 2)
        XCTAssertNil(meta.bitrate)
    }
    
    // MARK: - Year Parsing
    
    func test_parseYearFromDateString_pureYear() {
        XCTAssertEqual(sut.parseYearFromDateString("2023"), 2023)
        XCTAssertEqual(sut.parseYearFromDateString("1995"), 1995)
    }
    
    func test_parseYearFromDateString_isoDate() {
        XCTAssertEqual(sut.parseYearFromDateString("2023-06-15"), 2023)
        XCTAssertEqual(sut.parseYearFromDateString("2018/12/31"), 2018)
    }
    
    func test_parseYearFromDateString_isoDateTime() {
        XCTAssertEqual(sut.parseYearFromDateString("2023-06-15T08:30:00Z"), 2023)
    }
    
    func test_parseYearFromDateString_complexText() {
        XCTAssertEqual(sut.parseYearFromDateString("Released in 2004"), 2004)
        XCTAssertEqual(sut.parseYearFromDateString("Recorded: 1989"), 1989)
    }
    
    func test_parseYearFromDateString_invalidData() {
        XCTAssertNil(sut.parseYearFromDateString("Not a year"))
        XCTAssertNil(sut.parseYearFromDateString(""))
        XCTAssertNil(sut.parseYearFromDateString("12-30"))
    }
    
    // MARK: - Errors
    
    func test_metadataError_descriptions() {
        let err1 = MetadataError.cannotCreateAsset("/path/to/song.flac")
        XCTAssertTrue(err1.localizedDescription.contains("Cannot create AVAsset"))
        
        let err2 = MetadataError.noAudioTrack("/path/to/song.flac")
        XCTAssertTrue(err2.localizedDescription.contains("No audio track found"))
        
        let underlying = NSError(domain: "test", code: 404, userInfo: [NSLocalizedDescriptionKey: "File missing"])
        let err3 = MetadataError.extractionFailed("/path/to/song.flac", underlying)
        XCTAssertTrue(err3.localizedDescription.contains("Metadata extraction failed"))
        XCTAssertTrue(err3.localizedDescription.contains("File missing"))
    }
}
