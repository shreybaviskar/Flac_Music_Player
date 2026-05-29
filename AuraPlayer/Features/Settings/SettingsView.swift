//
//  SettingsView.swift
//  AuraPlayer
//
//  App settings: audio output info, library statistics, about section.
//

import SwiftUI
import SwiftData

struct SettingsView: View {
    @ObservedObject var libraryVM: LibraryViewModel
    @ObservedObject var playerVM: PlayerViewModel
    @Environment(\.modelContext) private var modelContext
    
    var body: some View {
        NavigationStack {
            List {
                // Audio Output section
                audioOutputSection
                
                // Library Stats section
                libraryStatsSection
                
                // Playback section
                playbackSection
                
                // About section
                aboutSection
            }
            .listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)
            .background(Color.auraBackground)
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.large)
        }
    }
    
    // MARK: - Audio Output
    
    private var audioOutputSection: some View {
        Section {
            HStack {
                Label {
                    Text("Output Device")
                } icon: {
                    Image(systemName: outputIcon)
                        .foregroundColor(.auraPrimary)
                }
                Spacer()
                Text(playerVM.outputRoute.portName)
                    .font(.auraCaption)
                    .foregroundColor(.auraTextSecondary)
            }
            .listRowBackground(Color.auraSurface)
            
            HStack {
                Label {
                    Text("Sample Rate")
                } icon: {
                    Image(systemName: "waveform")
                        .foregroundColor(.auraSuccess)
                }
                Spacer()
                Text(formattedSessionSampleRate)
                    .font(.auraCaption)
                    .foregroundColor(.auraTextSecondary)
            }
            .listRowBackground(Color.auraSurface)
            
            if playerVM.outputRoute.isExternalDAC {
                HStack {
                    Label {
                        Text("DAC Status")
                    } icon: {
                        Image(systemName: "checkmark.seal.fill")
                            .foregroundColor(.auraSuccess)
                    }
                    Spacer()
                    Text("Connected · Bit-Perfect")
                        .font(.auraTiny)
                        .foregroundColor(.auraSuccess)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(Color.auraSuccess.opacity(0.15))
                        .clipShape(Capsule())
                }
                .listRowBackground(Color.auraSurface)
            }
        } header: {
            Label("Audio Output", systemImage: "hifispeaker.fill")
                .font(.system(size: 13, weight: .bold))
                .foregroundColor(.auraTextSecondary)
        }
    }
    
    // MARK: - Library Stats
    
    private var libraryStatsSection: some View {
        Section {
            statRow(icon: "music.note", label: "Songs", value: "\(libraryVM.totalTracks)")
            statRow(icon: "square.stack", label: "Albums", value: "\(libraryVM.totalAlbums)")
            statRow(icon: "music.mic", label: "Artists", value: "\(libraryVM.totalArtists)")
            statRow(icon: "clock", label: "Total Duration", value: libraryVM.formattedTotalDuration)
        } header: {
            Label("Library", systemImage: "books.vertical.fill")
                .font(.system(size: 13, weight: .bold))
                .foregroundColor(.auraTextSecondary)
        }
    }
    
    // MARK: - Playback
    
    private var playbackSection: some View {
        Section {
            HStack {
                Label {
                    Text("Shuffle")
                } icon: {
                    Image(systemName: "shuffle")
                        .foregroundColor(.auraAccent)
                }
                Spacer()
                Toggle("", isOn: shuffleToggleBinding)
                    .labelsHidden()
                    .tint(.auraAccent)
            }
            .listRowBackground(Color.auraSurface)

            // Shuffle Mode picker
            HStack {
                Label {
                    Text("Shuffle Mode")
                } icon: {
                    Image(systemName: "shuffle")
                        .foregroundColor(.auraAccent)
                }
                
                Spacer()
                
                Menu {
                    ForEach(ShuffleMode.allCases) { mode in
                        Button {
                            playerVM.setShuffleMode(mode)
                        } label: {
                            HStack {
                                Image(systemName: mode.iconName)
                                Text(mode.rawValue)
                                if playerVM.isShuffleEnabled && playerVM.shuffleMode == mode {
                                    Image(systemName: "checkmark")
                                }
                            }
                        }
                    }
                } label: {
                    HStack(spacing: 4) {
                        Text(playerVM.shuffleMode.rawValue)
                            .font(.auraCaption)
                        Image(systemName: "chevron.up.chevron.down")
                            .font(.system(size: 10))
                    }
                    .foregroundColor(playerVM.isShuffleEnabled ? .auraTextSecondary : .auraTextTertiary)
                }
                .disabled(!playerVM.isShuffleEnabled)
            }
            .listRowBackground(Color.auraSurface)
        } header: {
            Label("Playback", systemImage: "play.circle.fill")
                .font(.system(size: 13, weight: .bold))
                .foregroundColor(.auraTextSecondary)
        }
    }
    
    // MARK: - About
    
    private var aboutSection: some View {
        Section {
            HStack {
                Label {
                    Text("Version")
                } icon: {
                    Image(systemName: "info.circle")
                        .foregroundColor(.auraTextTertiary)
                }
                Spacer()
                Text(appVersionDisplay)
                    .font(.auraCaption)
                    .foregroundColor(.auraTextTertiary)
            }
            .listRowBackground(Color.auraSurface)
            
            HStack {
                Label {
                    Text("Supported Formats")
                } icon: {
                    Image(systemName: "doc.text")
                        .foregroundColor(.auraTextTertiary)
                }
                Spacer()
                Text("FLAC · ALAC · WAV · MP3")
                    .font(.auraTiny)
                    .foregroundColor(.auraTextTertiary)
            }
            .listRowBackground(Color.auraSurface)
        } header: {
            Label("About", systemImage: "waveform.circle.fill")
                .font(.system(size: 13, weight: .bold))
                .foregroundColor(.auraTextSecondary)
        }
    }
    
    // MARK: - Helpers
    
    private func statRow(icon: String, label: String, value: String) -> some View {
        HStack {
            Label {
                Text(label)
            } icon: {
                Image(systemName: icon)
                    .foregroundColor(.auraPrimary)
            }
            Spacer()
            Text(value)
                .font(.system(size: 14, weight: .semibold, design: .rounded))
                .foregroundColor(.auraTextSecondary)
        }
        .listRowBackground(Color.auraSurface)
    }
    
    private var outputIcon: String {
        if playerVM.outputRoute.isExternalDAC { return "hifispeaker.fill" }
        if playerVM.outputRoute.isBluetooth { return "airplayaudio" }
        if playerVM.outputRoute.isHeadphones { return "headphones" }
        return "speaker.fill"
    }
    
    private var formattedSessionSampleRate: String {
        let kHz = AudioSessionManager.shared.sessionSampleRate / 1000.0
        if kHz.truncatingRemainder(dividingBy: 1) == 0 {
            return String(format: "%.0f kHz", kHz)
        }
        return String(format: "%.1f kHz", kHz)
    }

    private var shuffleToggleBinding: Binding<Bool> {
        Binding(
            get: { playerVM.isShuffleEnabled },
            set: { _ in
                playerVM.toggleShuffle()
            }
        )
    }

    private var appVersionDisplay: String {
        let info = Bundle.main.infoDictionary
        let shortVersion = (info?["CFBundleShortVersionString"] as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let buildVersion = (info?["CFBundleVersion"] as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let hasShortVersion = !(shortVersion?.isEmpty ?? true)
        let hasBuildVersion = !(buildVersion?.isEmpty ?? true)

        if hasShortVersion, hasBuildVersion, let shortVersion, let buildVersion {
            return "\(shortVersion) (\(buildVersion))"
        }
        if hasShortVersion, let shortVersion {
            return shortVersion
        }
        if hasBuildVersion, let buildVersion {
            return buildVersion
        }
        return "—"
    }
}
