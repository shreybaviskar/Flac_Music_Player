//
//  AlbumGridView.swift
//  AuraPlayer
//
//  Album grid with artwork thumbnails, album detail navigation.
//

import SwiftUI
import SwiftData

struct AlbumGridView: View {
    let albums: [Album]
    @ObservedObject var libraryVM: LibraryViewModel
    @ObservedObject var playerVM: PlayerViewModel
    
    private let columns = [
        GridItem(.adaptive(minimum: 160), spacing: 16)
    ]
    
    var body: some View {
        ScrollView {
            LazyVGrid(columns: columns, spacing: 20) {
                ForEach(albums) { album in
                    NavigationLink(destination: AlbumDetailView(
                        album: album,
                        libraryVM: libraryVM,
                        playerVM: playerVM
                    )) {
                        AlbumCardView(album: album)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal)
            .padding(.top, 8)
            .padding(.bottom, 100) // Space for mini player
        }
    }
}

// MARK: - Album Card

struct AlbumCardView: View {
    let album: Album
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Artwork
            if let artworkData = album.artworkData,
               let uiImage = UIImage(data: artworkData) {
                Image(uiImage: uiImage)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(minWidth: 0, maxWidth: .infinity)
                    .aspectRatio(1, contentMode: .fit)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .shadow(color: .black.opacity(0.3), radius: 8, y: 4)
            } else {
                RoundedRectangle(cornerRadius: 12)
                    .fill(
                        LinearGradient(
                            colors: [.auraSurface, .auraSurfaceSecondary],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .aspectRatio(1, contentMode: .fit)
                    .overlay(
                        Image(systemName: "music.note")
                            .font(.system(size: 32))
                            .foregroundColor(.auraTextTertiary)
                    )
            }
            
            // Title + Artist
            VStack(alignment: .leading, spacing: 2) {
                Text(album.title)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.auraTextPrimary)
                    .lineLimit(1)
                
                Text(album.artistName)
                    .font(.system(size: 12))
                    .foregroundColor(.auraTextSecondary)
                    .lineLimit(1)
            }
        }
    }
}

// MARK: - Album Detail View

struct AlbumDetailView: View {
    let album: Album
    @ObservedObject var libraryVM: LibraryViewModel
    @ObservedObject var playerVM: PlayerViewModel
    
    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                // Header with artwork
                albumHeader
                
                // Action buttons
                actionButtons
                    .padding(.vertical, 16)
                
                // Track list
                LazyVStack(spacing: 0) {
                    ForEach(album.sortedTracks) { track in
                        TrackRowView(
                            track: track,
                            showAlbumArt: false,
                            showTrackNumber: true,
                            isCurrentTrack: playerVM.currentTrack?.id == track.id
                        ) {
                            libraryVM.playAllTracks(album.sortedTracks, startingFrom: track)
                        }
                        .withContextMenu(playerVM: playerVM, libraryVM: libraryVM)
                        .padding(.horizontal)
                        
                        Divider()
                            .overlay(Color.auraDivider)
                            .padding(.leading, 52)
                    }
                }
                
                // Album info footer
                albumFooter
                    .padding(.top, 24)
                    .padding(.bottom, 100)
            }
        }
        .background(Color.auraBackground)
        .navigationBarTitleDisplayMode(.inline)
    }
    
    // MARK: - Album Header
    
    private var albumHeader: some View {
        VStack(spacing: 12) {
            if let artworkData = album.artworkData,
               let uiImage = UIImage(data: artworkData) {
                Image(uiImage: uiImage)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 240, height: 240)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .shadow(color: .black.opacity(0.4), radius: 20, y: 10)
            } else {
                RoundedRectangle(cornerRadius: 12)
                    .fill(LinearGradient(
                        colors: [.auraSurface, .auraSurfaceSecondary],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ))
                    .frame(width: 240, height: 240)
                    .overlay(
                        Image(systemName: "music.note")
                            .font(.system(size: 48))
                            .foregroundColor(.auraTextTertiary)
                    )
            }
            
            Text(album.title)
                .font(.auraHeadline)
                .foregroundColor(.auraTextPrimary)
                .multilineTextAlignment(.center)
            
            Text(album.artistName)
                .font(.auraSubheadline)
                .foregroundColor(.auraPrimary)
            
            Text(album.subtitle)
                .font(.auraCaption)
                .foregroundColor(.auraTextTertiary)
        }
        .padding(.top, 20)
    }
    
    // MARK: - Action Buttons
    
    private var actionButtons: some View {
        HStack(spacing: 16) {
            Button {
                libraryVM.playAlbum(album)
            } label: {
                HStack {
                    Image(systemName: "play.fill")
                    Text("Play")
                }
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .background(Color.auraPrimary)
                .clipShape(RoundedRectangle(cornerRadius: 12))
            }
            
            Button {
                QueueManager.shared.isShuffleEnabled = true
                libraryVM.playAlbum(album)
            } label: {
                HStack {
                    Image(systemName: "shuffle")
                    Text("Shuffle")
                }
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(.auraPrimary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .background(.auraPrimary.opacity(0.15))
                .clipShape(RoundedRectangle(cornerRadius: 12))
            }
        }
        .padding(.horizontal)
    }
    
    // MARK: - Album Footer
    
    private var albumFooter: some View {
        VStack(spacing: 4) {
            if let year = album.year {
                Text("\(year)")
                    .font(.auraCaption)
                    .foregroundColor(.auraTextTertiary)
            }
            Text("\(album.trackCount) songs · \(album.formattedDuration)")
                .font(.auraCaption)
                .foregroundColor(.auraTextTertiary)
            
            if album.isLossless {
                HStack(spacing: 4) {
                    Image(systemName: "waveform")
                    Text(album.isHiRes ? "Hi-Res Lossless" : "Lossless")
                }
                .font(.auraTiny)
                .foregroundColor(album.isHiRes ? .auraWarning : .auraSuccess)
                .padding(.top, 4)
            }
        }
    }
}
