//
//  FileSystemManager.swift
//  AuraPlayer
//
//  Handles directory scanning, security-scoped resource access,
//  and the UIDocumentPickerViewController bridge for SwiftUI.
//

import Foundation
import UIKit
import UniformTypeIdentifiers
import SwiftUI

// MARK: - Scan Result

/// The result of scanning a single audio file on disk.
/// This is a lightweight value type passed from the scanner to the
/// MetadataExtractor — no SwiftData dependencies at this layer.
struct ScannedFile: Sendable {
    let url: URL
    let fileExtension: String
    let fileSize: Int64
    let bookmarkData: Data?
    let codec: AudioCodec
}

// MARK: - Scan Progress

/// Observable progress reporting for library scans.
@MainActor
final class ScanProgress: ObservableObject {
    @Published var totalFiles: Int = 0
    @Published var processedFiles: Int = 0
    @Published var currentFileName: String = ""
    @Published var isScanning: Bool = false
    @Published var errors: [ScanError] = []
    
    var progressFraction: Double {
        guard totalFiles > 0 else { return 0 }
        return Double(processedFiles) / Double(totalFiles)
    }
    
    func reset() {
        totalFiles = 0
        processedFiles = 0
        currentFileName = ""
        isScanning = false
        errors = []
    }
}

/// Represents an error encountered while scanning a specific file.
struct ScanError: Identifiable, Sendable {
    let id = UUID()
    let fileName: String
    let message: String
}

// MARK: - FileSystemManager

/// Manages all file system operations: directory access, recursive scanning,
/// and security-scoped bookmark creation/resolution.
///
/// This class is designed to be used from an async context. All heavy I/O
/// (directory enumeration, bookmark creation) is offloaded from the main actor.
final class FileSystemManager: Sendable {
    
    /// Shared singleton instance.
    static let shared = FileSystemManager()
    
    /// Supported audio file extensions.
    static let supportedExtensions: Set<String> = ["flac", "mp3", "wav", "m4a", "caf"]
    
    /// The UserDefaults key where we store folder bookmark data
    /// so we can re-access user-selected folders across launches.
    private static let savedFoldersKey = "com.auraplayer.savedFolderBookmarks"
    
    private init() {}
    
    // MARK: - Directory Scanning
    
    /// Recursively scans a directory for supported audio files.
    ///
    /// - Parameters:
    ///   - directoryURL: The root directory to scan. Must be a security-scoped URL
    ///     if obtained from a document picker.
    ///   - createBookmarks: Whether to create security-scoped bookmarks for each file.
    ///     Set to `true` for first-time imports; `false` for re-scans of bookmarked folders.
    /// - Returns: An array of `ScannedFile` structs ready for metadata extraction.
    func scanDirectory(
        at directoryURL: URL,
        createBookmarks: Bool = true
    ) async throws -> [ScannedFile] {
        
        // Begin security-scoped access for the directory.
        let didStartAccess = directoryURL.startAccessingSecurityScopedResource()
        defer {
            if didStartAccess {
                directoryURL.stopAccessingSecurityScopedResource()
            }
        }
        
        // Use FileManager to enumerate all files recursively.
        let fileManager = FileManager.default
        
        guard let enumerator = fileManager.enumerator(
            at: directoryURL,
            includingPropertiesForKeys: [.fileSizeKey, .isRegularFileKey, .isDirectoryKey],
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        ) else {
            throw FileSystemError.cannotAccessDirectory(directoryURL.path)
        }
        
        var scannedFiles: [ScannedFile] = []
        
        for case let fileURL as URL in enumerator {
            // Skip directories
            let resourceValues = try? fileURL.resourceValues(forKeys: [.isRegularFileKey])
            guard resourceValues?.isRegularFile == true else { continue }
            
            // Check if the extension is supported
            let ext = fileURL.pathExtension.lowercased()
            guard Self.supportedExtensions.contains(ext),
                  let codec = AudioCodec.from(extension: ext) else {
                continue
            }
            
            // Get file size
            let attributes = try? fileManager.attributesOfItem(atPath: fileURL.path)
            let fileSize = (attributes?[.size] as? Int64) ?? 0
            
            // Create a security-scoped bookmark if requested
            var bookmarkData: Data? = nil
            if createBookmarks {
                bookmarkData = try? fileURL.bookmarkData(
                    options: .minimalBookmark,
                    includingResourceValuesForKeys: nil,
                    relativeTo: nil
                )
            }
            
            let scannedFile = ScannedFile(
                url: fileURL,
                fileExtension: ext,
                fileSize: fileSize,
                bookmarkData: bookmarkData,
                codec: codec
            )
            
            scannedFiles.append(scannedFile)
        }
        
        return scannedFiles
    }
    
    // MARK: - Folder Bookmark Persistence
    
    /// Saves a folder's security-scoped bookmark for later re-access.
    /// This allows re-scanning the folder on subsequent app launches
    /// without requiring the user to re-pick it.
    func saveFolderBookmark(for folderURL: URL) throws {
        let bookmarkData = try folderURL.bookmarkData(
            options: .minimalBookmark,
            includingResourceValuesForKeys: nil,
            relativeTo: nil
        )
        
        var savedBookmarks = loadSavedFolderBookmarks()
        
        // Avoid duplicates — check if we already have a bookmark that resolves to the same path
        let existingPaths = savedBookmarks.compactMap { resolveBookmark($0)?.path }
        if !existingPaths.contains(folderURL.path) {
            savedBookmarks.append(bookmarkData)
            UserDefaults.standard.set(savedBookmarks, forKey: Self.savedFoldersKey)
        }
    }
    
    /// Returns all previously saved folder bookmarks.
    func loadSavedFolderBookmarks() -> [Data] {
        UserDefaults.standard.array(forKey: Self.savedFoldersKey) as? [Data] ?? []
    }
    
    /// Resolves a folder bookmark back to a URL.
    func resolveBookmark(_ bookmarkData: Data) -> URL? {
        var isStale = false
        let url = try? URL(
            resolvingBookmarkData: bookmarkData,
            options: [],
            relativeTo: nil,
            bookmarkDataIsStale: &isStale
        )
        return url
    }
    
    /// Removes a saved folder bookmark.
    func removeFolderBookmark(at index: Int) {
        var savedBookmarks = loadSavedFolderBookmarks()
        guard index < savedBookmarks.count else { return }
        savedBookmarks.remove(at: index)
        UserDefaults.standard.set(savedBookmarks, forKey: Self.savedFoldersKey)
    }
    
    /// Returns all saved folders as resolved URLs (filtering out any stale ones).
    func resolvedSavedFolders() -> [URL] {
        loadSavedFolderBookmarks().compactMap { resolveBookmark($0) }
    }
    
    // MARK: - File Access Helpers
    
    /// Resolves a track's bookmark and begins security-scoped access.
    /// The caller MUST call `stopAccessing(_:)` when done.
    func startAccessing(_ bookmarkData: Data) -> URL? {
        var isStale = false
        guard let url = try? URL(
            resolvingBookmarkData: bookmarkData,
            options: [],
            relativeTo: nil,
            bookmarkDataIsStale: &isStale
        ) else {
            return nil
        }
        
        _ = url.startAccessingSecurityScopedResource()
        return url
    }
    
    /// Ends security-scoped access for a URL.
    func stopAccessing(_ url: URL) {
        url.stopAccessingSecurityScopedResource()
    }
    
    // MARK: - File Existence Check
    
    /// Checks if a file still exists at the bookmarked location.
    func fileExists(bookmarkData: Data) -> Bool {
        guard let url = resolveBookmark(bookmarkData) else { return false }
        return FileManager.default.fileExists(atPath: url.path)
    }
}

// MARK: - Errors

enum FileSystemError: LocalizedError {
    case cannotAccessDirectory(String)
    case bookmarkCreationFailed(String)
    case fileNotFound(String)
    
    var errorDescription: String? {
        switch self {
        case .cannotAccessDirectory(let path):
            return "Cannot access directory: \(path)"
        case .bookmarkCreationFailed(let path):
            return "Failed to create bookmark for: \(path)"
        case .fileNotFound(let path):
            return "File not found: \(path)"
        }
    }
}

// MARK: - SwiftUI Document Picker Bridge

/// A SwiftUI-compatible wrapper around `UIDocumentPickerViewController`
/// configured for folder selection. When the user picks a folder,
/// the `onFolderPicked` closure fires with the security-scoped URL.
struct FolderPickerView: UIViewControllerRepresentable {
    
    /// Called when the user selects a folder.
    let onFolderPicked: (URL) -> Void
    
    /// Called when the user cancels the picker.
    var onCancel: (() -> Void)? = nil
    
    func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
        // iOS 14+: Use UTType.folder for directory picking
        let picker = UIDocumentPickerViewController(forOpeningContentTypes: [UTType.folder])
        picker.allowsMultipleSelection = false
        picker.delegate = context.coordinator
        return picker
    }
    
    func updateUIViewController(_ uiViewController: UIDocumentPickerViewController, context: Context) {
        // No updates needed
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator(onFolderPicked: onFolderPicked, onCancel: onCancel)
    }
    
    // MARK: - Coordinator
    
    final class Coordinator: NSObject, UIDocumentPickerDelegate {
        let onFolderPicked: (URL) -> Void
        let onCancel: (() -> Void)?
        
        init(onFolderPicked: @escaping (URL) -> Void, onCancel: (() -> Void)?) {
            self.onFolderPicked = onFolderPicked
            self.onCancel = onCancel
        }
        
        func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
            guard let folderURL = urls.first else { return }
            onFolderPicked(folderURL)
        }
        
        func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
            onCancel?()
        }
    }
}
