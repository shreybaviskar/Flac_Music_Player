//
//  AuraPlayerApp.swift
//  AuraPlayer
//
//  A high-fidelity offline music player for iOS.
//

import SwiftUI
import SwiftData

// MARK: - Info.plist Requirements
// ================================
// The following keys MUST be set in your Xcode project:
//
// 1. UIBackgroundModes: ["audio"]
//    → Enables background audio playback.
//
// 2. UIFileSharingEnabled: true
//    → Exposes the app's Documents folder in Finder/iTunes.
//
// 3. LSSupportsOpeningDocumentsInPlace: true
//    → Allows opening documents in-place from Files app.
//
// 4. NSDocumentsFolderUsageDescription:
//    "AuraPlayer needs access to your music files to build your library."
//
// 5. CFBundleDocumentTypes:
//    → Register FLAC, WAV, AIFF, MP3 as supported document types.
//
// 6. UISupportedExternalAccessoryProtocols (optional):
//    → For MFi DAC accessories.
// ================================

@main
struct AuraPlayerApp: App {
    
    /// UIKit AppDelegate for early-launch setup (audio session, library load).
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    
    /// The shared SwiftData model container for the entire app.
    var sharedModelContainer: ModelContainer = {
        let schema = Schema([
            Track.self,
            Album.self,
            Playlist.self,
            EQPreset.self
        ])
        
        let modelConfiguration = ModelConfiguration(
            schema: schema,
            isStoredInMemoryOnly: false
        )
        
        do {
            return try ModelContainer(
                for: schema,
                configurations: [modelConfiguration]
            )
        } catch {
            fatalError("Could not create ModelContainer: \(error)")
        }
    }()
    
    var body: some Scene {
        WindowGroup {
            if NSClassFromString("XCTestCase") != nil {
                Text("Running Unit Tests")
            } else {
                ContentView()
                    .preferredColorScheme(.dark)
            }
        }
        .modelContainer(sharedModelContainer)
    }
}

// MARK: - AppDelegate

class AppDelegate: NSObject, UIApplicationDelegate {
    
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        
        if NSClassFromString("XCTestCase") != nil {
            return true
        }
        
        // Configure the audio session for high-fidelity playback.
        // Must happen before any audio engine operations.
        Task { @MainActor in
            AudioSessionManager.shared.configureSession()
        }
        
        return true
    }
    
    /// Handle audio files opened via "Open In" or Files app.
    func application(
        _ app: UIApplication,
        open url: URL,
        options: [UIApplication.OpenURLOptionsKey: Any] = [:]
    ) -> Bool {
        if url.isFileURL {
            // The LibraryViewModel will handle importing this file.
            NotificationCenter.default.post(
                name: .didReceiveExternalAudioFile,
                object: nil,
                userInfo: ["url": url]
            )
        }
        return true
    }
}

// MARK: - Notifications

extension Notification.Name {
    /// Posted when an audio file is opened from an external source (Files, AirDrop, etc.).
    static let didReceiveExternalAudioFile = Notification.Name("didReceiveExternalAudioFile")
}
