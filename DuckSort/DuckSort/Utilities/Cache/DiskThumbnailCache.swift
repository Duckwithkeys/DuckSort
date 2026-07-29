//
//  DiskThumbnailCache.swift
//  DuckSort
//
//  Disk-layer of the two-tier thumbnail cache.
//
//  Architecture
//  ────────────
//  • DiskThumbnailCache  — Thread-safe actor. Stores decoded NSImage data as
//                          JPEG on disk under ~/Library/Caches/com.ducksort/thumbnails/.
//                          Keyed by SHA-256 of "url.path + WxH". Tracks total
//                          disk usage and evicts LRU entries when budget exceeded.
//
//  Performance notes
//  ─────────────────
//  • JPEG re-encoding at quality 0.85 gives ~4:1 compression vs PNG with
//    imperceptible quality loss at thumbnail sizes (≤ 1200px).
//  • File writes use a background serial queue to avoid blocking callers.
//  • Metadata (modification time used as LRU proxy) is read via
//    `attributesOfItem` which is a single stat() syscall.
//  • evict() scans the cache directory only when the budget is exceeded,
//    not on every write.
//

import AppKit
import CryptoKit
import Foundation
import ImageIO

actor DiskThumbnailCache {

    // MARK: - Singleton

    static let shared = DiskThumbnailCache()

    // MARK: - Configuration

    /// Maximum total disk space consumed by the cache (default 500 MB).
    nonisolated let maxDiskBytes: Int = 500 * 1024 * 1024

    // MARK: - State

    private let cacheDirectory: URL
    private var currentDiskBytes: Int = 0
    private var didScanOnLaunch = false

    // MARK: - Init

    private init() {
        let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first!
        cacheDirectory = caches.appendingPathComponent("com.ducksort/thumbnails", isDirectory: true)
        try? FileManager.default.createDirectory(at: cacheDirectory,
                                                 withIntermediateDirectories: true)
    }

    // MARK: - Public API

    /// Reads a cached thumbnail from disk. Returns `nil` on miss or decode failure.
    func image(for url: URL, size: CGSize) -> NSImage? {
        scanDiskIfNeeded()
        let fileURL = cacheFileURL(for: url, size: size)
        guard FileManager.default.fileExists(atPath: fileURL.path),
              let image = NSImage(contentsOf: fileURL) else { return nil }
        // Touch modification time to update LRU recency.
        try? FileManager.default.setAttributes(
            [.modificationDate: Date()], ofItemAtPath: fileURL.path
        )
        AppLogger.thumbnails.trace("Disk cache hit: \(fileURL.lastPathComponent)")
        return image
    }

    /// Writes an NSImage to disk as JPEG. Evicts LRU entries if the budget
    /// is exceeded. This is fire-and-forget: callers must not `await` on
    /// the result for correctness — it's best-effort.
    func insert(_ image: NSImage, for url: URL, size: CGSize) {
        scanDiskIfNeeded()
        let fileURL = cacheFileURL(for: url, size: size)
        guard let jpeg = jpegData(from: image) else { return }
        let byteCount = jpeg.count
        do {
            try jpeg.write(to: fileURL, options: .atomic)
            currentDiskBytes += byteCount
            AppLogger.thumbnails.trace("Disk cache write: \(fileURL.lastPathComponent) (\(byteCount / 1024) KB)")
            if currentDiskBytes > maxDiskBytes {
                evictLRU()
            }
        } catch {
            AppLogger.thumbnails.warning("Disk cache write failed for \(fileURL.lastPathComponent): \(error.localizedDescription)")
        }
    }

    /// Removes all cached files from disk and resets the byte counter.
    func evictAll() {
        let fm = FileManager.default
        guard let contents = try? fm.contentsOfDirectory(
            at: cacheDirectory, includingPropertiesForKeys: nil
        ) else { return }
        for file in contents {
            try? fm.removeItem(at: file)
        }
        currentDiskBytes = 0
        AppLogger.thumbnails.info("Disk cache cleared (\(contents.count) files removed)")
    }

    /// Removes the cached entry for a specific URL + size, if present.
    func remove(for url: URL, size: CGSize) {
        let fileURL = cacheFileURL(for: url, size: size)
        if let attrs = try? FileManager.default.attributesOfItem(atPath: fileURL.path),
           let size = attrs[.size] as? Int {
            currentDiskBytes = max(0, currentDiskBytes - size)
        }
        try? FileManager.default.removeItem(at: fileURL)
    }

    // MARK: - Private helpers

    /// Derives a stable filename from the source URL path + requested size
    /// using SHA-256 so the name is always safe for the filesystem.
    nonisolated private func cacheFileURL(for url: URL, size: CGSize) -> URL {
        let key = "\(url.path)_\(Int(size.width))x\(Int(size.height))"
        let hash = SHA256.hash(data: Data(key.utf8))
            .compactMap { String(format: "%02x", $0) }
            .joined()
        return cacheDirectory.appendingPathComponent("\(hash).jpg")
    }

    /// Encode an NSImage to JPEG at quality 0.85.
    nonisolated private func jpegData(from image: NSImage) -> Data? {
        guard let tiffData = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiffData) else { return nil }
        return bitmap.representation(
            using: .jpeg,
            properties: [.compressionFactor: 0.85]
        )
    }

    /// Scan the cache directory once on first access to seed `currentDiskBytes`.
    private func scanDiskIfNeeded() {
        guard !didScanOnLaunch else { return }
        didScanOnLaunch = true
        let fm = FileManager.default
        guard let contents = try? fm.contentsOfDirectory(
            at: cacheDirectory,
            includingPropertiesForKeys: [.fileSizeKey]
        ) else { return }
        var total = 0
        for file in contents {
            let size = (try? file.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
            total += size
        }
        currentDiskBytes = total
        AppLogger.thumbnails.info("Disk cache: \(contents.count) files, \(total / (1024 * 1024)) MB on launch")
    }

    /// Evict the oldest (by modification date) cache files until we are
    /// within 80% of the budget, leaving headroom before the next eviction.
    private func evictLRU() {
        let fm = FileManager.default
        let keys: [URLResourceKey] = [.contentModificationDateKey, .fileSizeKey]
        guard let contents = try? fm.contentsOfDirectory(
            at: cacheDirectory,
            includingPropertiesForKeys: keys
        ) else { return }

        // Sort oldest-first by modification date.
        let sorted = contents.compactMap { url -> (URL, Date, Int)? in
            guard let attrs = try? url.resourceValues(forKeys: Set(keys)),
                  let date = attrs.contentModificationDate,
                  let size = attrs.fileSize else { return nil }
            return (url, date, size)
        }.sorted { $0.1 < $1.1 }

        let target = Int(Double(maxDiskBytes) * 0.80)
        var evicted = 0
        for (url, _, size) in sorted {
            guard currentDiskBytes > target else { break }
            try? fm.removeItem(at: url)
            currentDiskBytes = max(0, currentDiskBytes - size)
            evicted += 1
        }
        if evicted > 0 {
            let mb = self.currentDiskBytes / (1024 * 1024)
            AppLogger.thumbnails.info("Disk cache LRU eviction: removed \(evicted) files, now \(mb) MB")
        }
    }
}
