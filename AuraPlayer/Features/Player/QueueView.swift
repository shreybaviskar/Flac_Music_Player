//
//  QueueView.swift
//  AuraPlayer
//
//  Displays the current playback queue with drag-to-reorder,
//  swipe-to-delete, and shuffle mode selection.
//

import SwiftUI

struct QueueView: View {
    @ObservedObject var playerVM: PlayerViewModel
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationStack {
            ZStack {
                Color.auraBackground.ignoresSafeArea()
                
                VStack(spacing: 0) {
                    // Now Playing header
                    nowPlayingHeader
                    
                    Divider()
                        .overlay(Color.auraDivider)
                    
                    // Queue info bar
                    queueInfoBar
                    
                    // Queue list
                    if playerVM.upcomingTracks.isEmpty {
                        emptyQueueView
                    } else {
                        queueList
                    }
                }
            }
            .navigationTitle("Queue")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                        .foregroundColor(.auraPrimary)
                }
                
                ToolbarItem(placement: .topBarLeading) {
                    Menu {
                        ForEach(ShuffleMode.allCases) { mode in
                            Button {
                                playerVM.setShuffleMode(mode)
                            } label: {
                                HStack {
                                    Image(systemName: mode.iconName)
                                    Text(mode.rawValue)
                                    if playerVM.shuffleMode == mode && playerVM.isShuffleEnabled {
                                        Image(systemName: "checkmark")
                                    }
                                }
                            }
                        }
                        
                        Divider()
                        
                        Button(role: .destructive) {
                            QueueManager.shared.clearQueue()
                        } label: {
                            Label("Clear Queue", systemImage: "trash")
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                            .foregroundColor(.auraPrimary)
                    }
                }
            }
        }
    }
    
    // MARK: - Now Playing Header
    
    private var nowPlayingHeader: some View {
        HStack(spacing: 14) {
            if let image = playerVM.artworkImage {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: 52, height: 52)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
            } else {
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.auraSurface)
                    .frame(width: 52, height: 52)
                    .overlay(
                        Image(systemName: "music.note")
                            .foregroundColor(.auraTextTertiary)
                    )
            }
            
            VStack(alignment: .leading, spacing: 3) {
                Text("Now Playing")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(.auraTextTertiary)
                    .textCase(.uppercase)
                
                Text(playerVM.currentTrack?.title ?? "Not Playing")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundColor(.auraTextPrimary)
                    .lineLimit(1)
                
                Text(playerVM.currentTrack?.artistName ?? "")
                    .font(.system(size: 13))
                    .foregroundColor(.auraTextSecondary)
                    .lineLimit(1)
            }
            
            Spacer()
            
            // Play/Pause indicator
            Image(systemName: playerVM.isPlaying ? "waveform" : "pause.fill")
                .font(.title3)
                .foregroundColor(.auraPrimary)
                .symbolEffect(.variableColor.iterative, isActive: playerVM.isPlaying)
        }
        .padding()
        .background(Color.auraSurface.opacity(0.5))
    }
    
    // MARK: - Queue Info Bar
    
    private var queueInfoBar: some View {
        HStack {
            Text("Up Next")
                .font(.system(size: 13, weight: .bold))
                .foregroundColor(.auraTextPrimary)
            
            Spacer()
            
            if !playerVM.upcomingTracks.isEmpty {
                Text("\(playerVM.upcomingTracks.count) tracks · \(QueueManager.shared.formattedRemainingDuration)")
                    .font(.system(size: 12))
                    .foregroundColor(.auraTextTertiary)
            }
            
            // Shuffle badge
            if playerVM.isShuffleEnabled {
                HStack(spacing: 4) {
                    Image(systemName: playerVM.shuffleMode.iconName)
                        .font(.system(size: 10))
                    Text(playerVM.shuffleMode.rawValue)
                        .font(.system(size: 10, weight: .medium))
                }
                .foregroundColor(.auraSuccess)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Color.auraSuccess.opacity(0.15))
                .clipShape(Capsule())
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 10)
    }
    
    // MARK: - Queue List
    
    private var queueList: some View {
        List {
            ForEach(Array(playerVM.upcomingTracks.enumerated()), id: \.element.id) { _, track in
                Button {
                    playerVM.jumpToQueueTrack(track)
                    dismiss()
                } label: {
                    HStack(spacing: 12) {
                        // Artwork
                        if let artworkData = track.artworkData,
                           let uiImage = UIImage(data: artworkData) {
                            Image(uiImage: uiImage)
                                .resizable()
                                .aspectRatio(contentMode: .fill)
                                .frame(width: 40, height: 40)
                                .clipShape(RoundedRectangle(cornerRadius: 6))
                        } else {
                            RoundedRectangle(cornerRadius: 6)
                                .fill(Color.auraSurface)
                                .frame(width: 40, height: 40)
                                .overlay(
                                    Image(systemName: "music.note")
                                        .font(.caption2)
                                        .foregroundColor(.auraTextTertiary)
                                )
                        }
                        
                        // Title + Artist
                        VStack(alignment: .leading, spacing: 2) {
                            Text(track.title)
                                .font(.system(size: 15))
                                .foregroundColor(.auraTextPrimary)
                                .lineLimit(1)
                            
                            Text(track.artistName)
                                .font(.system(size: 12))
                                .foregroundColor(.auraTextSecondary)
                                .lineLimit(1)
                        }
                        
                        Spacer()
                        
                        Text(track.formattedDuration)
                            .font(.system(size: 12, design: .monospaced))
                            .foregroundColor(.auraTextTertiary)
                        
                        // Drag handle
                        Image(systemName: "line.3.horizontal")
                            .font(.caption)
                            .foregroundColor(.auraTextTertiary)
                    }
                    .padding(.vertical, 2)
                }
                .listRowBackground(Color.auraBackground)
                .listRowSeparatorTint(.auraDivider)
            }
            .onDelete { offsets in
                playerVM.removeFromQueue(at: offsets)
            }
            .onMove { source, destination in
                playerVM.moveQueueTrack(from: source, to: destination)
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .environment(\.editMode, .constant(.active))
    }
    
    // MARK: - Empty Queue
    
    private var emptyQueueView: some View {
        VStack(spacing: 16) {
            Spacer()
            
            Image(systemName: "text.line.first.and.arrowtriangle.forward")
                .font(.system(size: 48))
                .foregroundColor(.auraTextTertiary)
            
            Text("Queue is Empty")
                .font(.auraHeadline)
                .foregroundColor(.auraTextSecondary)
            
            Text("Play a song to start building your queue")
                .font(.auraCaption)
                .foregroundColor(.auraTextTertiary)
            
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }
}
