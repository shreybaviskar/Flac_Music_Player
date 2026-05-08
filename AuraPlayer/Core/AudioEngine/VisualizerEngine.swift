//
//  VisualizerEngine.swift
//  AuraPlayer
//
//  Real-time FFT spectrum analyzer using the Accelerate framework.
//  Consumes raw audio buffer data from AudioEngineManager's mixer tap
//  and produces frequency-domain magnitude data for the visualizer UI.
//

import Foundation
import Accelerate

// MARK: - VisualizerEngine

/// Processes raw audio samples into FFT magnitude spectrum data
/// suitable for rendering a real-time frequency visualizer.
///
/// Uses Apple's Accelerate/vDSP framework for high-performance
/// signal processing with SIMD acceleration.
@MainActor
final class VisualizerEngine: ObservableObject {
    
    static let shared = VisualizerEngine()
    
    // MARK: - Published Data
    
    /// Normalized magnitude spectrum (0.0 – 1.0) for each frequency bin.
    /// The number of bins equals `fftSize / 2`.
    @Published var magnitudes: [Float] = []
    
    /// Smoothed magnitudes with decay — better for visual display.
    @Published var smoothedMagnitudes: [Float] = []
    
    /// The number of frequency bars to display in the UI.
    @Published var barCount: Int = 32
    
    /// Aggregated bar data (barCount elements, 0.0 – 1.0).
    @Published var bars: [Float] = []
    
    /// Whether the visualizer is active.
    @Published var isActive: Bool = false
    
    // MARK: - FFT Configuration
    
    /// FFT size (must be power of 2). Higher = more frequency resolution but more latency.
    private let fftSize: Int = 2048
    
    /// Log2 of FFT size, required by vDSP.
    private let log2n: vDSP_Length
    
    /// The FFT setup object (reused across calls for performance).
    private let fftSetup: vDSP.FFT<DSPSplitComplex>
    
    // MARK: - Buffers
    
    /// Hann window to reduce spectral leakage.
    private var window: [Float]
    
    /// Decay factor for smoothing (0.0 = instant, 1.0 = no change).
    private let smoothingFactor: Float = 0.7
    
    /// Minimum dB threshold (magnitudes below this are clamped to 0).
    private let minDb: Float = -80.0
    
    /// Reference magnitude for dB conversion.
    private let referenceDb: Float = 80.0
    
    // MARK: - Init
    
    private init() {
        log2n = vDSP_Length(log2(Double(fftSize)))
        
        // Create the FFT setup.
        fftSetup = vDSP.FFT(log2n: log2n, radix: .radix2, ofType: DSPSplitComplex.self)!
        
        // Pre-compute the Hann window.
        window = [Float](repeating: 0, count: fftSize)
        vDSP_hann_window(&window, vDSP_Length(fftSize), Int32(vDSP_HANN_NORM))
        
        // Initialize bar data.
        bars = [Float](repeating: 0, count: barCount)
        smoothedMagnitudes = [Float](repeating: 0, count: fftSize / 2)
    }
    
    // MARK: - Processing
    
    /// Processes a raw audio buffer into frequency spectrum data.
    ///
    /// Called from `AudioEngineManager.onVisualizerData`.
    /// This method is optimized using Accelerate/vDSP and runs on the main thread
    /// since the buffer sizes are small (2048–4096 samples).
    func process(buffer: [Float]) {
        guard isActive, buffer.count >= fftSize else { return }
        
        // 1. Take only the first `fftSize` samples.
        var samples = Array(buffer.prefix(fftSize))
        
        // 2. Apply Hann window to reduce spectral leakage.
        vDSP_vmul(samples, 1, window, 1, &samples, 1, vDSP_Length(fftSize))
        
        // 3. Perform FFT.
        let halfN = fftSize / 2
        
        var realPart = [Float](repeating: 0, count: halfN)
        var imagPart = [Float](repeating: 0, count: halfN)
        
        realPart.withUnsafeMutableBufferPointer { realBP in
            imagPart.withUnsafeMutableBufferPointer { imagBP in
                var splitComplex = DSPSplitComplex(
                    realp: realBP.baseAddress!,
                    imagp: imagBP.baseAddress!
                )
                
                // Convert interleaved real signal to split complex.
                samples.withUnsafeBufferPointer { samplesBP in
                    samplesBP.baseAddress!.withMemoryRebound(to: DSPComplex.self, capacity: halfN) { complexPtr in
                        vDSP_ctoz(complexPtr, 2, &splitComplex, 1, vDSP_Length(halfN))
                    }
                }
                
                // Forward FFT.
                fftSetup.forward(input: splitComplex, output: &splitComplex)
            }
        }
        
        // 4. Compute magnitudes (sqrt(real² + imag²)).
        var newMagnitudes = [Float](repeating: 0, count: halfN)
        vDSP_vdist(realPart, 1, imagPart, 1, &newMagnitudes, 1, vDSP_Length(halfN))
        
        // 5. Convert to decibels.
        var one: Float = 1.0
        vDSP_vdbcon(newMagnitudes, 1, &one, &newMagnitudes, 1, vDSP_Length(halfN), 0)
        
        // 6. Normalize to 0.0 – 1.0 range.
        var normalizedMagnitudes = newMagnitudes.map { mag -> Float in
            let db = max(mag, minDb)
            return (db + referenceDb) / referenceDb
        }
        
        // Clamp to [0, 1].
        normalizedMagnitudes = normalizedMagnitudes.map { max(0, min(1, $0)) }
        
        // 7. Apply temporal smoothing (exponential moving average).
        if smoothedMagnitudes.count == halfN {
            for i in 0..<halfN {
                smoothedMagnitudes[i] = smoothingFactor * smoothedMagnitudes[i] + (1 - smoothingFactor) * normalizedMagnitudes[i]
            }
        } else {
            smoothedMagnitudes = normalizedMagnitudes
        }
        
        magnitudes = normalizedMagnitudes
        
        // 8. Aggregate into display bars (logarithmic frequency grouping).
        aggregateToBars()
    }
    
    /// Groups frequency bins into `barCount` bars using logarithmic scaling.
    /// Low frequencies get fewer bins per bar, high frequencies get more.
    /// This matches human perception of frequency (octave-based).
    private func aggregateToBars() {
        let halfN = smoothedMagnitudes.count
        guard halfN > 0 else { return }
        
        var newBars = [Float](repeating: 0, count: barCount)
        
        // Logarithmic frequency distribution.
        for i in 0..<barCount {
            let startFraction = pow(Float(i) / Float(barCount), 2.0)
            let endFraction = pow(Float(i + 1) / Float(barCount), 2.0)
            
            let startBin = Int(startFraction * Float(halfN))
            let endBin = min(Int(endFraction * Float(halfN)), halfN - 1)
            
            guard startBin <= endBin else {
                newBars[i] = 0
                continue
            }
            
            // Take the average magnitude for this range.
            var sum: Float = 0
            let count = endBin - startBin + 1
            vDSP_meanv(Array(smoothedMagnitudes[startBin...endBin]), 1, &sum, vDSP_Length(count))
            newBars[i] = sum
        }
        
        bars = newBars
    }
    
    // MARK: - Control
    
    /// Starts the visualizer. Call this when the visualizer view appears.
    func start() {
        isActive = true
        
        // Connect to the engine's visualizer tap.
        AudioEngineManager.shared.onVisualizerData = { [weak self] buffer in
            self?.process(buffer: buffer)
        }
    }
    
    /// Stops the visualizer. Call this when the visualizer view disappears.
    func stop() {
        isActive = false
        AudioEngineManager.shared.onVisualizerData = nil
        
        // Fade out bars smoothly.
        bars = [Float](repeating: 0, count: barCount)
        smoothedMagnitudes = [Float](repeating: 0, count: fftSize / 2)
    }
    
    /// Updates the number of display bars.
    func setBarCount(_ count: Int) {
        barCount = max(8, min(128, count))
        bars = [Float](repeating: 0, count: barCount)
    }
}
