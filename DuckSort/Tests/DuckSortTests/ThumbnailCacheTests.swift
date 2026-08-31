import Testing
import Foundation
import AppKit
@testable import DuckSort

// MARK: - ThumbnailCacheTests

struct ThumbnailCacheTests {

    // MARK: - ThumbnailCache (memory tier)

    @Test
    func memoryCache_insertAndRetrieve() throws {
        let cache = ThumbnailCache()
        let url = URL(fileURLWithPath: "/tmp/test_photo.jpg")
        let size = CGSize(width: 300, height: 300)
        let image = NSImage(size: NSSize(width: 300, height: 300))

        #expect(cache.image(for: url, size: size) == nil)
        cache.insert(image, for: url, size: size)
        try #require(cache.image(for: url, size: size) != nil)
    }

    @Test
    func memoryCache_differentSizesAreIndependent() throws {
        let cache = ThumbnailCache()
        let url = URL(fileURLWithPath: "/tmp/photo.jpg")
        let smallSize = CGSize(width: 128, height: 128)
        let largeSize = CGSize(width: 600, height: 600)

        let small = NSImage(size: NSSize(width: 128, height: 128))
        let large = NSImage(size: NSSize(width: 600, height: 600))

        cache.insert(small, for: url, size: smallSize)
        cache.insert(large, for: url, size: largeSize)

        #expect(cache.image(for: url, size: smallSize)?.size.width == 128)
        #expect(cache.image(for: url, size: largeSize)?.size.width == 600)
    }

    @Test
    func memoryCache_evictAll() throws {
        let cache = ThumbnailCache()
        let url = URL(fileURLWithPath: "/tmp/photo_evict.jpg")
        let size = CGSize(width: 300, height: 300)
        let image = NSImage(size: NSSize(width: 300, height: 300))

        cache.insert(image, for: url, size: size)
        try #require(cache.image(for: url, size: size) != nil)
        cache.evictAll()
        #expect(cache.image(for: url, size: size) == nil)
    }

    @Test
    func memoryCache_removeSpecificEntry() throws {
        let cache = ThumbnailCache()
        let url = URL(fileURLWithPath: "/tmp/photo_remove.jpg")
        let size = CGSize(width: 300, height: 300)
        let image = NSImage(size: NSSize(width: 300, height: 300))

        cache.insert(image, for: url, size: size)
        try #require(cache.image(for: url, size: size) != nil)
        cache.remove(for: url, size: size)
        #expect(cache.image(for: url, size: size) == nil)
    }

    @Test
    func memoryCache_differentURLsSeparateEntries() throws {
        let cache = ThumbnailCache()
        let size = CGSize(width: 300, height: 300)
        let urlA = URL(fileURLWithPath: "/tmp/a.jpg")
        let urlB = URL(fileURLWithPath: "/tmp/b.jpg")
        let imgA = NSImage(size: NSSize(width: 100, height: 100))
        let imgB = NSImage(size: NSSize(width: 200, height: 200))

        cache.insert(imgA, for: urlA, size: size)
        cache.insert(imgB, for: urlB, size: size)

        #expect(cache.image(for: urlA, size: size)?.size.width == 100)
        #expect(cache.image(for: urlB, size: size)?.size.width == 200)
        // Removing A should not affect B
        cache.remove(for: urlA, size: size)
        #expect(cache.image(for: urlA, size: size) == nil)
        try #require(cache.image(for: urlB, size: size) != nil)
    }

    // MARK: - DiskThumbnailCache

    @Test
    func diskCache_insertAndRetrieve() async throws {
        // Use a non-singleton to avoid polluting the shared cache
        let cache = DiskThumbnailCache.shared
        let tmpURL = URL(fileURLWithPath: "/tmp/ducksort_test_thumb_\(UUID()).jpg")
        let size = CGSize(width: 64, height: 64)

        // Create a minimal NSImage with pixel data
        let image = NSImage(size: NSSize(width: 64, height: 64))
        image.lockFocus()
        NSColor.red.setFill()
        NSBezierPath.fill(NSRect(x: 0, y: 0, width: 64, height: 64))
        image.unlockFocus()

        // Clean up before test
        await cache.remove(for: tmpURL, size: size)

        // Miss before insertion
        let miss = await cache.image(for: tmpURL, size: size)
        #expect(miss == nil)

        // Insert then retrieve
        await cache.insert(image, for: tmpURL, size: size)
        let hit = await cache.image(for: tmpURL, size: size)
        try #require(hit != nil)

        // Cleanup
        await cache.remove(for: tmpURL, size: size)
    }

    @Test
    func diskCache_evictAll_emptiesCache() async throws {
        let cache = DiskThumbnailCache.shared
        let tmpURL = URL(fileURLWithPath: "/tmp/ducksort_evict_test_\(UUID()).jpg")
        let size = CGSize(width: 32, height: 32)
        let image = NSImage(size: NSSize(width: 32, height: 32))
        image.lockFocus()
        NSColor.blue.setFill()
        NSBezierPath.fill(NSRect(x: 0, y: 0, width: 32, height: 32))
        image.unlockFocus()

        await cache.insert(image, for: tmpURL, size: size)
        await cache.evictAll()

        let hit = await cache.image(for: tmpURL, size: size)
        #expect(hit == nil)
    }

    @Test
    func diskCache_remove_specificEntry() async throws {
        let cache = DiskThumbnailCache.shared
        let urlA = URL(fileURLWithPath: "/tmp/ducksort_a_\(UUID()).jpg")
        let urlB = URL(fileURLWithPath: "/tmp/ducksort_b_\(UUID()).jpg")
        let size = CGSize(width: 32, height: 32)
        let imageA = NSImage(size: NSSize(width: 32, height: 32))
        imageA.lockFocus()
        NSColor.green.setFill()
        NSBezierPath.fill(NSRect(x: 0, y: 0, width: 32, height: 32))
        imageA.unlockFocus()
        let imageB = NSImage(size: NSSize(width: 32, height: 32))
        imageB.lockFocus()
        NSColor.orange.setFill()
        NSBezierPath.fill(NSRect(x: 0, y: 0, width: 32, height: 32))
        imageB.unlockFocus()

        await cache.insert(imageA, for: urlA, size: size)
        await cache.insert(imageB, for: urlB, size: size)

        // Remove only A
        await cache.remove(for: urlA, size: size)

        let hitA = await cache.image(for: urlA, size: size)
        let hitB = await cache.image(for: urlB, size: size)
        #expect(hitA == nil)
        try #require(hitB != nil)

        // Cleanup
        await cache.remove(for: urlB, size: size)
    }

    // MARK: - AsyncSemaphore

    @Test
    func asyncSemaphore_limitsConcurrency() async {
        let limit = 3
        let semaphore = AsyncSemaphore(limit: limit)
        let counter = LockProtected(0)
        let maxObserved = LockProtected(0)

        await withTaskGroup(of: Void.self) { group in
            for _ in 0..<10 {
                group.addTask {
                    try? await semaphore.acquire()
                    let current = counter.modify { $0 + 1 }
                    maxObserved.modify { max($0, current) }
                    // Simulate work
                    try? await Task.sleep(nanoseconds: 1_000_000)
                    counter.modify { $0 - 1 }
                    await semaphore.release()
                }
            }
        }

        #expect(maxObserved.value <= limit)
    }
}

// MARK: - Test utilities

/// Simple thread-safe wrapper for reading/mutating a value in concurrent tests.
final class LockProtected<T>: @unchecked Sendable {
    private var _value: T
    private let lock = NSLock()
    init(_ value: T) { _value = value }
    var value: T { lock.withLock { _value } }
    @discardableResult
    func modify(_ transform: (T) -> T) -> T {
        lock.withLock {
            _value = transform(_value)
            return _value
        }
    }
}
