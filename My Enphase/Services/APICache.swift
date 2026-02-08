//
//  APICache.swift
//  Enphase Monitor App
//
//  Persistent cache for API responses with 60-second TTL
//

import Foundation

#if canImport(UIKit)
import UIKit
#endif

class APICache {
    static let shared = APICache()
    
    private struct CacheEntry: Codable {
        let data: Data
        let timestamp: Date
        let statusCode: Int
        let headers: [String: String]
    }
    
    private var cache: [String: CacheEntry] = [:]
    private let cacheQueue = DispatchQueue(label: "com.enphase.apicache", attributes: .concurrent)
    private let cacheTTL: TimeInterval = 60 // 60 seconds
    private let maxEntries = 20
    private let cacheFileURL: URL
    private var saveCacheWorkItem: DispatchWorkItem?
    
    private init() {
        // Get cache directory
        let cacheDir = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        cacheFileURL = cacheDir.appendingPathComponent("enphase_api_cache.json")
        
        // Load cache from disk
        loadCacheFromDisk()
        
        // Observe memory warnings to clear cache
        #if canImport(UIKit)
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleMemoryWarning),
            name: UIApplication.didReceiveMemoryWarningNotification,
            object: nil
        )
        #endif
    }
    
    deinit {
        NotificationCenter.default.removeObserver(self)
    }
    
    @objc private func handleMemoryWarning() {
        cacheQueue.async(flags: .barrier) {
            DebugLogger.log("⚠️ Memory warning received - clearing in-memory cache")
            let count = self.cache.count
            self.cache.removeAll()
            DebugLogger.log("📦 Cleared \(count) cache entries from memory (disk cache preserved)")
        }
    }
    
    /// Check if cache entry exists and is still valid (< 60 seconds old)
    func getCachedResponse(for url: String) -> (data: Data, statusCode: Int, headers: [String: String])? {
        var result: (Data, Int, [String: String])?
        
        cacheQueue.sync {
            guard let entry = cache[url] else {
                DebugLogger.log("📦 Cache MISS - no entry found")
                return
            }
            
            let age = Date().timeIntervalSince(entry.timestamp)
            DebugLogger.log("📦 Cache entry found, age: \(String(format: "%.1f", age))s, TTL: \(cacheTTL)s")
            if age < cacheTTL {
                result = (entry.data, entry.statusCode, entry.headers)
                DebugLogger.log("📦 Cache HIT for \(redactURL(url)) (age: \(String(format: "%.1f", age))s)")
            } else {
                DebugLogger.log("📦 Cache EXPIRED for \(redactURL(url)) (age: \(String(format: "%.1f", age))s)")
            }
        }
        
        return result
    }
    
    /// Store a response in cache with current timestamp
    func cacheResponse(for url: String, data: Data, statusCode: Int, headers: [String: String]) {
        cacheQueue.async(flags: .barrier) {
            let now = Date()
            
            // Evict expired entries first to prevent unbounded growth
            self.cache = self.cache.filter { _, entry in
                now.timeIntervalSince(entry.timestamp) < self.cacheTTL
            }

            // Enforce maxEntries limit BEFORE adding new entry to prevent race conditions
            if self.cache.count >= self.maxEntries {
                let sorted = self.cache.sorted { $0.value.timestamp < $1.value.timestamp }
                let toRemove = self.cache.count - self.maxEntries + 1
                for (key, _) in sorted.prefix(toRemove) {
                    self.cache.removeValue(forKey: key)
                }
            }

            // Now safe to add new entry
            self.cache[url] = CacheEntry(
                data: data,
                timestamp: now,
                statusCode: statusCode,
                headers: headers
            )

            DebugLogger.log("📦 Cache STORED for \(self.redactURL(url)) (\(data.count) bytes) - Total cached entries: \(self.cache.count)")

            // Persist to disk
            self.saveCacheToDisk()
        }
    }
    
    /// Clear all cached entries
    func clearCache() {
        cacheQueue.async(flags: .barrier) {
            self.cache.removeAll()
            self.saveCacheToDisk()
            DebugLogger.log("📦 Cache CLEARED")
        }
    }
    
    /// Clear specific cached entry
    func clearCache(for url: String) {
        cacheQueue.async(flags: .barrier) {
            self.cache.removeValue(forKey: url)
            self.saveCacheToDisk()
            DebugLogger.log("📦 Cache CLEARED for \(self.redactURL(url))")
        }
    }
    
    /// Save cache to disk (debounced to reduce I/O frequency)
    private func saveCacheToDisk() {
        // Cancel any pending save operation
        saveCacheWorkItem?.cancel()
        
        // Schedule new save after 2 seconds of inactivity
        let workItem = DispatchWorkItem { [weak self] in
            guard let self = self else { return }
            do {
                let encoder = JSONEncoder()
                encoder.dateEncodingStrategy = .iso8601
                let data = try encoder.encode(self.cache)
                try data.write(to: self.cacheFileURL, options: .atomic)
                DebugLogger.log("💾 Cache saved to disk (\(self.cache.count) entries)")
            } catch {
                DebugLogger.log("⚠️ Failed to save cache to disk: \(error)")
            }
        }
        
        saveCacheWorkItem = workItem
        cacheQueue.asyncAfter(deadline: .now() + 2.0, execute: workItem)
    }
    
    /// Load cache from disk
    private func loadCacheFromDisk() {
        guard FileManager.default.fileExists(atPath: cacheFileURL.path) else {
            DebugLogger.log("💾 No cache file found (starting fresh)")
            return
        }

        // Check file size before loading to prevent OOM on bloated cache files
        if let attrs = try? FileManager.default.attributesOfItem(atPath: cacheFileURL.path),
           let fileSize = attrs[.size] as? Int,
           fileSize > 5_000_000 { // 5 MB safety limit
            DebugLogger.log("⚠️ Cache file too large (\(fileSize) bytes) - deleting and starting fresh")
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

            // Clean up expired entries
            let now = Date()
            cache = cache.filter { _, entry in
                now.timeIntervalSince(entry.timestamp) < cacheTTL
            }

            // Save cleaned cache back to disk to prevent file from growing unboundedly
            if cache.count < loadedCount {
                saveCacheToDisk()
                DebugLogger.log("💾 Cleaned cache saved to disk (removed \(loadedCount - cache.count) expired entries)")
            }

            if cache.count > 0 {
                DebugLogger.log("📦 \(cache.count) valid cached entries available")
            }
        } catch {
            DebugLogger.log("💾 Failed to load cache - deleting corrupt file and starting fresh")
            try? FileManager.default.removeItem(at: cacheFileURL)
            cache = [:]
        }
    }
    
    /// Redact sensitive information from URL for logging
    private func redactURL(_ url: String) -> String {
        var redacted = url
        // Redact API key
        if let keyRange = redacted.range(of: "key=") {
            let startIndex = keyRange.upperBound
            if let endIndex = redacted[startIndex...].firstIndex(of: "&") ?? redacted[startIndex...].indices.last {
                redacted.replaceSubrange(startIndex...endIndex, with: "***")
            }
        }
        // Just show endpoint for brevity
        if let pathStart = redacted.range(of: "/systems/") {
            let endpoint = String(redacted[pathStart.lowerBound...])
            if let queryStart = endpoint.firstIndex(of: "?") {
                return String(endpoint[..<queryStart])
            }
            return endpoint
        }
        return redacted
    }
}
