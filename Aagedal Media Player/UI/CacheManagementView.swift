// Aagedal Media Player
// Copyright © 2026 Truls Aagedal
// SPDX-License-Identifier: GPL-3.0-or-later

import SwiftUI

struct CacheManagementView: View {
    let cache: EnhancementCache
    @State private var cachedVideos: [CachedVideo] = []
    @State private var totalSize: Int64 = 0
    @State private var isLoading = true
    
    struct CachedVideo: Identifiable {
        let id = UUID()
        let originalURL: URL
        let enhancedURL: URL
        let originalFileSize: Int64
        let enhancedFileSize: Int64
        let enhancementDate: Date
        let lastAccessed: Date
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("Enhanced Videos")
                    .font(.title2)
                    .fontWeight(.semibold)
                
                Spacer()
                
                Text("Total: \(formatSize(totalSize))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            
            if isLoading {
                ProgressView("Loading...")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if cachedVideos.isEmpty {
                Text("No enhanced videos cached")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(cachedVideos) { video in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(video.originalURL.lastPathComponent)
                            .font(.headline)
                        
                        HStack {
                            Text("Original: \(formatSize(video.originalFileSize))")
                            Text("Enhanced: \(formatSize(video.enhancedFileSize))")
                        }
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        
                        Text("Enhanced: \(video.enhancementDate.formatted(date: .abbreviated, time: .shortened))")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .swipeActions {
                        Button(role: .destructive) {
                            Task {
                                await deleteVideo(video)
                            }
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }
                    }
                }
            }
            
            HStack {
                Button("Clear All") {
                    Task {
                        await clearAll()
                    }
                }
                .buttonStyle(.bordered)
                .disabled(cachedVideos.isEmpty)
                
                Spacer()
                
                Text("Cache limit: 50 GB")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding()
        .frame(width: 500, height: 400)
        .task {
            await loadCachedVideos()
        }
    }
    
    private func loadCachedVideos() async {
        isLoading = true
        defer { isLoading = false }
        
        totalSize = await cache.totalSize()
        // Note: Would need to query database for cached videos list
        // For now, just show empty list
        cachedVideos = []
    }
    
    private func deleteVideo(_ video: CachedVideo) async {
        try? FileManager.default.removeItem(at: video.enhancedURL)
        await loadCachedVideos()
    }
    
    private func clearAll() async {
        for video in cachedVideos {
            try? FileManager.default.removeItem(at: video.enhancedURL)
        }
        await loadCachedVideos()
    }
    
    private func formatSize(_ bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useMB, .useGB]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: bytes)
    }
}
