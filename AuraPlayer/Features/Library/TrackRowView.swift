//
//  TrackRowView.swift
//  AuraPlayer
//
//  Reusable track row component used across all list views.
//

import SwiftUI

struct TrackRowView: View {
    let track: Track
    let showAlbumArt: Bool
    let showTrackNumber: Bool
    let isCurrentTrack: Bool
    var onTap: () -> Void = {}
    
    init(
        track: Track,
        showAlbumArt: Bool = true,
        showTrackNumber: Bool = false,
        isCurrentTrack: Bool = false,
        onTap: @escaping () -> Void = {}
    ) {
        self.track = track
        self.showAlbumArt = showAlbumArt
        self.showTrackNumber = showTrackNumber
        self.isCurrentTrack = isCurrentTrack
        self.onTap = onTap
    }
    
    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 12) {
                // Track number or album art
                if showTrackNumber {
                    Text("\(track.trackNumber ?? 0)")
                        .font(.auraCaption)
                        .foregroundColor(isCurrentTrack ? .auraPrimary : .auraTextTertiary)
                        .frame(width: 28)
                } else if showAlbumArt {
                    artworkView
                }
                
                // Now playing indicator
                if isCurrentTrack {
                    Image(systemName: "waveform")
                        .font(.caption)
                        .foregroundColor(.auraPrimary)
                        .symbolEffect(.variableColor.iterative, isActive: true)
                        .frame(width: 16)
                }
                
                // Title + Artist
                VStack(alignment: .leading, spacing: 3) {
                    Text(track.title)
                        .font(.auraBody)
                        .foregroundColor(isCurrentTrack ? .auraPrimary : .auraTextPrimary)
                        .lineLimit(1)
                    
                    HStack(spacing: 4) {
                        // Quality badge
                        if track.isLossless {
                            Text(track.qualityBadge)
                                .font(.auraTiny)
                                .foregroundColor(track.qualityColor)
                                .padding(.horizontal, 4)
                                .padding(.vertical, 1)
                                .background(track.qualityColor.opacity(0.15))
                                .clipShape(RoundedRectangle(cornerRadius: 3))
                        }
                        
                        Text(track.artistName)
                            .font(.auraCaption)
                            .foregroundColor(.auraTextSecondary)
                            .lineLimit(1)
                    }
                }
                
                Spacer()
                
                // Duration
                Text(track.formattedDuration)
                    .font(.auraCaption)
                    .foregroundColor(.auraTextTertiary)
            }
            .padding(.vertical, 6)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
    
    @ViewBuilder
    private var artworkView: some View {
        if let artworkData = track.artworkData,
           let uiImage = UIImage(data: artworkData) {
            Image(uiImage: uiImage)
                .resizable()
                .aspectRatio(contentMode: .fill)
                .frame(width: 48, height: 48)
                .clipShape(RoundedRectangle(cornerRadius: 8))
        } else {
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.auraSurface)
                .frame(width: 48, height: 48)
                .overlay(
                    Image(systemName: "music.note")
                        .foregroundColor(.auraTextTertiary)
                )
        }
    }
}

// MARK: - Context Menu

extension TrackRowView {
    func withContextMenu(
        playerVM: PlayerViewModel,
        libraryVM: LibraryViewModel
    ) -> some View {
        self.contextMenu {
            Button {
                playerVM.playNext(track: track)
            } label: {
                Label("Play Next", systemImage: "text.insert")
            }
            
            Button {
                playerVM.playLater(track: track)
            } label: {
                Label("Play Later", systemImage: "text.append")
            }
            
            Divider()
            
            Button {
                libraryVM.toggleFavorite(track)
            } label: {
                Label(
                    track.isFavorite ? "Unfavorite" : "Favorite",
                    systemImage: track.isFavorite ? "heart.fill" : "heart"
                )
            }
            
            Divider()
            
            if let album = track.album {
                Button {
                    // Navigate to album — handled by parent view
                } label: {
                    Label("Go to Album: \(album.title)", systemImage: "square.stack")
                }
            }
        }
    }
}
