//
//  ThumbnailView.swift
//  PhotomatorSort
//
//  Performance-critical path: thumbnails must load without ever blocking the
//  main thread or triggering the beach ball.
//
//  Architecture
//  ───────────
//  • ThumbnailView       — SwiftUI view (main actor). Observes ThumbnailLoader.
//  • ThumbnailLoader     — @MainActor ObservableObject. Only stores the result
//                          image; delegates ALL I/O to ThumbnailService.
//  • ThumbnailService    — Global actor (not MainActor). Owns an async semaphore
//                          that caps concurrent decodes to 4. All CGImageSource,
//                          QL, and NSWorkspace calls happen here, never on main.
//  • ThumbnailCache      — Thread-safe NSCache wrapper. Reads & writes happen
//                          on ThumbnailService's executor, never on main.
//

import AppKit
import ImageIO
import QuickLookThumbnailing
import SwiftUI

// MARK: - View

struct ThumbnailView: View {
    let url: URL?
    var size: CGSize = CGSize(width: 600, height: 600)
    var cornerRadius: CGFloat = Theme.Radius.xl
    @StateObject private var loader = ThumbnailLoader()

    var body: some View {
        Color.clear
            .overlay {
                ZStack {
                    // Placeholder
                    RoundedRectangle(cornerRadius: cornerRadius)
                        .fill(
                            LinearGradient(
                                colors: [
                                    Theme.Color.cellBackground,
                                    Theme.Color.separator.opacity(0.6)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )

                    if let image = loader.image {
                        Image(nsImage: image)
                            .resizable()
                            .scaledToFill()
                    } else {
                        Image(systemName: "photo")
                            .font(Theme.Font.iconHero)
                            .foregroundStyle(Theme.Color.textTertiary)
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
            }
        .task(id: url) {
            guard let url else { return }
            
            // Fast cache hit
            if let hit = ThumbnailCache.global.image(for: url, size: size) {
                loader.image = hit
                return
            }

            loader.image = nil

            let scale = NSScreen.main?.backingScaleFactor ?? 2

            // Dynamic LOD Adaptive Preloading:
            // Fast 128px proxy when scrolling, full size on scroll settle
            if ScrollStateObserver.shared.isScrolling {
                let fastSize = CGSize(width: 128, height: 128)
                if let fastProxy = await ThumbnailService.shared.thumbnail(for: url, size: fastSize, scale: scale) {
                    guard !Task.isCancelled else { return }
                    loader.image = fastProxy
                }
                for await isScrolling in ScrollStateObserver.shared.$isScrolling.values {
                    if !isScrolling { break }
                }
            }

            guard !Task.isCancelled else { return }

            if let result = await ThumbnailService.shared.thumbnail(for: url, size: size, scale: scale) {
                guard !Task.isCancelled else { return }
                loader.image = result
            }
        }
    }
}

// MARK: - Loader

@MainActor
final class ThumbnailLoader: ObservableObject {
    @Published var image: NSImage?
}

// MARK: - Service

@globalActor
actor ThumbnailActor {
    static let shared = ThumbnailActor()
}

@ThumbnailActor
final class ThumbnailService {
    static let shared = ThumbnailService()

    private let cache = ThumbnailCache()
    private let semaphore = AsyncSemaphore(limit: 6)

    private init() {}

    func thumbnail(for url: URL?, size: CGSize, scale: CGFloat = 2.0) async -> NSImage? {
        guard let url else { return nil }

        if let hit = ThumbnailCache.global.image(for: url, size: size) { return hit }

        do {
            try Task.checkCancellation()
            // Acquire will throw if cancelled while waiting
            try await semaphore.acquire()
        } catch {
            return nil
        }
        
        do {
            let result = try await decode(url: url, size: size, scale: scale)
            await semaphore.release()
            return result
        } catch {
            await semaphore.release()
            return nil
        }
    }

    private func decode(url: URL, size: CGSize, scale: CGFloat) async throws -> NSImage? {
        try Task.checkCancellation()

        let maxPixels = max(size.width, size.height) * scale
        let ext = url.pathExtension.lowercased()
        let alwaysCreate = FileExtension.rawLikeExtensions.contains(ext)

        // 1. Fast path: ImageIO
        if let cgImage = await decodeWithImageIO(url: url, maxPixels: maxPixels, alwaysCreate: alwaysCreate) {
            try Task.checkCancellation()
            let ns = NSImage(cgImage: cgImage, size: NSSize(width: cgImage.width, height: cgImage.height))
            ThumbnailCache.global.insert(ns, for: url, size: size)
            return ns
        }

        // 1b. HEIF / HEIC fallback using optimized load
        if FileExtension.heifLikeExtensions.contains(ext) {
            if let cg = await loadWithImageIOFallback(url: url, maxPixels: maxPixels) {
                try Task.checkCancellation()
                let ns = NSImage(cgImage: cg, size: NSSize(width: cg.width, height: cg.height))
                ThumbnailCache.global.insert(ns, for: url, size: size)
                return ns
            }
        }

        // 2. Slow path: QuickLook
        try Task.checkCancellation()
        
        let request = QLThumbnailGenerator.Request(
            fileAt: url,
            size: size,
            scale: scale,
            representationTypes: .thumbnail
        )
        
        do {
            let rep = try await QLThumbnailGenerator.shared.generateBestRepresentation(for: request)
            try Task.checkCancellation()
            ThumbnailCache.global.insert(rep.nsImage, for: url, size: size)
            return rep.nsImage
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            let icon = NSWorkspace.shared.icon(forFile: url.path)
            ThumbnailCache.global.insert(icon, for: url, size: size)
            return icon
        }
    }

    nonisolated private static let decodeQueue = DispatchQueue(label: "com.ducksort.imageio.decode", qos: .userInitiated, attributes: .concurrent)

    nonisolated private func decodeWithImageIO(url: URL, maxPixels: CGFloat, alwaysCreate: Bool) async -> CGImage? {
        await withCheckedContinuation { continuation in
            Self.decodeQueue.async {
                let options = [kCGImageSourceShouldCache: false] as CFDictionary
                guard let source = CGImageSourceCreateWithURL(url as CFURL, options) else {
                    continuation.resume(returning: nil)
                    return
                }
                guard !Task.isCancelled else {
                    continuation.resume(returning: nil)
                    return
                }
                let decodeOptions: [CFString: Any] = [
                    (alwaysCreate
                        ? kCGImageSourceCreateThumbnailFromImageAlways
                        : kCGImageSourceCreateThumbnailFromImageIfAbsent): true,
                    kCGImageSourceThumbnailMaxPixelSize: maxPixels,
                    kCGImageSourceCreateThumbnailWithTransform: true,
                    kCGImageSourceShouldCacheImmediately: true,
                    kCGImageSourceShouldAllowFloat: true
                ]
                let thumb = CGImageSourceCreateThumbnailAtIndex(source, 0, decodeOptions as CFDictionary)
                continuation.resume(returning: thumb)
            }
        }
    }

    nonisolated private func loadWithImageIOFallback(url: URL, maxPixels: CGFloat) async -> CGImage? {
        await withCheckedContinuation { continuation in
            Self.decodeQueue.async {
                let options = [kCGImageSourceShouldCache: false] as CFDictionary
                guard let source = CGImageSourceCreateWithURL(url as CFURL, options) else {
                    continuation.resume(returning: nil)
                    return
                }
                
                let decodeOptions: [CFString: Any] = [
                    kCGImageSourceCreateThumbnailFromImageAlways: true,
                    kCGImageSourceThumbnailMaxPixelSize: maxPixels,
                    kCGImageSourceCreateThumbnailWithTransform: true,
                    kCGImageSourceShouldCacheImmediately: true
                ]
                if let thumb = CGImageSourceCreateThumbnailAtIndex(source, 0, decodeOptions as CFDictionary) {
                    continuation.resume(returning: thumb)
                    return
                }

                guard let cgImage = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
                    continuation.resume(returning: nil)
                    return
                }
                
                let width = CGFloat(cgImage.width)
                let height = CGFloat(cgImage.height)
                let scale = min(maxPixels / max(width, height), 1.0)
                guard scale < 1.0 else {
                    continuation.resume(returning: cgImage)
                    return
                }
                
                let targetW = Int(width * scale)
                let targetH = Int(height * scale)
                
                guard let colorSpace = cgImage.colorSpace,
                      let context = CGContext(
                          data: nil,
                          width: targetW,
                          height: targetH,
                          bitsPerComponent: cgImage.bitsPerComponent,
                          bytesPerRow: 0,
                          space: colorSpace,
                          bitmapInfo: cgImage.bitmapInfo.rawValue
                      ) else {
                    continuation.resume(returning: cgImage)
                    return
                }
                      
                context.interpolationQuality = .high
                context.draw(cgImage, in: CGRect(x: 0, y: 0, width: targetW, height: targetH))
                continuation.resume(returning: context.makeImage())
            }
        }
    }
}

// MARK: - Thread-safe cache

final class ThumbnailCache {
    nonisolated(unsafe) static let global = ThumbnailCache()
    private let cache = NSCache<NSString, NSImage>()

    init() {
        let physicalMemory = ProcessInfo.processInfo.physicalMemory
        let memoryGB = Int(physicalMemory / (1024 * 1024 * 1024))
        if memoryGB >= 32 {
            cache.countLimit = 2500
            cache.totalCostLimit = 400 * 1024 * 1024
        } else if memoryGB >= 16 {
            cache.countLimit = 1500
            cache.totalCostLimit = 200 * 1024 * 1024
        } else {
            cache.countLimit = 800
            cache.totalCostLimit = 120 * 1024 * 1024
        }
    }

    private func cacheKey(for url: URL, size: CGSize) -> NSString {
        "\(url.path)_\(Int(size.width))x\(Int(size.height))" as NSString
    }

    func image(for url: URL, size: CGSize) -> NSImage? {
        cache.object(forKey: cacheKey(for: url, size: size))
    }

    func insert(_ image: NSImage, for url: URL, size: CGSize) {
        let rep = image.representations.first
        let pw = rep?.pixelsWide ?? Int(image.size.width)
        let ph = rep?.pixelsHigh ?? Int(image.size.height)
        let cost = Int(max(pw * ph * 4, 1))
        cache.setObject(image, forKey: cacheKey(for: url, size: size), cost: cost)
    }
}

// MARK: - Safe AsyncSemaphore

actor AsyncSemaphore {
    private let limit: Int
    private var current = 0
    private var waiters: [(id: UUID, continuation: CheckedContinuation<Void, Error>)] = []

    init(limit: Int) { self.limit = limit }

    func acquire() async throws {
        if current < limit {
            current += 1
            return
        }
        
        let id = UUID()
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                waiters.append((id, continuation))
            }
        } onCancel: {
            Task { await cancelWaiter(id: id) }
        }
    }

    func release() {
        if waiters.isEmpty {
            current -= 1
        } else {
            let next = waiters.removeFirst()
            next.continuation.resume()
        }
    }
    
    private func cancelWaiter(id: UUID) {
        if let index = waiters.firstIndex(where: { $0.id == id }) {
            let cancelled = waiters.remove(at: index)
            cancelled.continuation.resume(throwing: CancellationError())
        }
    }
}
