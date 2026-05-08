//
//  MiniPlayerView.swift
//  AuraPlayer
//
//  Persistent mini player bar at the bottom of the screen.
//  Expands to NowPlayingView via matchedGeometryEffect.
//

import SwiftUI

struct MiniPlayerView: View {
    @ObservedObject var playerVM: PlayerViewModel
    @Binding var isExpanded: Bool
    let namespace: Namespace.ID
    
    var body: some View {
        if playerVM.currentTrack != nil {
            VStack(spacing: 0) {
                // Progress bar (thin line at top)
                GeometryReader { geo in
                    Rectangle()
                        .fill(Color.auraPrimary)
                        .frame(width: geo.size.width * playerVM.playbackProgress, height: 2)
                }
                .frame(height: 2)
                
                // Content
                HStack(spacing: 12) {
                    // Artwork
                    if let image = playerVM.artworkImage {
                        Image(uiImage: image)
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                            .frame(width: 44, height: 44)
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                            .matchedGeometryEffect(id: "artwork", in: namespace)
                    } else {
                        RoundedRectangle(cornerRadius: 8)
                            .fill(Color.auraSurface)
                            .frame(width: 44, height: 44)
                            .overlay(
                                Image(systemName: "music.note")
                                    .font(.caption)
                                    .foregroundColor(.auraTextTertiary)
                            )
                            .matchedGeometryEffect(id: "artwork", in: namespace)
                    }
                    
                    // Title + Artist
                    VStack(alignment: .leading, spacing: 2) {
                        Text(playerVM.currentTrack?.title ?? "")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(.auraTextPrimary)
                            .lineLimit(1)
                        
                        Text(playerVM.currentTrack?.artistName ?? "")
                            .font(.system(size: 12))
                            .foregroundColor(.auraTextSecondary)
                            .lineLimit(1)
                    }
                    .matchedGeometryEffect(id: "trackInfo", in: namespace)
                    
                    Spacer()
                    
                    // Play / Pause
                    Button {
                        playerVM.togglePlayPause()
                    } label: {
                        Image(systemName: playerVM.isPlaying ? "pause.fill" : "play.fill")
                            .font(.system(size: 20))
                            .foregroundColor(.auraTextPrimary)
                            .frame(width: 36, height: 36)
                    }
                    
                    // Next
                    Button {
                        playerVM.nextTrack()
                    } label: {
                        Image(systemName: "forward.fill")
                            .font(.system(size: 16))
                            .foregroundColor(.auraTextPrimary)
                            .frame(width: 36, height: 36)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
            }
            .background(
                .ultraThinMaterial,
                in: RoundedRectangle(cornerRadius: 16)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .strokeBorder(Color.white.opacity(0.06), lineWidth: 0.5)
            )
            .padding(.horizontal, 8)
            .shadow(color: .black.opacity(0.2), radius: 8, y: -2)
            .onTapGesture {
                withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                    isExpanded = true
                }
            }
        }
    }
}
