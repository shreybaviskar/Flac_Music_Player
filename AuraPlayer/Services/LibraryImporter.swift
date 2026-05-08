//
//  LibraryImporter.swift
//  AuraPlayer
//
//  Orchestrates the full import pipeline: scan → extract → persist.
//  Bridges FileSystemManager and MetadataExtractor to SwiftData models.
//

import Foundation
import SwiftData
import UIKit

/// Orchestrates the end-to-end import of audio files into the SwiftData library.
///
/// Pipeline:
/// 1. `FileSystemManager` scans a folder → `[ScannedFile]`
/// 2. `MetadataExtractor` extracts tags + audio props → `ExtractedMetadata`
/// 3. `LibraryImporter` creates/updates `Track` and `Album` entities in SwiftData
///
/// This class runs on a background `ModelActor` to avoid blocking the main thread
/// during large library imports (thousands of files).
@MainActor
final class LibraryImporter: ObservableObject {
    
    // MARK: - Dependencies
    
    private let fileManager = FileSystemManager.shared
    private let extractor = MetadataExtractor.shared
    
    // MARK: - Progress
    
    @Published var scanProgress = ScanProgress()
    
    // MARK: - Import Results
    
    @Published var lastImportedCount: Int = 0
    @Published var lastSkippedCount: Int = 0
    
    // MARK: - Public API
    
    /// Imports all audio files from a user-selected folder into the library.
    ///
    /// - Parameters:
    ///   - folderURL: The security-scoped URL from the document picker.
    ///   - modelContext: The SwiftData model context to insert entities into.
    /// - Returns: The number of new tracks imported.
    @discardableResult
    func importFolder(
        _ folderURL: URL,
        into modelContext: ModelContext
    ) async throws -> Int {
        
        scanProgress.reset()
        scanProgress.isScanning = true
        
        defer {
            scanProgress.isScanning = false
        }
        
        // 1. Save the folder bookmark for future re-scans.
        try? fileManager.saveFolderBookmark(for: folderURL)
        
        // 2. Begin security-scoped access and scan.
        let didStartAccess = folderURL.startAccessingSecurityScopedResource()
        defer {
            if didStartAccess {
                folderURL.stopAccessingSecurityScopedResource()
            }
        }
        
        let scannedFiles = try await fileManager.scanDirectory(
            at: folderURL,
            createBookmarks: true
        )
        
        scanProgress.totalFiles = scannedFiles.count
        
        // 3. Fetch existing file paths to skip duplicates.
        let existingPaths = fetchExistingFilePaths(from: modelContext)
        
        // 4. Process each file: extract metadata → create Track + Album.
        var importedCount = 0
        var skippedCount = 0
        
        for scannedFile in scannedFiles {
            let fileName = scannedFile.url.lastPathComponent
            scanProgress.currentFileName = fileName
            
            // Skip if already in library.
            if existingPaths.contains(scannedFile.url.path) {
                skippedCount += 1
                scanProgress.processedFiles += 1
                continue
            }
            
            do {
                let metadata = try await extractor.extract(from: scannedFile)
                
                let track = createTrack(
                    from: scannedFile,
                    metadata: metadata,
                    modelContext: modelContext
                )
                
                // Link to album (create if needed).
                linkTrackToAlbum(track, metadata: metadata, modelContext: modelContext)
                
                modelContext.insert(track)
                importedCount += 1
                
            } catch {
                scanProgress.errors.append(ScanError(
                    fileName: fileName,
                    message: error.localizedDescription
                ))
            }
            
            scanProgress.processedFiles += 1
        }
        
        // 5. Persist all changes.
        try modelContext.save()
        
        lastImportedCount = importedCount
        lastSkippedCount = skippedCount
        
        return importedCount
    }
    
    /// Re-scans all previously saved folders to detect new files.
    ///
    /// - Parameter modelContext: The SwiftData model context.
    /// - Returns: The total number of new tracks imported across all folders.
    @discardableResult
    func rescanSavedFolders(into modelContext: ModelContext) async throws -> Int {
        let savedFolders = fileManager.resolvedSavedFolders()
        var totalImported = 0
        
        for folderURL in savedFolders {
            let count = try await importFolder(folderURL, into: modelContext)
            totalImported += count
        }
        
        return totalImported
    }
    
    /// Removes tracks whose backing files no longer exist on disk.
    /// Returns the number of tracks removed.
    @discardableResult
    func pruneOrphanedTracks(from modelContext: ModelContext) -> Int {
        let descriptor = FetchDescriptor<Track>()
        guard let allTracks = try? modelContext.fetch(descriptor) else { return 0 }
        
        var removedCount = 0
        
        for track in allTracks {
            guard let bookmarkData = track.bookmarkData else {
                // No bookmark → can't verify → skip (or remove if strict).
                continue
            }
            
            if !fileManager.fileExists(bookmarkData: bookmarkData) {
                modelContext.delete(track)
                removedCount += 1
            }
        }
        
        if removedCount > 0 {
            try? modelContext.save()
        }
        
        return removedCount
    }
    
    // MARK: - Private Helpers
    
    /// Fetches all existing file paths to quickly detect duplicates.
    private func fetchExistingFilePaths(from modelContext: ModelContext) -> Set<String> {
        let descriptor = FetchDescriptor<Track>()
        guard let existingTracks = try? modelContext.fetch(descriptor) else {
            return []
        }
        return Set(existingTracks.map(\.filePath))
    }
    
    /// Creates a `Track` entity from a scanned file and its extracted metadata.
    private func createTrack(
        from scannedFile: ScannedFile,
        metadata: ExtractedMetadata,
        modelContext: ModelContext
    ) -> Track {
        
        // Use the file name (without extension) as a fallback title.
        let fallbackTitle = scannedFile.url.deletingPathExtension().lastPathComponent
        
        return Track(
            filePath: scannedFile.url.path,
            fileExtension: scannedFile.fileExtension,
            fileSize: scannedFile.fileSize,
            bookmarkData: scannedFile.bookmarkData,
            title: metadata.title ?? fallbackTitle,
            artistName: metadata.artistName ?? metadata.albumArtist ?? "Unknown Artist",
            albumTitle: metadata.albumTitle ?? "Unknown Album",
            genre: metadata.genre,
            composer: metadata.composer,
            year: metadata.year,
            trackNumber: metadata.trackNumber,
            discNumber: metadata.discNumber,
            lyrics: metadata.lyrics,
            duration: metadata.duration,
            sampleRate: metadata.sampleRate,
            bitDepth: metadata.bitDepth,
            channelCount: metadata.channelCount,
            codec: scannedFile.codec,
            bitrate: metadata.bitrate,
            artworkData: metadata.artworkData,
            dateAdded: Date()
        )
    }
    
    /// Links a track to its album, creating the album entity if it doesn't exist.
    private func linkTrackToAlbum(
        _ track: Track,
        metadata: ExtractedMetadata,
        modelContext: ModelContext
    ) {
        let albumTitle = track.albumTitle
        let albumArtist = metadata.albumArtist ?? track.artistName
        
        // Skip "Unknown Album" to avoid a giant catch-all album.
        guard albumTitle != "Unknown Album" else { return }
        
        // Try to find an existing album with the same title + artist.
        let predicate = #Predicate<Album> { album in
            album.title == albumTitle && album.artistName == albumArtist
        }
        var descriptor = FetchDescriptor(predicate: predicate)
        descriptor.fetchLimit = 1
        
        if let existingAlbum = try? modelContext.fetch(descriptor).first {
            // Add track to the existing album.
            track.album = existingAlbum
            
            // Update album artwork if it doesn't have one yet.
            if existingAlbum.artworkData == nil, let artwork = track.artworkData {
                existingAlbum.artworkData = artwork
            }
            
            // Update year if not set.
            if existingAlbum.year == nil, let year = track.year {
                existingAlbum.year = year
            }
            
            // Update genre if not set.
            if existingAlbum.genre == nil, let genre = track.genre {
                existingAlbum.genre = genre
            }
            
        } else {
            // Create a new album.
            let album = Album(
                title: albumTitle,
                artistName: albumArtist,
                year: metadata.year,
                genre: metadata.genre,
                artworkData: metadata.artworkData,
                tracks: [track],
                dateAdded: Date()
            )
            modelContext.insert(album)
            track.album = album
        }
    }
}
