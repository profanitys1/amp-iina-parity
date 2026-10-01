// Aagedal Media Player
// Copyright © 2026 Truls Aagedal
// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation
import SQLite3

/// Manages cached enhanced video files with LRU eviction.
actor EnhancementCache {
    private let cacheDirectory: URL
    private let metadataDatabaseURL: URL
    private let maxSizeBytes: Int64
    
    private nonisolated(unsafe) var db: OpaquePointer?
    
    init(cacheDirectory: URL? = nil, maxSizeBytes: Int64 = 50_000_000_000) {  // 50 GB default
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        self.cacheDirectory = cacheDirectory ?? appSupport
            .appendingPathComponent("amp", isDirectory: true)
            .appendingPathComponent("Enhanced", isDirectory: true)
        self.metadataDatabaseURL = self.cacheDirectory.appendingPathComponent("metadata.sqlite3")
        self.maxSizeBytes = maxSizeBytes
        
        // Setup must happen synchronously in init
        Self.setupCacheDirectory(at: self.cacheDirectory)
        Self.setupDatabase(at: metadataDatabaseURL, db: &db)
    }
    
    deinit {
        if let db = db {
            sqlite3_close(db)
        }
    }
    
    private nonisolated static func setupCacheDirectory(at url: URL) {
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    }
    
    private nonisolated static func setupDatabase(at url: URL, db: inout OpaquePointer?) {
        guard sqlite3_open(url.path, &db) == SQLITE_OK else {
            print("Failed to open metadata database")
            return
        }
        
        let createTableSQL = """
            CREATE TABLE IF NOT EXISTS enhanced_videos (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                original_path TEXT UNIQUE NOT NULL,
                enhanced_path TEXT NOT NULL,
                original_mod_date REAL NOT NULL,
                original_file_size INTEGER NOT NULL,
                enhanced_file_size INTEGER NOT NULL,
                enhancement_date REAL NOT NULL,
                profile TEXT NOT NULL,
                bitrate INTEGER NOT NULL,
                source_width REAL,
                source_height REAL,
                pixel_format TEXT,
                last_accessed REAL NOT NULL
            );
            CREATE INDEX IF NOT EXISTS idx_last_accessed ON enhanced_videos(last_accessed);
        """
        
        var errMsg: UnsafeMutablePointer<CChar>?
        if sqlite3_exec(db, createTableSQL, nil, nil, &errMsg) != SQLITE_OK {
            let error = errMsg.map { String(cString: $0) } ?? "Unknown error"
            sqlite3_free(errMsg)
            print("Failed to create table: \(error)")
        }
    }
    
    /// Stores an enhanced video in the cache.
    func store(
        originalURL: URL,
        enhancedURL: URL,
        parameters: EnhancementParameters
    ) async throws {
        guard let db = db else {
            throw CacheError.databaseNotAvailable
        }
        
        // Get file attributes
        let originalAttrs = try FileManager.default.attributesOfItem(atPath: originalURL.path)
        let enhancedAttrs = try FileManager.default.attributesOfItem(atPath: enhancedURL.path)
        
        let originalModDate = originalAttrs[.modificationDate] as? Date ?? Date()
        let originalFileSize = (originalAttrs[.size] as? NSNumber)?.int64Value ?? 0
        let enhancedFileSize = (enhancedAttrs[.size] as? NSNumber)?.int64Value ?? 0
        
        // Generate cache filename
        let cacheFilename = "\(UUID().uuidString).mp4"
        let cachedURL = cacheDirectory.appendingPathComponent(cacheFilename)
        
        // Copy enhanced file to cache
        try FileManager.default.copyItem(at: enhancedURL, to: cachedURL)
        
        // Insert metadata
        let insertSQL = """
            INSERT OR REPLACE INTO enhanced_videos
            (original_path, enhanced_path, original_mod_date, original_file_size,
             enhanced_file_size, enhancement_date, profile, bitrate,
             source_width, source_height, pixel_format, last_accessed)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?);
        """
        
        var stmt: OpaquePointer?
        defer { sqlite3_finalize(stmt) }
        
        guard sqlite3_prepare_v2(db, insertSQL, -1, &stmt, nil) == SQLITE_OK else {
            throw CacheError.prepareFailed(String(cString: sqlite3_errmsg(db)))
        }
        
        let now = Date().timeIntervalSince1970
        
        sqlite3_bind_text(stmt, 1, (originalURL.path as NSString).utf8String, -1, nil)
        sqlite3_bind_text(stmt, 2, (cachedURL.path as NSString).utf8String, -1, nil)
        sqlite3_bind_double(stmt, 3, originalModDate.timeIntervalSince1970)
        sqlite3_bind_int64(stmt, 4, originalFileSize)
        sqlite3_bind_int64(stmt, 5, enhancedFileSize)
        sqlite3_bind_double(stmt, 6, now)
        sqlite3_bind_text(stmt, 7, (parameters.profile.rawValue as NSString).utf8String, -1, nil)
        sqlite3_bind_int64(stmt, 8, parameters.bitrate)
        
        if let width = parameters.sourceWidth {
            sqlite3_bind_double(stmt, 9, Double(width))
        } else {
            sqlite3_bind_null(stmt, 9)
        }
        
        if let height = parameters.sourceHeight {
            sqlite3_bind_double(stmt, 10, Double(height))
        } else {
            sqlite3_bind_null(stmt, 10)
        }
        
        if let pixelFormat = parameters.pixelFormat {
            sqlite3_bind_text(stmt, 11, (pixelFormat as NSString).utf8String, -1, nil)
        } else {
            sqlite3_bind_null(stmt, 11)
        }
        
        sqlite3_bind_double(stmt, 12, now)
        
        guard sqlite3_step(stmt) == SQLITE_DONE else {
            throw CacheError.insertFailed(String(cString: sqlite3_errmsg(db)))
        }
        
        // Enforce size limit
        try await enforceSizeLimit()
    }
    
    /// Retrieves the cached enhanced video URL for an original video.
    func getEnhancedURL(for originalURL: URL) async -> URL? {
        guard let db = db else { return nil }
        
        let selectSQL = """
            SELECT enhanced_path, original_mod_date FROM enhanced_videos
            WHERE original_path = ?;
        """
        
        var stmt: OpaquePointer?
        defer { sqlite3_finalize(stmt) }
        
        guard sqlite3_prepare_v2(db, selectSQL, -1, &stmt, nil) == SQLITE_OK else {
            return nil
        }
        
        sqlite3_bind_text(stmt, 1, (originalURL.path as NSString).utf8String, -1, nil)
        
        guard sqlite3_step(stmt) == SQLITE_ROW else {
            return nil
        }
        
        guard let enhancedPathCStr = sqlite3_column_text(stmt, 0) else {
            return nil
        }
        
        let enhancedPath = String(cString: enhancedPathCStr)
        let cachedModDate = Date(timeIntervalSince1970: sqlite3_column_double(stmt, 1))
        
        // Verify original file hasn't changed
        guard let currentAttrs = try? FileManager.default.attributesOfItem(atPath: originalURL.path),
              let currentModDate = currentAttrs[.modificationDate] as? Date else {
            return nil
        }
        
        // Invalidate if source changed (more than 1 second difference)
        if abs(currentModDate.timeIntervalSince(cachedModDate)) > 1.0 {
            await invalidate(originalURL: originalURL)
            return nil
        }
        
        // Verify enhanced file still exists
        guard FileManager.default.fileExists(atPath: enhancedPath) else {
            await invalidate(originalURL: originalURL)
            return nil
        }
        
        // Update last accessed time
        await updateLastAccessed(originalURL: originalURL)
        
        return URL(fileURLWithPath: enhancedPath)
    }
    
    /// Invalidates the cache entry for an original video.
    private func invalidate(originalURL: URL) async {
        guard let db = db else { return }
        
        // Get enhanced path before deleting
        let selectSQL = "SELECT enhanced_path FROM enhanced_videos WHERE original_path = ?;"
        var selectStmt: OpaquePointer?
        defer { sqlite3_finalize(selectStmt) }
        
        guard sqlite3_prepare_v2(db, selectSQL, -1, &selectStmt, nil) == SQLITE_OK else {
            return
        }
        
        sqlite3_bind_text(selectStmt, 1, (originalURL.path as NSString).utf8String, -1, nil)
        
        if sqlite3_step(selectStmt) == SQLITE_ROW,
           let enhancedPathCStr = sqlite3_column_text(selectStmt, 0) {
            let enhancedPath = String(cString: enhancedPathCStr)
            try? FileManager.default.removeItem(atPath: enhancedPath)
        }
        
        // Delete database entry
        let deleteSQL = "DELETE FROM enhanced_videos WHERE original_path = ?;"
        var deleteStmt: OpaquePointer?
        defer { sqlite3_finalize(deleteStmt) }
        
        guard sqlite3_prepare_v2(db, deleteSQL, -1, &deleteStmt, nil) == SQLITE_OK else {
            return
        }
        
        sqlite3_bind_text(deleteStmt, 1, (originalURL.path as NSString).utf8String, -1, nil)
        sqlite3_step(deleteStmt)
    }
    
    /// Updates the last accessed timestamp for an original video.
    private func updateLastAccessed(originalURL: URL) async {
        guard let db = db else { return }
        
        let updateSQL = "UPDATE enhanced_videos SET last_accessed = ? WHERE original_path = ?;"
        var stmt: OpaquePointer?
        defer { sqlite3_finalize(stmt) }
        
        guard sqlite3_prepare_v2(db, updateSQL, -1, &stmt, nil) == SQLITE_OK else {
            return
        }
        
        let now = Date().timeIntervalSince1970
        sqlite3_bind_double(stmt, 1, now)
        sqlite3_bind_text(stmt, 2, (originalURL.path as NSString).utf8String, -1, nil)
        
        sqlite3_step(stmt)
    }
    
    /// Enforces the cache size limit by evicting LRU entries.
    private func enforceSizeLimit() async throws {
        var currentSize = await totalSize()
        
        guard currentSize > maxSizeBytes else { return }
        
        // Select LRU entries
        let selectSQL = """
            SELECT original_path, enhanced_path, enhanced_file_size FROM enhanced_videos
            ORDER BY last_accessed ASC;
        """
        
        guard let db = db else { return }
        
        var stmt: OpaquePointer?
        defer { sqlite3_finalize(stmt) }
        
        guard sqlite3_prepare_v2(db, selectSQL, -1, &stmt, nil) == SQLITE_OK else {
            return
        }
        
        while sqlite3_step(stmt) == SQLITE_ROW && currentSize > maxSizeBytes {
            guard let originalPathCStr = sqlite3_column_text(stmt, 0),
                  let enhancedPathCStr = sqlite3_column_text(stmt, 1) else {
                continue
            }
            
            let originalPath = String(cString: originalPathCStr)
            let enhancedPath = String(cString: enhancedPathCStr)
            let fileSize = sqlite3_column_int64(stmt, 2)
            
            // Delete enhanced file
            try? FileManager.default.removeItem(atPath: enhancedPath)
            
            // Delete database entry
            let deleteSQL = "DELETE FROM enhanced_videos WHERE original_path = ?;"
            var deleteStmt: OpaquePointer?
            defer { sqlite3_finalize(deleteStmt) }
            
            if sqlite3_prepare_v2(db, deleteSQL, -1, &deleteStmt, nil) == SQLITE_OK {
                sqlite3_bind_text(deleteStmt, 1, (originalPath as NSString).utf8String, -1, nil)
                sqlite3_step(deleteStmt)
            }
            
            currentSize -= fileSize
        }
    }
    
    /// Calculates the total size of all cached enhanced videos.
    func totalSize() async -> Int64 {
        guard let db = db else { return 0 }
        
        let selectSQL = "SELECT SUM(enhanced_file_size) FROM enhanced_videos;"
        var stmt: OpaquePointer?
        defer { sqlite3_finalize(stmt) }
        
        guard sqlite3_prepare_v2(db, selectSQL, -1, &stmt, nil) == SQLITE_OK else {
            return 0
        }
        
        guard sqlite3_step(stmt) == SQLITE_ROW else {
            return 0
        }
        
        return sqlite3_column_int64(stmt, 0)
    }
    
    enum CacheError: Error {
        case databaseNotAvailable
        case prepareFailed(String)
        case insertFailed(String)
    }
}
