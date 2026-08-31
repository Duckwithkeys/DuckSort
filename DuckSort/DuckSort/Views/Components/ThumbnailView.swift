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
//                          that caps concurrent decodes to core-count (4–8).
//                          All CGImageSource, QL, and NSWorkspace calls happen
//                          here, never on main.
//  • ThumbnailCache      — Thread-safe NSCache wrapper (memory tier).
//                          Reads & writes happen on ThumbnailService's executor.
//  • DiskThumbnailCache  — Actor-isolated disk cache (JPEG on disk).
//                          Two-tier lookup: memory → disk → decode.
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
    @State private var isLoading = true

    var body: some View {
        Color.clear
            .overlay {
                ZStack {
                    // Placeholder / skeleton
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
                            .transition(.opacity.animation(.spring(response: 0.25, dampingFraction: 1.0)))
                    } else {
                        // Show subtle animated shimmer while loading
                        ShimmerView()
                            .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
                            .opacity(isLoading ? 1 : 0)
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
            }
        .task(id: url) {
            guard let url else {
                isLoading = false
                return
            }

            isLoading = true

            // Fast memory-cache hit
            if let hit = ThumbnailCache.global.image(for: url, size: size) {
                AppLogger.thumbnails.trace("Memory cache hit: \(url.lastPathComponent)")
                loader.image = hit
                isLoading = false
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

            AppLogger.thumbnails.trace("Decode started: \(url.lastPathComponent)")
            if let result = await ThumbnailService.shared.thumbnail(for: url, size: size, scale: scale, skipMemoryCache: true) {
                guard !Task.isCancelled else { return }
                loader.image = result
            }
            isLoading = false
        }
    }
}

// MARK: - Shimmer placeholder

/// Lightweight animated shimmer shown while thumbnails decode.
private struct ShimmerView: View {
    @State private var phase: CGFloat = 0

    var body: some View {
        GeometryReader { geo in
            Rectangle()
                .fill(
                    LinearGradient(
                        stops: [
                            .init(color: Theme.Color.cellBackground.opacity(0.6), location: 0),
                            .init(color: Theme.Color.separator.opacity(0.4), location: 0.4),
                            .init(color: Theme.Color.cellBackground.opacity(0.6), location: 1)
                        ],
                        startPoint: UnitPoint(x: phase - 0.3, y: 0.5),
                        endPoint: UnitPoint(x: phase + 0.3, y: 0.5)
                    )
                )
                .onAppear {
                    withAnimation(.linear(duration: 1.4).repeatForever(autoreverses: false)) {
                        phase = 1.3
                    }
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
    // Semaphore limit: core-count, bounded to 4–8 to avoid thrashing.
    private let semaphore = AsyncSemaphore(
        limit: ProcessInfo.processInfo.activeProcessorCount.clamped(to: 4...8)
    )
    private var inFlightTasks: [String: Task<NSImage?, Never>] = [:]

    private init() {}

    private func diskCacheSize(for size: CGSize) -> CGSize {
        let maxDim = max(size.width, size.height)
        if maxDim <= 128 {
            return CGSize(width: 128, height: 128)
        }
        return CGSize(width: 600, height: 600)
    }

    func thumbnail(for url: URL?, size: CGSize, scale: CGFloat = 2.0, skipMemoryCache: Bool = false) async -> NSImage? {
        guard let url else { return nil }

        // 1. Memory cache
        if !skipMemoryCache, let hit = ThumbnailCache.global.image(for: url, size: size) { return hit }

        let bucketSize = diskCacheSize(for: size)

        // 2. Disk cache (avoid decode if we already have JPEG on disk)
        if let diskHit = await DiskThumbnailCache.shared.image(for: url, size: bucketSize) {
            ThumbnailCache.global.insert(diskHit, for: url, size: size)
            return diskHit
        }

        // 3. In-flight task deduplication
        let key = "\(url.path)_\(Int(size.width))x\(Int(size.height))"
        if let existing = inFlightTasks[key] {
            return await existing.value
        }

        let task = Task<NSImage?, Never> {
            defer {
                Task { @ThumbnailActor in
                    ThumbnailService.shared.inFlightTasks.removeValue(forKey: key)
                }
            }

            do {
                try Task.checkCancellation()
                // Acquire will throw if cancelled while waiting
                try await semaphore.acquire()
            } catch {
                return nil
            }

            do {
                let result = try await decode(url: url, size: size, scale: scale, bucketSize: bucketSize)
                await semaphore.release()
                return result
            } catch {
                await semaphore.release()
                return nil
            }
        }

        inFlightTasks[key] = task
        return await task.value
    }

    private func decode(url: URL, size: CGSize, scale: CGFloat, bucketSize: CGSize) async throws -> NSImage? {
        try Task.checkCancellation()

        let maxPixels = max(size.width, size.height) * scale
        let ext = url.pathExtension.lowercased()
        let alwaysCreate = FileExtension.rawLikeExtensions.contains(ext)

        // 1. Fast path: ImageIO
        if let cgImage = await decodeWithImageIO(url: url, maxPixels: maxPixels, alwaysCreate: alwaysCreate) {
            try Task.checkCancellation()
            let ns = NSImage(cgImage: cgImage, size: NSSize(width: cgImage.width, height: cgImage.height))
            ThumbnailCache.global.insert(ns, for: url, size: size)
            Task(priority: .background) {
                await DiskThumbnailCache.shared.insert(ns, for: url, size: bucketSize)
            }
            return ns
        }

        // 1b. HEIF / HEIC fallback using optimized load
        if FileExtension.heifLikeExtensions.contains(ext) {
            if let cg = await loadWithImageIOFallback(url: url, maxPixels: maxPixels) {
                try Task.checkCancellation()
                let ns = NSImage(cgImage: cg, size: NSSize(width: cg.width, height: cg.height))
                ThumbnailCache.global.insert(ns, for: url, size: size)
                Task(priority: .background) {
                    await DiskThumbnailCache.shared.insert(ns, for: url, size: bucketSize)
                }
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
            let image = rep.nsImage
            ThumbnailCache.global.insert(image, for: url, size: size)
            Task(priority: .background) {
                await DiskThumbnailCache.shared.insert(image, for: url, size: bucketSize)
            }
            return image
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            let icon = NSWorkspace.shared.icon(forFile: url.path)
            ThumbnailCache.global.insert(icon, for: url, size: size)
            return icon
        }
    }

    nonisolated private static let decodeQueue = DispatchQueue(label: "com.ducksort.imageio.decode", qos: .utility, attributes: .concurrent)

    /// Applies EXIF orientation to a CGImage when decoded via CGImageSourceCreateImageAtIndex.
    nonisolated static func applyOrientation(from source: CGImageSource, to cgImage: CGImage) -> CGImage {
        guard let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let rawOrientation = properties[kCGImagePropertyOrientation] as? UInt32,
              let orientation = CGImagePropertyOrientation(rawValue: rawOrientation),
              orientation != .up else {
            return cgImage
        }
        
        let width = cgImage.width
        let height = cgImage.height
        let isTransposed = (orientation == .left || orientation == .right || orientation == .leftMirrored || orientation == .rightMirrored)
        let targetW = isTransposed ? height : width
        let targetH = isTransposed ? width : height
        
        guard let colorSpace = cgImage.colorSpace,
              let context = CGContext(
                  data: nil,
                  width: targetW,
                  height: targetH,
                  bitsPerComponent: cgImage.bitsPerComponent,
                  bytesPerRow: 0,
                  space: colorSpace,
                  bitmapInfo: cgImage.bitmapInfo.rawValue
              ) else { return cgImage }
        
        switch orientation {
        case .up:
            break
        case .upMirrored:
            context.translateBy(x: CGFloat(targetW), y: 0)
            context.scaleBy(x: -1.0, y: 1.0)
        case .down:
            context.translateBy(x: CGFloat(targetW), y: CGFloat(targetH))
            context.rotate(by: .pi)
        case .downMirrored:
            context.translateBy(x: 0, y: CGFloat(targetH))
            context.scaleBy(x: 1.0, y: -1.0)
        case .leftMirrored:
            context.rotate(by: .pi / 2.0)
            context.scaleBy(x: 1.0, y: -1.0)
        case .right:
            context.translateBy(x: CGFloat(targetW), y: 0)
            context.rotate(by: .pi / 2.0)
        case .rightMirrored:
            context.translateBy(x: CGFloat(targetW), y: CGFloat(targetH))
            context.rotate(by: .pi / 2.0)
            context.scaleBy(x: -1.0, y: 1.0)
        case .left:
            context.translateBy(x: 0, y: CGFloat(targetH))
            context.rotate(by: -.pi / 2.0)
        @unknown default:
            break
        }
        
        context.interpolationQuality = .high
        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))
        return context.makeImage() ?? cgImage
    }

    nonisolated private func decodeWithImageIO(url: URL, maxPixels: CGFloat, alwaysCreate: Bool) async -> CGImage? {
        await withCheckedContinuation { continuation in
            Self.decodeQueue.async {
                let ext = url.pathExtension.lowercased()
                var sourceOptions: [CFString: Any] = [
                    kCGImageSourceShouldCache: true
                ]
                if let typeHint = FileExtension.typeIdentifierHint(for: ext) {
                    sourceOptions[kCGImageSourceTypeIdentifierHint] = typeHint
                }
                guard let source = CGImageSourceCreateWithURL(url as CFURL, sourceOptions as CFDictionary) else {
                    continuation.resume(returning: nil)
                    return
                }
                guard !Task.isCancelled else {
                    continuation.resume(returning: nil)
                    return
                }

                let decodeOptions: [CFString: Any] = [
                    kCGImageSourceCreateThumbnailFromImageAlways: true,
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
                let ext = url.pathExtension.lowercased()
                var sourceOptions: [CFString: Any] = [
                    kCGImageSourceShouldCache: true
                ]
                if let typeHint = FileExtension.typeIdentifierHint(for: ext) {
                    sourceOptions[kCGImageSourceTypeIdentifierHint] = typeHint
                }
                guard let source = CGImageSourceCreateWithURL(url as CFURL, sourceOptions as CFDictionary) else {
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

                guard let rawCGImage = CGImageSourceCreateImageAtIndex(source, 0, [kCGImageSourceShouldCacheImmediately: true] as CFDictionary) else {
                    continuation.resume(returning: nil)
                    return
                }
                
                let orientedImage = Self.applyOrientation(from: source, to: rawCGImage)
                
                let width = CGFloat(orientedImage.width)
                let height = CGFloat(orientedImage.height)
                let scale = min(maxPixels / max(width, height), 1.0)
                guard scale < 1.0 else {
                    continuation.resume(returning: orientedImage)
                    return
                }
                
                let targetW = Int(width * scale)
                let targetH = Int(height * scale)
                
                guard let colorSpace = orientedImage.colorSpace,
                      let context = CGContext(
                          data: nil,
                          width: targetW,
                          height: targetH,
                          bitsPerComponent: orientedImage.bitsPerComponent,
                          bytesPerRow: 0,
                          space: colorSpace,
                          bitmapInfo: orientedImage.bitmapInfo.rawValue
                      ) else {
                    continuation.resume(returning: orientedImage)
                    return
                }
                      
                context.interpolationQuality = .high
                context.draw(orientedImage, in: CGRect(x: 0, y: 0, width: targetW, height: targetH))
                continuation.resume(returning: context.makeImage() ?? orientedImage)
            }
        }
    }
}

// MARK: - Thread-safe memory cache

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

    /// Removes a single entry by URL + size.
    func remove(for url: URL, size: CGSize) {
        cache.removeObject(forKey: cacheKey(for: url, size: size))
    }

    /// Evicts the entire in-memory cache. Called on memory pressure events.
    func evictAll() {
        cache.removeAllObjects()
        AppLogger.thumbnails.info("Memory cache evicted (all objects removed)")
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

// MARK: - Comparable clamping helper

extension Comparable {
    fileprivate func clamped(to range: ClosedRange<Self>) -> Self {
        min(max(self, range.lowerBound), range.upperBound)
    }
}
