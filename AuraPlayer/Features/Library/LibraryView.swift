//
//  LibraryView.swift
//  AuraPlayer
//
//  Main library view with segmented tabs: Songs, Albums, Artists,
//  Playlists, Favorites. Includes search, sort, and import actions.
//

import SwiftUI
import SwiftData

struct LibraryView: View {
    @Environment(\.modelContext) private var modelContext
    @ObservedObject var libraryVM: LibraryViewModel
    @ObservedObject var playerVM: PlayerViewModel
    
    // SwiftData queries
    @Query(sort: \Track.title) private var allTracks: [Track]
    @Query(sort: \Album.title) private var allAlbums: [Album]
    @Query(sort: \Playlist.dateModified, order: .reverse) private var allPlaylists: [Playlist]
    
    @State private var showCreatePlaylist = false
    @State private var newPlaylistName = ""
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Tab bar
                tabBar
                
                // Content
                TabView(selection: $libraryVM.selectedTab) {
                    songsTab.tag(LibraryTab.songs)
                    albumsTab.tag(LibraryTab.albums)
                    artistsTab.tag(LibraryTab.artists)
                    playlistsTab.tag(LibraryTab.playlists)
                    favoritesTab.tag(LibraryTab.favorites)
                }
                .tabViewStyle(.page(indexDisplayMode: .never))
            }
            .background(Color.auraBackground)
            .navigationTitle("Library")
            .navigationBarTitleDisplayMode(.large)
            .searchable(text: $libraryVM.searchText, prompt: "Songs, Albums, Artists")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    importMenu
                }
            }
            .sheet(isPresented: $libraryVM.showingFolderPicker) {
                FolderPickerView { url in
                    libraryVM.importFolder(url, modelContext: modelContext)
                    libraryVM.showingFolderPicker = false
                } onCancel: {
                    libraryVM.showingFolderPicker = false
                }
            }
            .alert("Import Result", isPresented: $libraryVM.showImportResult) {
                Button("OK") {}
            } message: {
                Text(libraryVM.importResultMessage)
            }
            .alert("New Playlist", isPresented: $showCreatePlaylist) {
                TextField("Playlist name", text: $newPlaylistName)
                Button("Cancel", role: .cancel) { newPlaylistName = "" }
                Button("Create") {
                    if !newPlaylistName.isEmpty {
                        _ = libraryVM.createPlaylist(name: newPlaylistName, modelContext: modelContext)
                        newPlaylistName = ""
                    }
                }
            }
            .onAppear {
                libraryVM.updateStats(modelContext: modelContext)
                libraryVM.seedEQPresetsIfNeeded(modelContext: modelContext)
            }
        }
    }
    
    // MARK: - Tab Bar
    
    private var tabBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 24) {
                ForEach(LibraryTab.allCases) { tab in
                    Button {
                        withAnimation(.easeInOut(duration: 0.25)) {
                            libraryVM.selectedTab = tab
                        }
                    } label: {
                        VStack(spacing: 6) {
                            Text(tab.rawValue)
                                .font(.system(size: 15, weight: libraryVM.selectedTab == tab ? .bold : .medium))
                                .foregroundColor(libraryVM.selectedTab == tab ? .auraTextPrimary : .auraTextTertiary)
                            
                            Rectangle()
                                .fill(libraryVM.selectedTab == tab ? Color.auraPrimary : Color.clear)
                                .frame(height: 2)
                                .animation(.easeInOut(duration: 0.2), value: libraryVM.selectedTab)
                        }
                    }
                }
            }
            .padding(.horizontal)
        }
        .padding(.vertical, 8)
        .background(Color.auraBackground)
    }
    
    // MARK: - Songs Tab
    
    private var songsTab: some View {
        Group {
            if allTracks.isEmpty {
                emptyLibraryView
            } else {
                List {
                    // Shuffle all button
                    Button {
                        libraryVM.shuffleAll(allTracks)
                    } label: {
                        HStack {
                            Image(systemName: "shuffle")
                                .foregroundColor(.auraPrimary)
                            Text("Shuffle All")
                                .foregroundColor(.auraPrimary)
                            Spacer()
                            Text("\(allTracks.count) songs")
                                .font(.auraCaption)
                                .foregroundColor(.auraTextTertiary)
                        }
                    }
                    .listRowBackground(Color.auraSurface)
                    
                    ForEach(filteredTracks) { track in
                        TrackRowView(
                            track: track,
                            isCurrentTrack: playerVM.currentTrack?.id == track.id
                        ) {
                            libraryVM.playAllTracks(filteredTracks, startingFrom: track)
                        }
                        .withContextMenu(playerVM: playerVM, libraryVM: libraryVM)
                        .listRowBackground(Color.auraBackground)
                        .listRowSeparatorTint(.auraDivider)
                    }
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
            }
        }
    }
    
    // MARK: - Albums Tab
    
    private var albumsTab: some View {
        Group {
            if allAlbums.isEmpty {
                emptyLibraryView
            } else {
                AlbumGridView(
                    albums: filteredAlbums,
                    libraryVM: libraryVM,
                    playerVM: playerVM
                )
            }
        }
    }
    
    // MARK: - Artists Tab
    
    private var artistsTab: some View {
        Group {
            let artistGroups = libraryVM.groupTracksByArtist(allTracks)
            if artistGroups.isEmpty {
                emptyLibraryView
            } else {
                List {
                    ForEach(artistGroups, id: \.name) { group in
                        NavigationLink {
                            ArtistDetailView(
                                artistName: group.name,
                                tracks: group.tracks,
                                libraryVM: libraryVM,
                                playerVM: playerVM
                            )
                        } label: {
                            HStack(spacing: 12) {
                                Circle()
                                    .fill(
                                        LinearGradient(
                                            colors: [.auraPrimary, .auraAccent],
                                            startPoint: .topLeading,
                                            endPoint: .bottomTrailing
                                        )
                                    )
                                    .frame(width: 44, height: 44)
                                    .overlay(
                                        Text(String(group.name.prefix(1)).uppercased())
                                            .font(.system(size: 18, weight: .bold))
                                            .foregroundColor(.white)
                                    )
                                
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(group.name)
                                        .font(.auraBody)
                                        .foregroundColor(.auraTextPrimary)
                                    
                                    Text("\(group.tracks.count) song\(group.tracks.count == 1 ? "" : "s")")
                                        .font(.auraCaption)
                                        .foregroundColor(.auraTextSecondary)
                                }
                            }
                        }
                        .listRowBackground(Color.auraBackground)
                        .listRowSeparatorTint(.auraDivider)
                    }
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
            }
        }
    }
    
    // MARK: - Playlists Tab
    
    private var playlistsTab: some View {
        Group {
            List {
                // Create playlist button
                Button {
                    showCreatePlaylist = true
                } label: {
                    HStack {
                        Image(systemName: "plus.circle.fill")
                            .foregroundColor(.auraPrimary)
                            .font(.title2)
                        Text("New Playlist")
                            .foregroundColor(.auraPrimary)
                    }
                }
                .listRowBackground(Color.auraSurface)
                
                ForEach(allPlaylists) { playlist in
                    NavigationLink {
                        PlaylistDetailView(
                            playlist: playlist,
                            libraryVM: libraryVM,
                            playerVM: playerVM
                        )
                    } label: {
                        HStack(spacing: 12) {
                            RoundedRectangle(cornerRadius: 8)
                                .fill(
                                    LinearGradient(
                                        colors: [.auraAccent, .auraPrimary],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    )
                                )
                                .frame(width: 48, height: 48)
                                .overlay(
                                    Image(systemName: "music.note.list")
                                        .foregroundColor(.white)
                                )
                            
                            VStack(alignment: .leading, spacing: 3) {
                                Text(playlist.name)
                                    .font(.auraBody)
                                    .foregroundColor(.auraTextPrimary)
                                
                                Text("\(playlist.trackCount) songs · \(playlist.formattedDuration)")
                                    .font(.auraCaption)
                                    .foregroundColor(.auraTextSecondary)
                            }
                        }
                    }
                    .listRowBackground(Color.auraBackground)
                    .listRowSeparatorTint(.auraDivider)
                }
                .onDelete { offsets in
                    for index in offsets {
                        libraryVM.deletePlaylist(allPlaylists[index], modelContext: modelContext)
                    }
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
        }
    }
    
    // MARK: - Favorites Tab
    
    private var favoritesTab: some View {
        Group {
            let favorites = allTracks.filter(\.isFavorite)
            if favorites.isEmpty {
                VStack(spacing: 16) {
                    Image(systemName: "heart")
                        .font(.system(size: 48))
                        .foregroundColor(.auraTextTertiary)
                    Text("No Favorites Yet")
                        .font(.auraHeadline)
                        .foregroundColor(.auraTextSecondary)
                    Text("Tap the heart icon on any song to add it here")
                        .font(.auraCaption)
                        .foregroundColor(.auraTextTertiary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List {
                    ForEach(favorites) { track in
                        TrackRowView(
                            track: track,
                            isCurrentTrack: playerVM.currentTrack?.id == track.id
                        ) {
                            libraryVM.playAllTracks(favorites, startingFrom: track)
                        }
                        .withContextMenu(playerVM: playerVM, libraryVM: libraryVM)
                        .listRowBackground(Color.auraBackground)
                        .listRowSeparatorTint(.auraDivider)
                    }
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
            }
        }
    }
    
    // MARK: - Import Menu
    
    private var importMenu: some View {
        Menu {
            Button {
                libraryVM.showingFolderPicker = true
            } label: {
                Label("Import Folder", systemImage: "folder.badge.plus")
            }
            
            Button {
                libraryVM.rescanLibrary(modelContext: modelContext)
            } label: {
                Label("Rescan Library", systemImage: "arrow.clockwise")
            }
            
            Divider()
            
            Button(role: .destructive) {
                libraryVM.pruneOrphanedTracks(modelContext: modelContext)
            } label: {
                Label("Remove Missing Files", systemImage: "trash")
            }
        } label: {
            Image(systemName: "plus")
                .font(.title3)
                .foregroundColor(.auraPrimary)
        }
    }
    
    // MARK: - Empty State
    
    private var emptyLibraryView: some View {
        VStack(spacing: 20) {
            Image(systemName: "music.note.house")
                .font(.system(size: 56))
                .foregroundStyle(
                    LinearGradient(
                        colors: [.auraPrimary, .auraAccent],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
            
            Text("Your Library is Empty")
                .font(.auraHeadline)
                .foregroundColor(.auraTextPrimary)
            
            Text("Import a folder of music files to get started")
                .font(.auraBody)
                .foregroundColor(.auraTextSecondary)
                .multilineTextAlignment(.center)
            
            Button {
                libraryVM.showingFolderPicker = true
            } label: {
                HStack {
                    Image(systemName: "folder.badge.plus")
                    Text("Import Folder")
                }
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(.white)
                .padding(.horizontal, 32)
                .padding(.vertical, 14)
                .background(.auraPrimary)
                .clipShape(Capsule())
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    // MARK: - Filtered Data
    
    private var filteredTracks: [Track] {
        if libraryVM.debouncedSearchText.isEmpty { return allTracks }
        let query = libraryVM.debouncedSearchText.lowercased()
        return allTracks.filter {
            $0.title.lowercased().contains(query) ||
            $0.artistName.lowercased().contains(query) ||
            $0.albumTitle.lowercased().contains(query)
        }
    }
    
    private var filteredAlbums: [Album] {
        if libraryVM.debouncedSearchText.isEmpty { return allAlbums }
        let query = libraryVM.debouncedSearchText.lowercased()
        return allAlbums.filter {
            $0.title.lowercased().contains(query) ||
            $0.artistName.lowercased().contains(query)
        }
    }
}

// MARK: - Artist Detail View

struct ArtistDetailView: View {
    let artistName: String
    let tracks: [Track]
    @ObservedObject var libraryVM: LibraryViewModel
    @ObservedObject var playerVM: PlayerViewModel
    
    var body: some View {
        List {
            Button {
                libraryVM.shuffleAll(tracks)
            } label: {
                HStack {
                    Image(systemName: "shuffle")
                        .foregroundColor(.auraPrimary)
                    Text("Shuffle All")
                        .foregroundColor(.auraPrimary)
                    Spacer()
                    Text("\(tracks.count) songs")
                        .font(.auraCaption)
                        .foregroundColor(.auraTextTertiary)
                }
            }
            .listRowBackground(Color.auraSurface)
            
            ForEach(tracks) { track in
                TrackRowView(
                    track: track,
                    isCurrentTrack: playerVM.currentTrack?.id == track.id
                ) {
                    libraryVM.playAllTracks(tracks, startingFrom: track)
                }
                .withContextMenu(playerVM: playerVM, libraryVM: libraryVM)
                .listRowBackground(Color.auraBackground)
                .listRowSeparatorTint(.auraDivider)
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .background(Color.auraBackground)
        .navigationTitle(artistName)
    }
}

// MARK: - Playlist Detail View

struct PlaylistDetailView: View {
    @Bindable var playlist: Playlist
    @ObservedObject var libraryVM: LibraryViewModel
    @ObservedObject var playerVM: PlayerViewModel
    
    var body: some View {
        List {
            if !playlist.orderedTracks.isEmpty {
                Button {
                    libraryVM.playPlaylist(playlist)
                } label: {
                    HStack {
                        Image(systemName: "play.fill")
                            .foregroundColor(.auraPrimary)
                        Text("Play")
                            .foregroundColor(.auraPrimary)
                        Spacer()
                        Text("\(playlist.trackCount) songs")
                            .font(.auraCaption)
                            .foregroundColor(.auraTextTertiary)
                    }
                }
                .listRowBackground(Color.auraSurface)
            }
            
            ForEach(playlist.orderedTracks) { track in
                TrackRowView(
                    track: track,
                    isCurrentTrack: playerVM.currentTrack?.id == track.id
                ) {
                    libraryVM.playAllTracks(playlist.orderedTracks, startingFrom: track)
                }
                .listRowBackground(Color.auraBackground)
                .listRowSeparatorTint(.auraDivider)
            }
            .onDelete { offsets in
                let tracks = playlist.orderedTracks
                for index in offsets {
                    libraryVM.removeTrackFromPlaylist(tracks[index], playlist: playlist)
                }
            }
            .onMove { source, destination in
                playlist.moveTrack(from: source, to: destination)
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .background(Color.auraBackground)
        .navigationTitle(playlist.name)
        .toolbar {
            EditButton()
                .foregroundColor(.auraPrimary)
        }
    }
}
