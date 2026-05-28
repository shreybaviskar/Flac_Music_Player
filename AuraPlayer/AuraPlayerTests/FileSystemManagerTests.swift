//
//  FileSystemManagerTests.swift
//  AuraPlayerTests
//
//  Unit tests for FileSystemManager checking supported extensions,
//  and sandbox-safe folder bookmark saving, loading, and deletion.
//

import XCTest
@testable import AuraPlayer

final class FileSystemManagerTests: XCTestCase {
    
    private var sut: FileSystemManager!
    
    override func setUp() {
        super.setUp()
        sut = FileSystemManager.shared
        
        // Clean up any existing UserDefaults entries for our keys before testing
        let key = "com.auraplayer.savedFolderBookmarks"
        UserDefaults.standard.removeObject(forKey: key)
    }
    
    override func tearDown() {
        let key = "com.auraplayer.savedFolderBookmarks"
        UserDefaults.standard.removeObject(forKey: key)
        sut = nil
        super.tearDown()
    }
    
    // MARK: - Supported Extensions
    
    func test_supportedExtensions_containsCorrectExtensions() {
        let expected: Set<String> = ["flac", "mp3", "wav", "m4a", "caf"]
        XCTAssertEqual(FileSystemManager.supportedExtensions, expected)
    }
    
    func test_supportedExtensions_hasCorrectCount() {
        XCTAssertEqual(FileSystemManager.supportedExtensions.count, 5)
    }
    
    // MARK: - Folder Bookmarks Persistence
    
    func test_loadSavedFolderBookmarks_whenEmpty_returnsEmptyArray() {
        let bookmarks = sut.loadSavedFolderBookmarks()
        XCTAssertTrue(bookmarks.isEmpty)
    }
    
    func test_saveFolderBookmark_persistsBookmarkData() throws {
        // Use a real directory that exists on the device (temp directory)
        let tempDir = FileManager.default.temporaryDirectory
        
        try sut.saveFolderBookmark(for: tempDir)
        
        let savedBookmarks = sut.loadSavedFolderBookmarks()
        XCTAssertEqual(savedBookmarks.count, 1)
        
        // Resolving should point back to the same folder path
        guard let resolvedURL = sut.resolveBookmark(savedBookmarks[0]) else {
            XCTFail("Failed to resolve saved folder bookmark")
            return
        }
        
        XCTAssertEqual(resolvedURL.standardized.path, tempDir.standardized.path)
    }
    
    func test_saveFolderBookmark_preventsDuplicates() throws {
        let tempDir = FileManager.default.temporaryDirectory
        
        try sut.saveFolderBookmark(for: tempDir)
        try sut.saveFolderBookmark(for: tempDir) // Attempt duplicate
        
        let savedBookmarks = sut.loadSavedFolderBookmarks()
        XCTAssertEqual(savedBookmarks.count, 1, "Duplicate folder URLs should not be stored twice")
    }
    
    func test_removeFolderBookmark_deletesCorrectBookmark() throws {
        let tempDir = FileManager.default.temporaryDirectory
        
        try sut.saveFolderBookmark(for: tempDir)
        XCTAssertEqual(sut.loadSavedFolderBookmarks().count, 1)
        
        sut.removeFolderBookmark(at: 0)
        
        XCTAssertEqual(sut.loadSavedFolderBookmarks().count, 0)
    }
    
    func test_removeFolderBookmark_outOfBoundsIndex_doesNothing() throws {
        let tempDir = FileManager.default.temporaryDirectory
        try sut.saveFolderBookmark(for: tempDir)
        
        // Remove at index that doesn't exist
        sut.removeFolderBookmark(at: 5)
        
        XCTAssertEqual(sut.loadSavedFolderBookmarks().count, 1)
    }
    
    func test_resolvedSavedFolders_returnsValidFolderURLs() throws {
        let tempDir = FileManager.default.temporaryDirectory
        try sut.saveFolderBookmark(for: tempDir)
        
        let folders = sut.resolvedSavedFolders()
        XCTAssertEqual(folders.count, 1)
        XCTAssertEqual(folders.first?.standardized.path, tempDir.standardized.path)
    }
}
