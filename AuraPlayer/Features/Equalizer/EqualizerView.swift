//
//  EqualizerView.swift
//  AuraPlayer
//
//  10-band graphic equalizer with vertical sliders, preset selector,
//  and real-time visualizer bars.
//

import SwiftUI
import SwiftData

struct EqualizerView: View {
    @ObservedObject var playerVM: PlayerViewModel
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \EQPreset.name) private var allPresets: [EQPreset]
    
    @State private var showSaveSheet = false
    @State private var customPresetName = ""
    
    private let frequencyLabels = ["32", "64", "125", "250", "500", "1K", "2K", "4K", "8K", "16K"]
    
    var body: some View {
        NavigationStack {
            ZStack {
                Color.auraBackground.ignoresSafeArea()
                
                VStack(spacing: 20) {
                    // EQ Toggle + Preset selector
                    headerView
                    
                    // Visualizer bars (real-time FFT)
                    if playerVM.isVisualizerActive {
                        visualizerView
                            .frame(height: 60)
                            .padding(.horizontal)
                    }
                    
                    // EQ Band sliders
                    eqBandsView
                        .padding(.horizontal, 8)
                    
                    // Preamp slider
                    preampView
                        .padding(.horizontal, 28)
                    
                    Spacer()
                }
            }
            .navigationTitle("Equalizer")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                        .foregroundColor(.auraPrimary)
                }
            }
            .onAppear { playerVM.startVisualizer() }
            .onDisappear { playerVM.stopVisualizer() }
            .alert("Save Preset", isPresented: $showSaveSheet) {
                TextField("Preset name", text: $customPresetName)
                Button("Cancel", role: .cancel) { customPresetName = "" }
                Button("Save") {
                    if !customPresetName.isEmpty {
                        _ = playerVM.saveCustomPreset(name: customPresetName, modelContext: modelContext)
                        customPresetName = ""
                    }
                }
            }
        }
    }
    
    // MARK: - Header
    
    private var headerView: some View {
        VStack(spacing: 12) {
            // EQ enabled toggle
            HStack {
                Text("EQ")
                    .font(.auraHeadline)
                    .foregroundColor(.auraTextPrimary)
                
                Spacer()
                
                Toggle("", isOn: Binding(
                    get: { playerVM.isEQEnabled },
                    set: { _ in playerVM.toggleEQ() }
                ))
                .tint(.auraPrimary)
            }
            .padding(.horizontal)
            
            // Preset picker
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(allPresets) { preset in
                        Button {
                            playerVM.applyEQPreset(preset)
                        } label: {
                            HStack(spacing: 6) {
                                if let icon = preset.iconName {
                                    Image(systemName: icon)
                                        .font(.caption)
                                }
                                Text(preset.name)
                                    .font(.system(size: 13, weight: .medium))
                            }
                            .foregroundColor(
                                playerVM.activeEQPreset?.id == preset.id ? .white : .auraTextSecondary
                            )
                            .padding(.horizontal, 14)
                            .padding(.vertical, 8)
                            .background(
                                playerVM.activeEQPreset?.id == preset.id
                                    ? Color.auraPrimary
                                    : Color.auraSurface
                            )
                            .clipShape(Capsule())
                        }
                    }
                    
                    // Save custom button
                    Button {
                        showSaveSheet = true
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "plus")
                            Text("Save")
                        }
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(.auraPrimary)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .background(Color.auraPrimary.opacity(0.15))
                        .clipShape(Capsule())
                    }
                    
                    // Reset button
                    Button {
                        playerVM.resetEQ()
                    } label: {
                        Image(systemName: "arrow.counterclockwise")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundColor(.auraTextTertiary)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(Color.auraSurface)
                            .clipShape(Capsule())
                    }
                }
                .padding(.horizontal)
            }
        }
    }
    
    // MARK: - Visualizer Bars
    
    private var visualizerView: some View {
        HStack(spacing: 3) {
            ForEach(0..<playerVM.visualizerBars.count, id: \.self) { index in
                RoundedRectangle(cornerRadius: 2)
                    .fill(
                        LinearGradient(
                            colors: [.auraPrimary, .auraAccent],
                            startPoint: .bottom,
                            endPoint: .top
                        )
                    )
                    .frame(
                        width: nil,
                        height: max(2, CGFloat(playerVM.visualizerBars[index]) * 60)
                    )
                    .frame(maxWidth: .infinity)
                    .animation(.easeOut(duration: 0.08), value: playerVM.visualizerBars[index])
            }
        }
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.auraSurface)
        )
    }
    
    // MARK: - EQ Bands
    
    private var eqBandsView: some View {
        VStack(spacing: 0) {
            // dB labels
            HStack {
                Text("+12")
                    .font(.system(size: 9))
                    .foregroundColor(.auraTextTertiary)
                Spacer()
                Text("0 dB")
                    .font(.system(size: 9))
                    .foregroundColor(.auraTextTertiary)
                Spacer()
                Text("-12")
                    .font(.system(size: 9))
                    .foregroundColor(.auraTextTertiary)
            }
            .padding(.horizontal, 8)
            
            // Sliders
            HStack(alignment: .center, spacing: 4) {
                ForEach(0..<10, id: \.self) { index in
                    VStack(spacing: 6) {
                        // Gain label
                        Text(String(format: "%.0f", playerVM.eqGains[index]))
                            .font(.system(size: 10, weight: .medium, design: .monospaced))
                            .foregroundColor(gainColor(for: playerVM.eqGains[index]))
                            .frame(height: 16)
                        
                        // Vertical slider
                        VerticalEQSlider(
                            value: Binding(
                                get: { playerVM.eqGains[index] },
                                set: { playerVM.setEQBand(index: index, gain: $0) }
                            ),
                            range: -12...12,
                            accentColor: gainColor(for: playerVM.eqGains[index])
                        )
                        .frame(height: 180)
                        
                        // Frequency label
                        Text(frequencyLabels[index])
                            .font(.system(size: 9, weight: .medium))
                            .foregroundColor(.auraTextTertiary)
                    }
                    .frame(maxWidth: .infinity)
                }
            }
            .padding(.vertical, 12)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(Color.auraSurface)
            )
        }
    }
    
    // MARK: - Preamp
    
    private var preampView: some View {
        VStack(spacing: 6) {
            HStack {
                Text("Pre-Amp")
                    .font(.auraCaption)
                    .foregroundColor(.auraTextSecondary)
                
                Spacer()
                
                Text(String(format: "%.1f dB", playerVM.preampGain))
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .foregroundColor(.auraTextTertiary)
            }
            
            Slider(
                value: Binding(
                    get: { playerVM.preampGain },
                    set: { playerVM.setPreampGain($0) }
                ),
                in: -12...12,
                step: 0.5
            )
            .tint(.auraPrimary)
        }
    }
    
    // MARK: - Helpers
    
    private func gainColor(for gain: Float) -> Color {
        if gain > 0 { return .auraSuccess }
        if gain < 0 { return .auraPrimary }
        return .auraTextTertiary
    }
}

// MARK: - Vertical EQ Slider

struct VerticalEQSlider: View {
    @Binding var value: Float
    let range: ClosedRange<Float>
    let accentColor: Color
    
    var body: some View {
        GeometryReader { geometry in
            let height = geometry.size.height
            let normalizedValue = CGFloat((value - range.lowerBound) / (range.upperBound - range.lowerBound))
            let centerY = height / 2
            let thumbY = height * (1 - normalizedValue)
            
            ZStack {
                // Track
                RoundedRectangle(cornerRadius: 3)
                    .fill(Color.white.opacity(0.1))
                    .frame(width: 6)
                
                // Center line
                Rectangle()
                    .fill(Color.white.opacity(0.2))
                    .frame(width: 12, height: 1)
                    .position(x: geometry.size.width / 2, y: centerY)
                
                // Fill from center
                let fillTop = min(centerY, thumbY)
                let fillHeight = abs(thumbY - centerY)
                RoundedRectangle(cornerRadius: 3)
                    .fill(accentColor.opacity(0.6))
                    .frame(width: 6, height: fillHeight)
                    .position(x: geometry.size.width / 2, y: fillTop + fillHeight / 2)
                
                // Thumb
                Circle()
                    .fill(accentColor)
                    .frame(width: 16, height: 16)
                    .shadow(color: accentColor.opacity(0.4), radius: 4)
                    .position(x: geometry.size.width / 2, y: thumbY)
            }
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { gesture in
                        let normalized = 1 - Float(gesture.location.y / height)
                        let clamped = max(0, min(1, normalized))
                        value = range.lowerBound + clamped * (range.upperBound - range.lowerBound)
                    }
            )
        }
    }
}
