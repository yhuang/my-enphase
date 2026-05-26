//
//  Cache.swift
//  My Enphase
//
//  Persistent cache for API responses with 60-second TTL
//

import Foundation

#if canImport(UIKit)
import UIKit
#endif

// Actor-based cache providing automatic serialization of all reads and writes.
// maxEntries supports 4 systems × 5 endpoints with one fetch of headroom.
actor Cache {
    static let shared = Cache()

    private struct CacheEntry: Codable {
        let data: Data
        let timestamp: Date
        let statusCode: Int
        let headers: [String: String]
    }

    private var cache: [String: CacheEntry] = [:]
    // Intentionally matches apiCooldownTTL in SiteDataService.swift — a cache entry
    // older than this is served as stale while a fresh fetch runs.
    private let cacheTTL: TimeInterval = apiCooldownTTL
    // Supports 4 systems × 5 endpoints with 5 entries of headroom.
    private let maxEntries = 25
    private let cacheFileURL: URL
    private var saveDiskTask: Task<Void, Never>?
    #if canImport(UIKit)
    private var memoryWarningObserver: (any NSObjectProtocol)?
    #endif

    private init() {
        let cacheDir = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        cacheFileURL = cacheDir.appendingPathComponent("enphase_cache.json")

        Task { await loadFromDisk() }

        #if canImport(UIKit)
        memoryWarningObserver = NotificationCenter.default.addObserver(
            forName: UIApplication.didReceiveMemoryWarningNotification,
            object: nil,
            queue: nil
        ) { [weak self] _ in
            guard let self else { return }
            Task { await self.evictAll() }
        }
        #endif
    }

    // MARK: - Public interface

    func getCachedResponse(for url: String) -> (data: Data, statusCode: Int, headers: [String: String])? {
        guard let entry = cache[url] else {
            DebugLogger.log("📦 Cache MISS - no entry found")
            return nil
        }
        let age = Date().timeIntervalSince(entry.timestamp)
        DebugLogger.log("📦 Cache entry found, age: \(String(format: "%.1f", age))s, TTL: \(cacheTTL)s")
        guard age < cacheTTL else {
            DebugLogger.log("📦 Cache EXPIRED for \(redactURL(url)) (age: \(String(format: "%.1f", age))s)")
            return nil
        }
        DebugLogger.log("📦 Cache HIT for \(redactURL(url)) (age: \(String(format: "%.1f", age))s)")
        return (entry.data, entry.statusCode, entry.headers)
    }

    func cacheResponse(for url: String, data: Data, statusCode: Int, headers: [String: String]) {
        let now = Date()
        cache = cache.filter { now.timeIntervalSince($0.value.timestamp) < cacheTTL }
        if cache.count >= maxEntries {
            let sorted = cache.sorted { $0.value.timestamp < $1.value.timestamp }
            for (key, _) in sorted.prefix(cache.count - maxEntries + 1) {
                cache.removeValue(forKey: key)
            }
        }
        cache[url] = CacheEntry(data: data, timestamp: now, statusCode: statusCode, headers: headers)
        DebugLogger.log("📦 Cache STORED for \(redactURL(url)) (\(data.count) bytes) — \(cache.count) entries total")
        scheduleSaveToDisk()
    }

    func clearCache() {
        cache.removeAll()
        scheduleSaveToDisk()
        DebugLogger.log("📦 Cache CLEARED")
    }

    func clearCache(for url: String) {
        cache.removeValue(forKey: url)
        scheduleSaveToDisk()
        DebugLogger.log("📦 Cache CLEARED for \(redactURL(url))")
    }

    // MARK: - Memory pressure

    private func evictAll() {
        let count = cache.count
        cache.removeAll()
        DebugLogger.log("⚠️ Memory warning — cleared \(count) entries from memory (disk cache preserved)")
    }

    // MARK: - Persistence

    // Debounced: cancels any pending save before scheduling a new one 2 s out.
    private func scheduleSaveToDisk() {
        saveDiskTask?.cancel()
        saveDiskTask = Task {
            do {
                try await Task.sleep(nanoseconds: 2_000_000_000)
            } catch {
                return // cancelled before the delay elapsed
            }
            persistToDisk()
        }
    }

    // Captures the current cache snapshot and writes it off-actor so I/O doesn't
    // block the actor's serial queue.
    private func persistToDisk() {
        let snapshot = cache
        let url = cacheFileURL
        Task.detached {
            do {
                let encoder = JSONEncoder()
                encoder.dateEncodingStrategy = .iso8601
                let data = try encoder.encode(snapshot)
                try data.write(to: url, options: .atomic)
                DebugLogger.log("💾 Cache saved to disk (\(snapshot.count) entries)")
            } catch {
                DebugLogger.log("⚠️ Failed to save cache to disk: \(error)")
            }
        }
    }

    private func loadFromDisk() {
        guard FileManager.default.fileExists(atPath: cacheFileURL.path) else {
            DebugLogger.log("💾 No cache file found (starting fresh)")
            return
        }

        let maxCacheBytes = 5_000_000
        if let attrs = try? FileManager.default.attributesOfItem(atPath: cacheFileURL.path),
           let fileSize = attrs[.size] as? Int,
           fileSize > maxCacheBytes {
            DebugLogger.log("⚠️ Cache file too large (\(fileSize) bytes) — deleting and starting fresh")
            try? FileManager.default.removeItem(at: cacheFileURL)
            return
        }

        do {
            let data = try Data(contentsOf: cacheFileURL)
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            cache = try decoder.decode([String: CacheEntry].self, from: data)
            let loadedCount = cache.count
            DebugLogger.log("💾 Cache loaded from disk (\(loadedCount) entries)")

            let now = Date()
            cache = cache.filter { now.timeIntervalSince($0.value.timestamp) < cacheTTL }
            if cache.count < loadedCount {
                scheduleSaveToDisk()
                DebugLogger.log("💾 Removed \(loadedCount - cache.count) expired entries")
            }
            if cache.count > 0 {
                DebugLogger.log("📦 \(cache.count) valid cached entries available")
            }
        } catch {
            DebugLogger.log("💾 Failed to load cache — deleting corrupt file and starting fresh")
            try? FileManager.default.removeItem(at: cacheFileURL)
            cache = [:]
        }
    }

    // MARK: - Helpers

    private func redactURL(_ url: String) -> String {
        if let range = url.range(of: "/systems/") {
            let path = String(url[range.lowerBound...])
            return path.components(separatedBy: "?").first ?? path
        }
        return url
    }
}
