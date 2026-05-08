//
//  ContentView.swift
//  AuraPlayer
//
//  Root view — tab-based navigation with Library, Settings,
//  persistent MiniPlayer bar, and full-screen NowPlaying expansion.
//

import SwiftUI
import SwiftData

struct ContentView: View {
    @Environment(\.modelContext) private var modelContext
    
    @StateObject private var libraryVM = LibraryViewModel()
    @StateObject private var playerVM = PlayerViewModel()
    
    @Namespace private var playerNamespace
    @State private var isNowPlayingExpanded = false
    @State private var selectedTab: AppTab = .library
    
    var body: some View {
        ZStack(alignment: .bottom) {
            // Tab content
            TabView(selection: $selectedTab) {
                LibraryView(libraryVM: libraryVM, playerVM: playerVM)
                    .tag(AppTab.library)
                    .tabItem {
                        Label("Library", systemImage: "music.note.house.fill")
                    }
                
                SettingsView(libraryVM: libraryVM, playerVM: playerVM)
                    .tag(AppTab.settings)
                    .tabItem {
                        Label("Settings", systemImage: "gearshape.fill")
                    }
            }
            .tint(.auraPrimary)
            
            // Mini player bar (above tab bar)
            VStack(spacing: 0) {
                Spacer()
                
                if !isNowPlayingExpanded {
                    MiniPlayerView(
                        playerVM: playerVM,
                        isExpanded: $isNowPlayingExpanded,
                        namespace: playerNamespace
                    )
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    .padding(.bottom, 49) // Tab bar height
                }
            }
            .animation(.spring(response: 0.35, dampingFraction: 0.86), value: playerVM.currentTrack != nil)
            
            // Full-screen Now Playing (overlay)
            if isNowPlayingExpanded {
                NowPlayingView(playerVM: playerVM)
                    .transition(.move(edge: .bottom))
                    .zIndex(10)
                    .gesture(
                        DragGesture(minimumDistance: 20, coordinateSpace: .local)
                            .onEnded { value in
                                if value.translation.height > 100 {
                                    withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                                        isNowPlayingExpanded = false
                                    }
                                }
                            }
                    )
            }
        }
        .preferredColorScheme(.dark)
        .ignoresSafeArea(.keyboard)
    }
}

// MARK: - App Tabs

enum AppTab: String, CaseIterable {
    case library = "Library"
    case settings = "Settings"
}

// MARK: - Preview

#Preview {
    ContentView()
        .modelContainer(for: [
            Track.self,
            Album.self,
            Playlist.self,
            EQPreset.self
        ], inMemory: true)
}
