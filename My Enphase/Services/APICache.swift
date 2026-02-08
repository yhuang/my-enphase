//
//  APICache.swift
//  Enphase Monitor App
//
//  Persistent cache for API responses with 60-second TTL
//

import Foundation

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
    
    private init() {
        // Get cache directory
        let cacheDir = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        cacheFileURL = cacheDir.appendingPathComponent("enphase_api_cache.json")
        
        // Load cache from disk
        loadCacheFromDisk()
    }
    
    /// Check if cache entry exists and is still valid (< 60 seconds old)
    func getCachedResponse(for url: String) -> (data: Data, statusCode: Int, headers: [String: String])? {
        var result: (Data, Int, [String: String])?
        
        cacheQueue.sync {
            guard let entry = cache[url] else {
                print("📦 Cache MISS - no entry found")
                return
            }
            
            let age = Date().timeIntervalSince(entry.timestamp)
            print("📦 Cache entry found, age: \(String(format: "%.1f", age))s, TTL: \(cacheTTL)s")
            if age < cacheTTL {
                result = (entry.data, entry.statusCode, entry.headers)
                print("📦 Cache HIT for \(redactURL(url)) (age: \(String(format: "%.1f", age))s)")
            } else {
                print("📦 Cache EXPIRED for \(redactURL(url)) (age: \(String(format: "%.1f", age))s)")
            }
        }
        
        return result
    }
    
    /// Store a response in cache with current timestamp
    func cacheResponse(for url: String, data: Data, statusCode: Int, headers: [String: String]) {
        cacheQueue.async(flags: .barrier) {
            // Evict expired entries before adding new ones to prevent unbounded growth
            let now = Date()
            self.cache = self.cache.filter { _, entry in
                now.timeIntervalSince(entry.timestamp) < self.cacheTTL
            }

            self.cache[url] = CacheEntry(
                data: data,
                timestamp: now,
                statusCode: statusCode,
                headers: headers
            )

            // If still over the cap, remove oldest entries
            if self.cache.count > self.maxEntries {
                let sorted = self.cache.sorted { $0.value.timestamp < $1.value.timestamp }
                let toRemove = self.cache.count - self.maxEntries
                for (key, _) in sorted.prefix(toRemove) {
                    self.cache.removeValue(forKey: key)
                }
            }

            print("📦 Cache STORED for \(self.redactURL(url)) (\(data.count) bytes) - Total cached entries: \(self.cache.count)")

            // Persist to disk
            self.saveCacheToDisk()
        }
    }
    
    /// Clear all cached entries
    func clearCache() {
        cacheQueue.async(flags: .barrier) {
            self.cache.removeAll()
            self.saveCacheToDisk()
            print("📦 Cache CLEARED")
        }
    }
    
    /// Clear specific cached entry
    func clearCache(for url: String) {
        cacheQueue.async(flags: .barrier) {
            self.cache.removeValue(forKey: url)
            self.saveCacheToDisk()
            print("📦 Cache CLEARED for \(self.redactURL(url))")
        }
    }
    
    /// Save cache to disk
    private func saveCacheToDisk() {
        do {
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            let data = try encoder.encode(cache)
            try data.write(to: cacheFileURL, options: .atomic)
            print("💾 Cache saved to disk (\(cache.count) entries)")
        } catch {
            print("⚠️ Failed to save cache to disk: \(error)")
        }
    }
    
    /// Load cache from disk
    private func loadCacheFromDisk() {
        guard FileManager.default.fileExists(atPath: cacheFileURL.path) else {
            print("💾 No cache file found (starting fresh)")
            return
        }

        // Check file size before loading to prevent OOM on bloated cache files
        if let attrs = try? FileManager.default.attributesOfItem(atPath: cacheFileURL.path),
           let fileSize = attrs[.size] as? Int,
           fileSize > 5_000_000 { // 5 MB safety limit
            print("⚠️ Cache file too large (\(fileSize) bytes) - deleting and starting fresh")
            try? FileManager.default.removeItem(at: cacheFileURL)
            return
        }

        do {
            let data = try Data(contentsOf: cacheFileURL)
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            cache = try decoder.decode([String: CacheEntry].self, from: data)
            let loadedCount = cache.count
            print("💾 Cache loaded from disk (\(loadedCount) entries)")

            // Clean up expired entries
            let now = Date()
            cache = cache.filter { _, entry in
                now.timeIntervalSince(entry.timestamp) < cacheTTL
            }

            // Save cleaned cache back to disk to prevent file from growing unboundedly
            if cache.count < loadedCount {
                saveCacheToDisk()
                print("💾 Cleaned cache saved to disk (removed \(loadedCount - cache.count) expired entries)")
            }

            if cache.count > 0 {
                print("📦 \(cache.count) valid cached entries available")
            }
        } catch {
            print("💾 Failed to load cache - deleting corrupt file and starting fresh")
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
