//
//  NowPlayingView.swift
//  AuraPlayer
//
//  Full-screen Now Playing view inspired by Apple Music.
//  Features: dynamic artwork gradient, glassmorphism controls,
//  seek slider, quality badge, output route indicator.
//

import SwiftUI

struct NowPlayingView: View {
    @ObservedObject var playerVM: PlayerViewModel
    @Environment(\.dismiss) private var dismiss
    
    @State private var isDraggingSlider = false
    @State private var dragValue: Double = 0
    
    var body: some View {
        ZStack {
            // Dynamic background gradient from album art
            backgroundGradient
            
            // Content
            ScrollView(showsIndicators: false) {
                VStack(spacing: 24) {
                    // Drag indicator
                    Capsule()
                        .fill(Color.white.opacity(0.3))
                        .frame(width: 40, height: 5)
                        .padding(.top, 8)
                    
                    // Album artwork
                    artworkView
                        .padding(.top, 12)
                    
                    // Track info
                    trackInfoView
                    
                    // Progress slider
                    progressView
                        .padding(.horizontal, 28)
                    
                    // Playback controls
                    controlsView
                    
                    // Volume slider
                    volumeView
                        .padding(.horizontal, 28)
                    
                    // Bottom actions (EQ, Queue, AirPlay)
                    bottomActionsView
                    
                    // Output route
                    outputRouteView
                        .padding(.bottom, 32)
                }
            }
        }
        .sheet(isPresented: $playerVM.showingEqualizer) {
            EqualizerView(playerVM: playerVM)
        }
        .sheet(isPresented: $playerVM.showingQueue) {
            QueueView(playerVM: playerVM)
        }
    }
    
    // MARK: - Background Gradient
    
    private var backgroundGradient: some View {
        ZStack {
            if let image = playerVM.artworkImage {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .blur(radius: 80)
                    .opacity(0.5)
                    .scaleEffect(1.2)
            }
            
            LinearGradient(
                colors: playerVM.artworkColors,
                startPoint: .top,
                endPoint: .bottom
            )
            .opacity(0.9)
        }
        .ignoresSafeArea()
        .animation(.easeInOut(duration: 0.8), value: playerVM.currentTrack?.id)
    }
    
    // MARK: - Artwork
    
    private var artworkView: some View {
        Group {
            if let image = playerVM.artworkImage {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(maxWidth: 320, maxHeight: 320)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .shadow(color: .black.opacity(0.5), radius: 30, y: 15)
                    .scaleEffect(playerVM.isPlaying ? 1.0 : 0.85)
                    .animation(.spring(response: 0.5, dampingFraction: 0.7), value: playerVM.isPlaying)
            } else {
                RoundedRectangle(cornerRadius: 12)
                    .fill(
                        LinearGradient(
                            colors: [.auraSurface, .auraSurfaceSecondary],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 320, height: 320)
                    .overlay(
                        Image(systemName: "music.note")
                            .font(.system(size: 64))
                            .foregroundColor(.auraTextTertiary)
                    )
                    .shadow(color: .black.opacity(0.3), radius: 20, y: 10)
            }
        }
    }
    
    // MARK: - Track Info
    
    private var trackInfoView: some View {
        VStack(spacing: 6) {
            // Title (marquee for long titles)
            Text(playerVM.currentTrack?.title ?? "Not Playing")
                .font(.system(size: 22, weight: .bold))
                .foregroundColor(.white)
                .lineLimit(1)
                .multilineTextAlignment(.center)
            
            // Artist
            Text(playerVM.currentTrack?.artistName ?? "")
                .font(.system(size: 18, weight: .medium))
                .foregroundColor(.white.opacity(0.7))
                .lineLimit(1)
            
            // Quality badge
            if let track = playerVM.currentTrack {
                HStack(spacing: 6) {
                    Image(systemName: "waveform")
                        .font(.system(size: 10))
                    Text("\(track.qualityBadge) · \(Int(playerVM.sampleRate / 1000))kHz · \(playerVM.bitDepth)-bit")
                        .font(.system(size: 11, weight: .medium))
                }
                .foregroundColor(track.qualityColor)
                .padding(.horizontal, 12)
                .padding(.vertical, 4)
                .background(track.qualityColor.opacity(0.2))
                .clipShape(Capsule())
                .padding(.top, 4)
            }
        }
        .padding(.horizontal, 28)
    }
    
    // MARK: - Progress Slider
    
    private var progressView: some View {
        VStack(spacing: 6) {
            // Custom slider
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    // Track background
                    Capsule()
                        .fill(Color.white.opacity(0.2))
                        .frame(height: 4)
                    
                    // Progress fill
                    Capsule()
                        .fill(Color.white)
                        .frame(
                            width: max(0, geometry.size.width * (isDraggingSlider ? dragValue : playerVM.playbackProgress)),
                            height: isDraggingSlider ? 6 : 4
                        )
                    
                    // Thumb (visible on drag)
                    if isDraggingSlider {
                        Circle()
                            .fill(Color.white)
                            .frame(width: 14, height: 14)
                            .offset(x: geometry.size.width * dragValue - 7)
                    }
                }
                .frame(height: 14)
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { value in
                            if !isDraggingSlider {
                                isDraggingSlider = true
                                playerVM.beginSeeking()
                            }
                            let progress = value.location.x / geometry.size.width
                            dragValue = max(0, min(1, progress))
                            playerVM.updateSeekPosition(dragValue)
                        }
                        .onEnded { _ in
                            playerVM.endSeeking()
                            isDraggingSlider = false
                        }
                )
            }
            .frame(height: 14)
            
            // Time labels
            HStack {
                Text(playerVM.formattedCurrentTime)
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .foregroundColor(.white.opacity(0.6))
                
                Spacer()
                
                Text(playerVM.formattedRemainingTime)
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .foregroundColor(.white.opacity(0.6))
            }
        }
    }
    
    // MARK: - Playback Controls
    
    private var controlsView: some View {
        HStack(spacing: 40) {
            // Shuffle
            Button {
                playerVM.toggleShuffle()
            } label: {
                Image(systemName: "shuffle")
                    .font(.title3)
                    .foregroundColor(playerVM.isShuffleEnabled ? .auraSuccess : .white.opacity(0.5))
            }
            
            // Previous
            Button {
                playerVM.previousTrack()
            } label: {
                Image(systemName: "backward.fill")
                    .font(.system(size: 28))
                    .foregroundColor(.white)
            }
            
            // Play / Pause
            Button {
                playerVM.togglePlayPause()
            } label: {
                Image(systemName: playerVM.isPlaying ? "pause.circle.fill" : "play.circle.fill")
                    .font(.system(size: 68))
                    .foregroundColor(.white)
            }
            
            // Next
            Button {
                playerVM.nextTrack()
            } label: {
                Image(systemName: "forward.fill")
                    .font(.system(size: 28))
                    .foregroundColor(.white)
            }
            
            // Repeat
            Button {
                playerVM.cycleRepeatMode()
            } label: {
                Image(systemName: QueueManager.shared.repeatModeIcon)
                    .font(.title3)
                    .foregroundColor(playerVM.repeatMode != .off ? .auraSuccess : .white.opacity(0.5))
            }
        }
    }
    
    // MARK: - Volume
    
    private var volumeView: some View {
        HStack(spacing: 12) {
            Image(systemName: "speaker.fill")
                .font(.caption)
                .foregroundColor(.white.opacity(0.5))
            
            Slider(value: $playerVM.volume, in: 0...1)
                .tint(.white.opacity(0.8))
            
            Image(systemName: "speaker.wave.3.fill")
                .font(.caption)
                .foregroundColor(.white.opacity(0.5))
        }
    }
    
    // MARK: - Bottom Actions
    
    private var bottomActionsView: some View {
        HStack(spacing: 48) {
            // Lyrics
            Button {
                playerVM.showingLyrics.toggle()
            } label: {
                Image(systemName: "quote.bubble")
                    .font(.title3)
                    .foregroundColor(.white.opacity(0.6))
            }
            
            // EQ
            Button {
                playerVM.showingEqualizer = true
            } label: {
                Image(systemName: "slider.horizontal.3")
                    .font(.title3)
                    .foregroundColor(.white.opacity(0.6))
            }
            
            // Queue
            Button {
                playerVM.showingQueue = true
            } label: {
                Image(systemName: "list.bullet")
                    .font(.title3)
                    .foregroundColor(.white.opacity(0.6))
            }
        }
        .padding(.top, 8)
    }
    
    // MARK: - Output Route
    
    private var outputRouteView: some View {
        HStack(spacing: 6) {
            Image(systemName: playerVM.outputRoute.isExternalDAC ? "hifispeaker.fill" :
                    playerVM.outputRoute.isBluetooth ? "airplayaudio" : "speaker.fill")
                .font(.caption)
            Text(playerVM.outputRouteLabel)
                .font(.caption)
        }
        .foregroundColor(.white.opacity(0.4))
    }
}
