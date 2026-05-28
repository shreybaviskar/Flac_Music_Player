//
//  EQPresetTests.swift
//  AuraPlayerTests
//
//  Unit tests for EQFrequency, EQBand, and EQPreset models.
//

import XCTest
@testable import AuraPlayer

final class EQPresetTests: XCTestCase {

    // MARK: - EQFrequency

    func test_eqFrequency_allCases_countIsTen() {
        XCTAssertEqual(EQFrequency.allCases.count, 10)
    }

    func test_eqFrequency_rawValues_areCorrect() {
        XCTAssertEqual(EQFrequency.band32Hz.rawValue, 32.0)
        XCTAssertEqual(EQFrequency.band64Hz.rawValue, 64.0)
        XCTAssertEqual(EQFrequency.band125Hz.rawValue, 125.0)
        XCTAssertEqual(EQFrequency.band250Hz.rawValue, 250.0)
        XCTAssertEqual(EQFrequency.band500Hz.rawValue, 500.0)
        XCTAssertEqual(EQFrequency.band1kHz.rawValue, 1000.0)
        XCTAssertEqual(EQFrequency.band2kHz.rawValue, 2000.0)
        XCTAssertEqual(EQFrequency.band4kHz.rawValue, 4000.0)
        XCTAssertEqual(EQFrequency.band8kHz.rawValue, 8000.0)
        XCTAssertEqual(EQFrequency.band16kHz.rawValue, 16000.0)
    }

    func test_eqFrequency_labels_areCorrect() {
        XCTAssertEqual(EQFrequency.band32Hz.label, "32")
        XCTAssertEqual(EQFrequency.band64Hz.label, "64")
        XCTAssertEqual(EQFrequency.band125Hz.label, "125")
        XCTAssertEqual(EQFrequency.band250Hz.label, "250")
        XCTAssertEqual(EQFrequency.band500Hz.label, "500")
        XCTAssertEqual(EQFrequency.band1kHz.label, "1K")
        XCTAssertEqual(EQFrequency.band2kHz.label, "2K")
        XCTAssertEqual(EQFrequency.band4kHz.label, "4K")
        XCTAssertEqual(EQFrequency.band8kHz.label, "8K")
        XCTAssertEqual(EQFrequency.band16kHz.label, "16K")
    }

    func test_eqFrequency_labelsUseSuffix_kForKilohertz() {
        // All frequencies >= 1000 Hz should use "K" suffix
        let khzCases: [EQFrequency] = [.band1kHz, .band2kHz, .band4kHz, .band8kHz, .band16kHz]
        for freq in khzCases {
            XCTAssertTrue(freq.label.hasSuffix("K"), "\(freq) label should end with K")
        }
    }

    // MARK: - EQBand

    func test_eqBand_defaultInit_hasZeroGainAndOneBandwidth() {
        let band = EQBand(frequency: 1000.0)
        XCTAssertEqual(band.frequency, 1000.0)
        XCTAssertEqual(band.gain, 0.0)
        XCTAssertEqual(band.bandwidth, 1.0)
    }

    func test_eqBand_customInit_storesValues() {
        let band = EQBand(frequency: 32.0, gain: 5.0, bandwidth: 2.0)
        XCTAssertEqual(band.frequency, 32.0)
        XCTAssertEqual(band.gain, 5.0)
        XCTAssertEqual(band.bandwidth, 2.0)
    }

    func test_eqBand_equatable_equalBandsAreEqual() {
        let band1 = EQBand(frequency: 500.0, gain: 3.0, bandwidth: 1.0)
        let band2 = EQBand(frequency: 500.0, gain: 3.0, bandwidth: 1.0)
        XCTAssertEqual(band1, band2)
    }

    func test_eqBand_equatable_differentGainAreNotEqual() {
        let band1 = EQBand(frequency: 500.0, gain: 3.0)
        let band2 = EQBand(frequency: 500.0, gain: -3.0)
        XCTAssertNotEqual(band1, band2)
    }

    func test_eqBand_codable_roundTrip() throws {
        let original = EQBand(frequency: 4000.0, gain: -6.5, bandwidth: 1.5)
        let encoder = JSONEncoder()
        let decoder = JSONDecoder()

        let data = try encoder.encode(original)
        let decoded = try decoder.decode(EQBand.self, from: data)

        XCTAssertEqual(decoded, original)
    }

    func test_eqBand_codable_arrayRoundTrip() throws {
        let bands = EQPreset.flatBands()
        let encoder = JSONEncoder()
        let decoder = JSONDecoder()

        let data = try encoder.encode(bands)
        let decoded = try decoder.decode([EQBand].self, from: data)

        XCTAssertEqual(decoded, bands)
    }

    func test_eqBand_hashable_canBeUsedInSet() {
        let band1 = EQBand(frequency: 1000.0, gain: 0.0, bandwidth: 1.0)
        let band2 = EQBand(frequency: 1000.0, gain: 0.0, bandwidth: 1.0)
        let band3 = EQBand(frequency: 2000.0, gain: 3.0, bandwidth: 1.0)

        let set: Set<EQBand> = [band1, band2, band3]
        XCTAssertEqual(set.count, 2, "Duplicate bands should collapse in a Set")
    }

    // MARK: - flatBands

    func test_flatBands_returnsTenBands() {
        let bands = EQPreset.flatBands()
        XCTAssertEqual(bands.count, 10)
    }

    func test_flatBands_allGainsAreZero() {
        let bands = EQPreset.flatBands()
        for band in bands {
            XCTAssertEqual(band.gain, 0.0, "Flat band at \(band.frequency) Hz should have 0 gain")
        }
    }

    func test_flatBands_allBandwidthsAreOne() {
        let bands = EQPreset.flatBands()
        for band in bands {
            XCTAssertEqual(band.bandwidth, 1.0)
        }
    }

    func test_flatBands_frequenciesMatchEQFrequency() {
        let bands = EQPreset.flatBands()
        let expectedFreqs = EQFrequency.allCases.map(\.rawValue)
        let actualFreqs = bands.map(\.frequency)
        XCTAssertEqual(actualFreqs, expectedFreqs)
    }

    // MARK: - Factory Preset: Flat

    func test_flatPreset_hasTenBands() {
        let preset = EQPreset.flat()
        XCTAssertEqual(preset.bands.count, 10)
    }

    func test_flatPreset_allGainsZero() {
        let preset = EQPreset.flat()
        for band in preset.bands {
            XCTAssertEqual(band.gain, 0.0)
        }
    }

    func test_flatPreset_isBuiltIn() {
        let preset = EQPreset.flat()
        XCTAssertTrue(preset.isBuiltIn)
    }

    func test_flatPreset_nameIsFlat() {
        let preset = EQPreset.flat()
        XCTAssertEqual(preset.name, "Flat")
    }

    func test_flatPreset_preampIsZero() {
        let preset = EQPreset.flat()
        XCTAssertEqual(preset.preampGain, 0.0)
    }

    // MARK: - Factory Preset: Bass Boost

    func test_bassBoost_hasTenBands() {
        let preset = EQPreset.bassBoost()
        XCTAssertEqual(preset.bands.count, 10)
    }

    func test_bassBoost_isBuiltIn() {
        XCTAssertTrue(EQPreset.bassBoost().isBuiltIn)
    }

    func test_bassBoost_nameIsBassBoost() {
        XCTAssertEqual(EQPreset.bassBoost().name, "Bass Boost")
    }

    func test_bassBoost_lowFrequenciesAreBoosted() {
        let preset = EQPreset.bassBoost()
        // 32 Hz = 8, 64 Hz = 6, 125 Hz = 4, 250 Hz = 2
        XCTAssertEqual(preset.bands[0].gain, 8.0)
        XCTAssertEqual(preset.bands[1].gain, 6.0)
        XCTAssertEqual(preset.bands[2].gain, 4.0)
        XCTAssertEqual(preset.bands[3].gain, 2.0)
    }

    func test_bassBoost_highFrequenciesAreFlat() {
        let preset = EQPreset.bassBoost()
        // 500 Hz through 16 kHz should be 0
        for i in 4..<10 {
            XCTAssertEqual(preset.bands[i].gain, 0.0,
                           "Band at index \(i) should have 0 gain for Bass Boost")
        }
    }

    func test_bassBoost_preampIsNegative() {
        let preset = EQPreset.bassBoost()
        XCTAssertEqual(preset.preampGain, -3.0)
    }

    // MARK: - Factory Preset: Treble Boost

    func test_trebleBoost_highFrequenciesBoosted() {
        let preset = EQPreset.trebleBoost()
        XCTAssertEqual(preset.bands[6].gain, 2.0)  // 2 kHz
        XCTAssertEqual(preset.bands[7].gain, 4.0)  // 4 kHz
        XCTAssertEqual(preset.bands[8].gain, 6.0)  // 8 kHz
        XCTAssertEqual(preset.bands[9].gain, 8.0)  // 16 kHz
    }

    func test_trebleBoost_lowFrequenciesFlat() {
        let preset = EQPreset.trebleBoost()
        for i in 0..<6 {
            XCTAssertEqual(preset.bands[i].gain, 0.0)
        }
    }

    // MARK: - Factory Preset: Vocal

    func test_vocal_midFrequenciesBoosted() {
        let preset = EQPreset.vocal()
        XCTAssertEqual(preset.bands[4].gain, 3.0)  // 500 Hz
        XCTAssertEqual(preset.bands[5].gain, 5.0)  // 1 kHz
        XCTAssertEqual(preset.bands[6].gain, 5.0)  // 2 kHz
        XCTAssertEqual(preset.bands[7].gain, 3.0)  // 4 kHz
    }

    func test_vocal_lowFrequenciesCut() {
        let preset = EQPreset.vocal()
        XCTAssertEqual(preset.bands[0].gain, -2.0)  // 32 Hz
        XCTAssertEqual(preset.bands[1].gain, -1.0)  // 64 Hz
    }

    // MARK: - allFactoryPresets

    func test_allFactoryPresets_returnsEightPresets() {
        let presets = EQPreset.allFactoryPresets
        XCTAssertEqual(presets.count, 8)
    }

    func test_allFactoryPresets_allAreBuiltIn() {
        for preset in EQPreset.allFactoryPresets {
            XCTAssertTrue(preset.isBuiltIn, "\(preset.name) should be built-in")
        }
    }

    func test_allFactoryPresets_allHaveNonEmptyNames() {
        for preset in EQPreset.allFactoryPresets {
            XCTAssertFalse(preset.name.isEmpty, "Preset should have a non-empty name")
        }
    }

    func test_allFactoryPresets_allHaveTenBands() {
        for preset in EQPreset.allFactoryPresets {
            XCTAssertEqual(preset.bands.count, 10,
                           "\(preset.name) should have exactly 10 bands")
        }
    }

    func test_allFactoryPresets_allGainsInValidRange() {
        for preset in EQPreset.allFactoryPresets {
            for band in preset.bands {
                XCTAssertGreaterThanOrEqual(band.gain, -12.0,
                    "\(preset.name): gain at \(band.frequency) Hz is below -12 dB")
                XCTAssertLessThanOrEqual(band.gain, 12.0,
                    "\(preset.name): gain at \(band.frequency) Hz is above +12 dB")
            }
        }
    }

    func test_allFactoryPresets_allHaveIconNames() {
        for preset in EQPreset.allFactoryPresets {
            XCTAssertNotNil(preset.iconName,
                            "\(preset.name) should have an icon name")
            XCTAssertFalse(preset.iconName?.isEmpty ?? true,
                           "\(preset.name) icon name should not be empty")
        }
    }

    func test_allFactoryPresets_allEnabled() {
        for preset in EQPreset.allFactoryPresets {
            XCTAssertTrue(preset.isEnabled, "\(preset.name) should be enabled by default")
        }
    }

    func test_allFactoryPresets_expectedNames() {
        let names = EQPreset.allFactoryPresets.map(\.name)
        let expected = ["Flat", "Bass Boost", "Treble Boost", "Vocal",
                        "Rock", "Electronic", "Classical", "Late Night"]
        XCTAssertEqual(names, expected)
    }

    func test_allFactoryPresets_uniqueIDs() {
        let ids = EQPreset.allFactoryPresets.map(\.id)
        let uniqueIDs = Set(ids)
        XCTAssertEqual(uniqueIDs.count, ids.count, "All factory presets should have unique IDs")
    }

    // MARK: - EQPreset Initialization Defaults

    func test_eqPreset_defaultInit_useFlatBands() {
        let preset = EQPreset(name: "Custom")
        XCTAssertEqual(preset.bands.count, 10)
        for band in preset.bands {
            XCTAssertEqual(band.gain, 0.0)
        }
    }

    func test_eqPreset_defaultInit_notBuiltIn() {
        let preset = EQPreset(name: "Custom")
        XCTAssertFalse(preset.isBuiltIn)
    }

    func test_eqPreset_defaultInit_preampIsZero() {
        let preset = EQPreset(name: "Custom")
        XCTAssertEqual(preset.preampGain, 0.0)
    }

    func test_eqPreset_defaultInit_isEnabled() {
        let preset = EQPreset(name: "Custom")
        XCTAssertTrue(preset.isEnabled)
    }

    func test_eqPreset_defaultInit_iconNameIsNil() {
        let preset = EQPreset(name: "Custom")
        XCTAssertNil(preset.iconName)
    }

    // MARK: - Specific Presets: Rock

    func test_rock_characteristicGains() {
        let preset = EQPreset.rock()
        XCTAssertEqual(preset.name, "Rock")
        XCTAssertEqual(preset.bands[0].gain, 5.0)   // 32 Hz
        XCTAssertEqual(preset.bands[4].gain, -2.0)  // 500 Hz — scooped mids
        XCTAssertEqual(preset.bands[9].gain, 5.0)   // 16 kHz
    }

    // MARK: - Specific Presets: Electronic

    func test_electronic_characteristicGains() {
        let preset = EQPreset.electronic()
        XCTAssertEqual(preset.name, "Electronic")
        XCTAssertEqual(preset.bands[0].gain, 6.0)   // 32 Hz — heavy sub bass
        XCTAssertEqual(preset.bands[9].gain, 6.0)   // 16 kHz — high sparkle
    }

    // MARK: - Specific Presets: Classical

    func test_classical_characteristicGains() {
        let preset = EQPreset.classical()
        XCTAssertEqual(preset.name, "Classical")
        // Low end flat, mids cut, highs boosted
        XCTAssertEqual(preset.bands[0].gain, 0.0)
        XCTAssertEqual(preset.bands[5].gain, -2.0)  // 1 kHz
        XCTAssertEqual(preset.bands[9].gain, 4.0)   // 16 kHz
    }

    // MARK: - Specific Presets: Late Night

    func test_lateNight_allGainsPositive() {
        let preset = EQPreset.lateNight()
        XCTAssertEqual(preset.name, "Late Night")
        for band in preset.bands {
            XCTAssertGreaterThan(band.gain, 0.0,
                "Late Night band at \(band.frequency) Hz should have positive gain")
        }
    }

    func test_lateNight_preampIsNegative() {
        let preset = EQPreset.lateNight()
        XCTAssertEqual(preset.preampGain, -4.0)
    }
}
