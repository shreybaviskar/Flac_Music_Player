//
//  MetadataExtractor.swift
//  AuraPlayer
//
//  Extracts audio metadata (ID3, Vorbis comments, iTunes tags) and
//  audio format properties (sample rate, bit depth, channels) from
//  supported audio files using AVFoundation.
//

import Foundation
import AVFoundation
import UIKit

// MARK: - Extracted Metadata

/// A plain value type holding all metadata extracted from an audio file.
/// This is the output of the extractor, consumed by the LibraryViewModel
/// to create/update SwiftData `Track` entities.
struct ExtractedMetadata: Sendable {
    // -- Tags --
    var title: String?
    var artistName: String?
    var albumTitle: String?
    var albumArtist: String?
    var genre: String?
    var composer: String?
    var year: Int?
    var trackNumber: Int?
    var trackTotal: Int?
    var discNumber: Int?
    var discTotal: Int?
    var lyrics: String?
    
    // -- Artwork --
    var artworkData: Data?
    
    // -- Audio Properties --
    var duration: TimeInterval = 0
    var sampleRate: Double = 44100
    var bitDepth: Int = 16
    var channelCount: Int = 2
    var bitrate: Int?
}

// MARK: - MetadataExtractor

/// Extracts metadata and audio properties from a file URL using AVFoundation.
///
/// Supports:
/// - **MP3**: ID3v2 tags
/// - **M4A/ALAC**: iTunes/QuickTime metadata atoms
/// - **FLAC**: Vorbis comments (via AVAsset, supported since iOS 11)
/// - **WAV**: Minimal metadata (RIFF INFO chunks where available)
///
/// Audio format details (sample rate, bit depth, channel count) are extracted
/// from the `AudioStreamBasicDescription` of the first audio track, ensuring
/// bit-perfect reporting regardless of container format.
final class MetadataExtractor: Sendable {
    
    /// Shared singleton instance.
    static let shared = MetadataExtractor()
    
    private init() {}
    
    // MARK: - Public API
    
    /// Extracts all metadata from a scanned file.
    ///
    /// - Parameter scannedFile: The file to extract metadata from.
    ///   The URL must be accessible (security-scoped access must be
    ///   started by the caller if needed).
    /// - Returns: A populated `ExtractedMetadata` struct.
    func extract(from scannedFile: ScannedFile) async throws -> ExtractedMetadata {
        return try await extract(from: scannedFile.url)
    }
    
    /// Extracts all metadata from a file URL.
    ///
    /// - Parameter url: The file URL. Must be accessible.
    /// - Returns: A populated `ExtractedMetadata` struct.
    func extract(from url: URL) async throws -> ExtractedMetadata {
        let asset = AVURLAsset(url: url)
        
        var metadata = ExtractedMetadata()
        
        // Extract tags and audio properties sequentially.
        // (async let cannot be used with inout parameters in Swift.)
        try await extractTags(from: asset, into: &metadata)
        try await extractAudioProperties(from: asset, url: url, into: &metadata)
        
        return metadata
    }
    
    // MARK: - Tag Extraction
    
    /// Extracts text and artwork metadata from the AVAsset.
    ///
    /// AVAsset normalizes metadata from multiple formats (ID3, iTunes, Vorbis)
    /// into a unified API. We query both the common keyspace and format-specific
    /// keyspaces to ensure maximum coverage.
    private func extractTags(from asset: AVURLAsset, into metadata: inout ExtractedMetadata) async throws {
        
        // Load all metadata items from the asset.
        let metadataItems = try await asset.load(.metadata)
        
        // Also try format-specific metadata for broader coverage.
        let commonItems = AVMetadataItem.metadataItems(from: metadataItems, filteredByIdentifier: .commonIdentifierTitle)
        _ = commonItems // We'll iterate all items below anyway.
        
        for item in metadataItems {
            
            // Attempt to match by common key first (works across all formats).
            if let commonKey = item.commonKey {
                await extractCommonKey(commonKey, from: item, into: &metadata)
                continue
            }
            
            // Fall back to identifier-based matching for format-specific keys.
            if let identifier = item.identifier {
                await extractByIdentifier(identifier, from: item, into: &metadata)
            }
        }
    }
    
    /// Handles common (cross-format) metadata keys.
    private func extractCommonKey(
        _ key: AVMetadataKey,
        from item: AVMetadataItem,
        into metadata: inout ExtractedMetadata
    ) async {
        switch key {
        case .commonKeyTitle:
            metadata.title = await loadStringValue(from: item)
            
        case .commonKeyArtist:
            metadata.artistName = await loadStringValue(from: item)
            
        case .commonKeyAlbumName:
            metadata.albumTitle = await loadStringValue(from: item)
            
        case .commonKeyType:
            metadata.genre = await loadStringValue(from: item)
            
        case .commonKeyCreator:
            metadata.composer = await loadStringValue(from: item)
            
        case .commonKeyArtwork:
            metadata.artworkData = await loadDataValue(from: item)
            
        default:
            break
        }
    }
    
    /// Handles format-specific metadata identifiers.
    private func extractByIdentifier(
        _ identifier: AVMetadataIdentifier,
        from item: AVMetadataItem,
        into metadata: inout ExtractedMetadata
    ) async {
        
        switch identifier {
            
        // --- ID3 (MP3) ---
        case .id3MetadataTrackNumber:
            metadata.trackNumber = await extractTrackOrDiscNumber(from: item).number
            metadata.trackTotal = await extractTrackOrDiscNumber(from: item).total
            
        case .id3MetadataPartOfASet:
            metadata.discNumber = await extractTrackOrDiscNumber(from: item).number
            metadata.discTotal = await extractTrackOrDiscNumber(from: item).total
            
        case .id3MetadataYear:
            metadata.year = await loadIntValue(from: item)
            
        case .id3MetadataRecordingTime:
            // ID3v2.4 uses TDRC instead of TYER
            if let dateStr = await loadStringValue(from: item) {
                metadata.year = parseYearFromDateString(dateStr)
            }
            
        case .id3MetadataContentType:
            metadata.genre = await cleanID3Genre(from: item)
            
        case .id3MetadataComposer:
            metadata.composer = await loadStringValue(from: item)
            
        case .id3MetadataUnsynchronizedLyric:
            metadata.lyrics = await loadStringValue(from: item)
            
        case .id3MetadataBand:
            // TPE2 = "Album Artist" in ID3
            metadata.albumArtist = await loadStringValue(from: item)
            
        case .id3MetadataAttachedPicture:
            if metadata.artworkData == nil {
                metadata.artworkData = await loadDataValue(from: item)
            }
            
        // --- iTunes / QuickTime (M4A, ALAC) ---
        case .iTunesMetadataTrackNumber:
            metadata.trackNumber = await loadIntValue(from: item)
            
        case .iTunesMetadataDiscNumber:
            metadata.discNumber = await loadIntValue(from: item)
            
        case .iTunesMetadataAlbumArtist:
            metadata.albumArtist = await loadStringValue(from: item)
            
        case .iTunesMetadataComposer:
            metadata.composer = await loadStringValue(from: item)
            
        case .iTunesMetadataLyrics:
            metadata.lyrics = await loadStringValue(from: item)
            
        case .iTunesMetadataCoverArt:
            if metadata.artworkData == nil {
                metadata.artworkData = await loadDataValue(from: item)
            }
            
        case .quickTimeMetadataYear:
            if let dateStr = await loadStringValue(from: item) {
                metadata.year = parseYearFromDateString(dateStr)
            }
            
        case .quickTimeMetadataGenre:
            metadata.genre = await loadStringValue(from: item)
            
        default:
            // Handle any format-specific keys we don't explicitly map.
            // This catches Vorbis comment fields in FLAC files that may
            // not have common key mappings.
            await extractFallbackVorbis(identifier: identifier, from: item, into: &metadata)
        }
    }
    
    /// Attempts to extract Vorbis comment fields from FLAC files.
    /// AVAsset maps Vorbis comments to identifiers that may not match
    /// the standard ID3/iTunes identifiers, so we check key strings.
    private func extractFallbackVorbis(
        identifier: AVMetadataIdentifier,
        from item: AVMetadataItem,
        into metadata: inout ExtractedMetadata
    ) async {
        let key = identifier.rawValue.uppercased()
        
        if key.contains("TRACKNUMBER"), metadata.trackNumber == nil {
            metadata.trackNumber = await loadIntValue(from: item)
        } else if key.contains("DISCNUMBER"), metadata.discNumber == nil {
            metadata.discNumber = await loadIntValue(from: item)
        } else if key.contains("DATE") || key.contains("YEAR"), metadata.year == nil {
            if let dateStr = await loadStringValue(from: item) {
                metadata.year = parseYearFromDateString(dateStr)
            }
        } else if key.contains("GENRE"), metadata.genre == nil {
            metadata.genre = await loadStringValue(from: item)
        } else if key.contains("ALBUMARTIST"), metadata.albumArtist == nil {
            metadata.albumArtist = await loadStringValue(from: item)
        } else if key.contains("COMPOSER"), metadata.composer == nil {
            metadata.composer = await loadStringValue(from: item)
        } else if key.contains("LYRICS"), metadata.lyrics == nil {
            metadata.lyrics = await loadStringValue(from: item)
        }
    }
    
    // MARK: - Audio Property Extraction
    
    /// Extracts audio format properties: duration, sample rate, bit depth,
    /// channel count, and bitrate.
    ///
    /// We use two approaches:
    /// 1. `AVAudioFile` — gives us the processing format's ASBD directly.
    /// 2. `AVAssetTrack` format descriptions — for formats where AVAudioFile
    ///    may not work (e.g., some FLAC containers).
    private func extractAudioProperties(
        from asset: AVURLAsset,
        url: URL,
        into metadata: inout ExtractedMetadata
    ) async throws {
        
        // Duration from AVAsset (most reliable).
        let duration = try await asset.load(.duration)
        metadata.duration = CMTimeGetSeconds(duration)
        
        // Try AVAudioFile first — it gives the most accurate ASBD.
        if let audioFile = try? AVAudioFile(forReading: url) {
            let format = audioFile.processingFormat
            metadata.sampleRate = format.sampleRate
            metadata.channelCount = Int(format.channelCount)
            
            // Bit depth from the file format (not the processing format,
            // which is always 32-bit float).
            let fileFormat = audioFile.fileFormat
            metadata.bitDepth = Int(fileFormat.settings[AVLinearPCMBitDepthKey] as? Int ?? 16)
            
            // For lossless formats, the bit depth may be in the stream description.
            let asbd = fileFormat.streamDescription.pointee
            if asbd.mBitsPerChannel > 0 {
                metadata.bitDepth = Int(asbd.mBitsPerChannel)
            }
            
            // Calculate bitrate for the file.
            let fileSize = (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int64) ?? 0
            if metadata.duration > 0 && fileSize > 0 {
                metadata.bitrate = Int(Double(fileSize * 8) / metadata.duration / 1000.0)
            }
            
            return
        }
        
        // Fallback: Use AVAssetTrack format descriptions.
        let tracks = try await asset.loadTracks(withMediaType: .audio)
        if let audioTrack = tracks.first {
            let descriptions = try await audioTrack.load(.formatDescriptions)
            if let formatDesc = descriptions.first {
                let asbd = CMAudioFormatDescriptionGetStreamBasicDescription(formatDesc)?.pointee
                if let asbd {
                    metadata.sampleRate = asbd.mSampleRate
                    metadata.channelCount = Int(asbd.mChannelsPerFrame)
                    
                    if asbd.mBitsPerChannel > 0 {
                        metadata.bitDepth = Int(asbd.mBitsPerChannel)
                    }
                }
            }
            
            // Estimated bitrate from the track.
            let estimatedRate = try await audioTrack.load(.estimatedDataRate)
            if estimatedRate > 0 {
                metadata.bitrate = Int(estimatedRate / 1000.0)
            }
        }
    }
    
    // MARK: - Value Loading Helpers
    
    /// Loads a string value from a metadata item using the modern async API.
    private func loadStringValue(from item: AVMetadataItem) async -> String? {
        if let value = try? await item.load(.stringValue), !value.isEmpty {
            return value.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return nil
    }
    
    /// Loads an integer value from a metadata item.
    private func loadIntValue(from item: AVMetadataItem) async -> Int? {
        // Try direct number value first.
        if let number = try? await item.load(.numberValue) {
            return number.intValue
        }
        // Fall back to parsing the string value.
        if let str = try? await item.load(.stringValue), let val = Int(str) {
            return val
        }
        return nil
    }
    
    /// Loads raw data from a metadata item (used for artwork).
    private func loadDataValue(from item: AVMetadataItem) async -> Data? {
        if let data = try? await item.load(.dataValue) {
            return data
        }
        // Some artwork items expose their value as a UIImage-compatible object.
        if let value = try? await item.load(.value) {
            if let data = value as? Data { return data }
            if let image = value as? UIImage { return image.jpegData(compressionQuality: 0.9) }
        }
        return nil
    }
    
    // MARK: - Track / Disc Number Parsing
    
    /// Parses "X/Y" format used by ID3 TRCK and TPOS frames.
    /// e.g. "3/12" → (number: 3, total: 12)
    private func extractTrackOrDiscNumber(from item: AVMetadataItem) async -> (number: Int?, total: Int?) {
        if let str = try? await item.load(.stringValue) {
            let parts = str.split(separator: "/")
            let number = parts.first.flatMap { Int($0) }
            let total = parts.count > 1 ? Int(parts[1]) : nil
            return (number, total)
        }
        if let number = try? await item.load(.numberValue) {
            return (number.intValue, nil)
        }
        return (nil, nil)
    }
    
    // MARK: - Genre Cleaning
    
    /// Cleans up ID3 genre strings that use the numeric "(XX)" format.
    /// e.g. "(17)" → "Rock", "(255)Custom" → "Custom"
    func cleanID3Genre(from item: AVMetadataItem) async -> String? {
        guard let raw = await loadStringValue(from: item) else { return nil }
        
        // If the genre is a pure numeric reference like "(17)", map it.
        // Most modern taggers write the text, but legacy files may use numbers.
        if raw.hasPrefix("("), let endParen = raw.firstIndex(of: ")") {
            let numberStr = raw[raw.index(after: raw.startIndex)..<endParen]
            let suffix = raw[raw.index(after: endParen)...]
            
            // If there's text after the parentheses, use that.
            if !suffix.isEmpty {
                return String(suffix).trimmingCharacters(in: .whitespacesAndNewlines)
            }
            
            // Otherwise map the numeric genre ID to a name.
            if let genreID = Int(numberStr) {
                return Self.id3GenreNames[safe: genreID]
            }
        }
        
        return raw
    }
    
    // MARK: - Year Parsing
    
    /// Extracts a 4-digit year from various date string formats.
    /// Handles: "2023", "2023-06-15", "2023-06-15T00:00:00Z", etc.
    func parseYearFromDateString(_ dateStr: String) -> Int? {
        // Try direct 4-digit parse first.
        if dateStr.count == 4, let year = Int(dateStr) {
            return year
        }
        // Extract the first 4-digit sequence.
        let pattern = #"(\d{4})"#
        if let range = dateStr.range(of: pattern, options: .regularExpression) {
            return Int(dateStr[range])
        }
        return nil
    }
    
    // MARK: - ID3 Genre Name Table
    
    /// Standard ID3v1 genre names (indices 0–191).
    /// Used to decode numeric genre references in legacy MP3 files.
    private static let id3GenreNames: [String] = [
        "Blues", "Classic Rock", "Country", "Dance", "Disco", "Funk", "Grunge",
        "Hip-Hop", "Jazz", "Metal", "New Age", "Oldies", "Other", "Pop", "R&B",
        "Rap", "Reggae", "Rock", "Techno", "Industrial", "Alternative", "Ska",
        "Death Metal", "Pranks", "Soundtrack", "Euro-Techno", "Ambient",
        "Trip-Hop", "Vocal", "Jazz+Funk", "Fusion", "Trance", "Classical",
        "Instrumental", "Acid", "House", "Game", "Sound Clip", "Gospel",
        "Noise", "AlternRock", "Bass", "Soul", "Punk", "Space", "Meditative",
        "Instrumental Pop", "Instrumental Rock", "Ethnic", "Gothic", "Darkwave",
        "Techno-Industrial", "Electronic", "Pop-Folk", "Eurodance", "Dream",
        "Southern Rock", "Comedy", "Cult", "Gangsta", "Top 40", "Christian Rap",
        "Pop/Funk", "Jungle", "Native American", "Cabaret", "New Wave",
        "Psychedelic", "Rave", "Showtunes", "Trailer", "Lo-Fi", "Tribal",
        "Acid Punk", "Acid Jazz", "Polka", "Retro", "Musical", "Rock & Roll",
        "Hard Rock", "Folk", "Folk-Rock", "National Folk", "Swing", "Fast Fusion",
        "Bebop", "Latin", "Revival", "Celtic", "Bluegrass", "Avantgarde",
        "Gothic Rock", "Progressive Rock", "Psychedelic Rock", "Symphonic Rock",
        "Slow Rock", "Big Band", "Chorus", "Easy Listening", "Acoustic",
        "Humour", "Speech", "Chanson", "Opera", "Chamber Music", "Sonata",
        "Symphony", "Booty Bass", "Primus", "Porn Groove", "Satire",
        "Slow Jam", "Club", "Tango", "Samba", "Folklore", "Ballad",
        "Power Ballad", "Rhythmic Soul", "Freestyle", "Duet", "Punk Rock",
        "Drum Solo", "A capella", "Euro-House", "Dance Hall", "Goa",
        "Drum & Bass", "Club-House", "Hardcore Techno", "Terror", "Indie",
        "BritPop", "Negerpunk", "Polsk Punk", "Beat", "Christian Gangsta Rap",
        "Heavy Metal", "Black Metal", "Crossover", "Contemporary Christian",
        "Christian Rock", "Merengue", "Salsa", "Thrash Metal", "Anime",
        "JPop", "Synthpop", "Abstract", "Art Rock", "Baroque", "Bhangra",
        "Big Beat", "Breakbeat", "Chillout", "Downtempo", "Dub", "EBM",
        "Eclectic", "Electro", "Electroclash", "Emo", "Experimental",
        "Garage", "Global", "IDM", "Illbient", "Industro-Goth", "Jam Band",
        "Krautrock", "Leftfield", "Lounge", "Math Rock", "New Romantic",
        "Nu-Breakz", "Post-Punk", "Post-Rock", "Psytrance", "Shoegaze",
        "Space Rock", "Trop Rock", "World Music", "Neoclassical", "Audiobook",
        "Audio Theatre", "Neue Deutsche Welle", "Podcast", "Indie Rock",
        "G-Funk", "Dubstep", "Garage Rock", "Psybient"
    ]
}

// MARK: - Safe Array Subscript

private extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}

// MARK: - Metadata Extraction Errors

enum MetadataError: LocalizedError {
    case cannotCreateAsset(String)
    case noAudioTrack(String)
    case extractionFailed(String, Error)
    
    var errorDescription: String? {
        switch self {
        case .cannotCreateAsset(let path):
            return "Cannot create AVAsset for: \(path)"
        case .noAudioTrack(let path):
            return "No audio track found in: \(path)"
        case .extractionFailed(let path, let error):
            return "Metadata extraction failed for \(path): \(error.localizedDescription)"
        }
    }
}
