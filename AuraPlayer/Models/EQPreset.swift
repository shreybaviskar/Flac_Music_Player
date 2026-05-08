//
//  EQPreset.swift
//  AuraPlayer
//
//  SwiftData entity representing a 10-band graphic equalizer preset.
//

import Foundation
import SwiftData

/// The 10 standard ISO center frequencies (in Hz) for a graphic EQ.
/// These match the industry-standard bands used in most professional
/// and consumer audio equipment.
enum EQFrequency: Double, Codable, CaseIterable {
    case band32Hz   = 32.0
    case band64Hz   = 64.0
    case band125Hz  = 125.0
    case band250Hz  = 250.0
    case band500Hz  = 500.0
    case band1kHz   = 1000.0
    case band2kHz   = 2000.0
    case band4kHz   = 4000.0
    case band8kHz   = 8000.0
    case band16kHz  = 16000.0
    
    /// Human-readable label for display.
    var label: String {
        switch self {
        case .band32Hz:  return "32"
        case .band64Hz:  return "64"
        case .band125Hz: return "125"
        case .band250Hz: return "250"
        case .band500Hz: return "500"
        case .band1kHz:  return "1K"
        case .band2kHz:  return "2K"
        case .band4kHz:  return "4K"
        case .band8kHz:  return "8K"
        case .band16kHz: return "16K"
        }
    }
}

/// A single EQ band's configuration.
/// Stored as part of the `EQPreset` model.
struct EQBand: Codable, Equatable, Hashable {
    /// Center frequency in Hz.
    var frequency: Double
    
    /// Gain in decibels. Range: -12 dB to +12 dB.
    var gain: Float
    
    /// Bandwidth in octaves. Default 1.0 for a standard graphic EQ.
    var bandwidth: Float
    
    init(frequency: Double, gain: Float = 0.0, bandwidth: Float = 1.0) {
        self.frequency = frequency
        self.gain = gain
        self.bandwidth = bandwidth
    }
}

@Model
final class EQPreset {
    
    // MARK: - Identity
    
    @Attribute(.unique)
    var id: UUID
    
    // MARK: - Metadata
    
    /// Display name (e.g. "Flat", "Bass Boost", "Vocal", custom name).
    var name: String
    
    /// Whether this is a built-in (factory) preset that cannot be deleted.
    var isBuiltIn: Bool
    
    /// Optional icon name (SF Symbol) for the preset.
    var iconName: String?
    
    // MARK: - EQ Configuration
    
    /// The 10 EQ bands with their gain values.
    /// Encoded as JSON via `Codable` conformance.
    var bands: [EQBand]
    
    /// Pre-amp gain in dB. Range: -12 dB to +12 dB.
    /// Applied before the EQ bands to prevent clipping.
    var preampGain: Float
    
    // MARK: - State
    
    /// Whether EQ processing is enabled when this preset is active.
    var isEnabled: Bool
    
    /// Timestamp of last modification.
    var dateModified: Date
    
    // MARK: - Initializer
    
    init(
        id: UUID = UUID(),
        name: String,
        isBuiltIn: Bool = false,
        iconName: String? = nil,
        bands: [EQBand]? = nil,
        preampGain: Float = 0.0,
        isEnabled: Bool = true,
        dateModified: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.isBuiltIn = isBuiltIn
        self.iconName = iconName
        self.bands = bands ?? EQPreset.flatBands()
        self.preampGain = preampGain
        self.isEnabled = isEnabled
        self.dateModified = dateModified
    }
}

// MARK: - Factory Presets

extension EQPreset {
    
    /// Returns a flat (zero-gain) band configuration for all 10 frequencies.
    static func flatBands() -> [EQBand] {
        EQFrequency.allCases.map { freq in
            EQBand(frequency: freq.rawValue, gain: 0.0, bandwidth: 1.0)
        }
    }
    
    /// Factory preset: Flat (no EQ processing).
    static func flat() -> EQPreset {
        EQPreset(
            name: "Flat",
            isBuiltIn: true,
            iconName: "waveform.path",
            bands: flatBands(),
            preampGain: 0.0
        )
    }
    
    /// Factory preset: Bass Boost.
    static func bassBoost() -> EQPreset {
        var bands = flatBands()
        bands[0].gain = 8.0   // 32 Hz
        bands[1].gain = 6.0   // 64 Hz
        bands[2].gain = 4.0   // 125 Hz
        bands[3].gain = 2.0   // 250 Hz
        bands[4].gain = 0.0   // 500 Hz
        
        return EQPreset(
            name: "Bass Boost",
            isBuiltIn: true,
            iconName: "speaker.wave.3.fill",
            bands: bands,
            preampGain: -3.0
        )
    }
    
    /// Factory preset: Treble Boost.
    static func trebleBoost() -> EQPreset {
        var bands = flatBands()
        bands[6].gain = 2.0   // 2 kHz
        bands[7].gain = 4.0   // 4 kHz
        bands[8].gain = 6.0   // 8 kHz
        bands[9].gain = 8.0   // 16 kHz
        
        return EQPreset(
            name: "Treble Boost",
            isBuiltIn: true,
            iconName: "waveform.badge.plus",
            bands: bands,
            preampGain: -3.0
        )
    }
    
    /// Factory preset: Vocal.
    static func vocal() -> EQPreset {
        var bands = flatBands()
        bands[0].gain = -2.0  // 32 Hz
        bands[1].gain = -1.0  // 64 Hz
        bands[4].gain = 3.0   // 500 Hz
        bands[5].gain = 5.0   // 1 kHz
        bands[6].gain = 5.0   // 2 kHz
        bands[7].gain = 3.0   // 4 kHz
        bands[8].gain = 1.0   // 8 kHz
        
        return EQPreset(
            name: "Vocal",
            isBuiltIn: true,
            iconName: "mic.fill",
            bands: bands,
            preampGain: -2.0
        )
    }
    
    /// Factory preset: Rock.
    static func rock() -> EQPreset {
        var bands = flatBands()
        bands[0].gain = 5.0   // 32 Hz
        bands[1].gain = 4.0   // 64 Hz
        bands[2].gain = 2.0   // 125 Hz
        bands[3].gain = -1.0  // 250 Hz
        bands[4].gain = -2.0  // 500 Hz
        bands[5].gain = 1.0   // 1 kHz
        bands[6].gain = 3.0   // 2 kHz
        bands[7].gain = 4.0   // 4 kHz
        bands[8].gain = 5.0   // 8 kHz
        bands[9].gain = 5.0   // 16 kHz
        
        return EQPreset(
            name: "Rock",
            isBuiltIn: true,
            iconName: "guitars.fill",
            bands: bands,
            preampGain: -2.0
        )
    }
    
    /// Factory preset: Electronic.
    static func electronic() -> EQPreset {
        var bands = flatBands()
        bands[0].gain = 6.0   // 32 Hz
        bands[1].gain = 5.0   // 64 Hz
        bands[2].gain = 2.0   // 125 Hz
        bands[3].gain = 0.0   // 250 Hz
        bands[4].gain = -2.0  // 500 Hz
        bands[5].gain = 1.0   // 1 kHz
        bands[6].gain = 0.0   // 2 kHz
        bands[7].gain = 2.0   // 4 kHz
        bands[8].gain = 5.0   // 8 kHz
        bands[9].gain = 6.0   // 16 kHz
        
        return EQPreset(
            name: "Electronic",
            isBuiltIn: true,
            iconName: "dial.medium.fill",
            bands: bands,
            preampGain: -3.0
        )
    }
    
    /// Factory preset: Classical.
    static func classical() -> EQPreset {
        var bands = flatBands()
        bands[0].gain = 0.0   // 32 Hz
        bands[1].gain = 0.0   // 64 Hz
        bands[2].gain = 0.0   // 125 Hz
        bands[3].gain = 0.0   // 250 Hz
        bands[4].gain = 0.0   // 500 Hz
        bands[5].gain = -2.0  // 1 kHz
        bands[6].gain = -2.0  // 2 kHz
        bands[7].gain = -2.0  // 4 kHz
        bands[8].gain = 2.0   // 8 kHz
        bands[9].gain = 4.0   // 16 kHz
        
        return EQPreset(
            name: "Classical",
            isBuiltIn: true,
            iconName: "music.note.list",
            bands: bands,
            preampGain: -1.0
        )
    }
    
    /// Factory preset: Late Night (compression — boosts quiet, reduces loud).
    static func lateNight() -> EQPreset {
        var bands = flatBands()
        bands[0].gain = 3.0   // 32 Hz
        bands[1].gain = 3.0   // 64 Hz
        bands[2].gain = 2.0   // 125 Hz
        bands[3].gain = 1.0   // 250 Hz
        bands[4].gain = 1.0   // 500 Hz
        bands[5].gain = 2.0   // 1 kHz
        bands[6].gain = 3.0   // 2 kHz
        bands[7].gain = 3.0   // 4 kHz
        bands[8].gain = 3.0   // 8 kHz
        bands[9].gain = 3.0   // 16 kHz
        
        return EQPreset(
            name: "Late Night",
            isBuiltIn: true,
            iconName: "moon.fill",
            bands: bands,
            preampGain: -4.0
        )
    }
    
    /// All factory presets, in display order.
    static var allFactoryPresets: [EQPreset] {
        [
            .flat(),
            .bassBoost(),
            .trebleBoost(),
            .vocal(),
            .rock(),
            .electronic(),
            .classical(),
            .lateNight()
        ]
    }
}
