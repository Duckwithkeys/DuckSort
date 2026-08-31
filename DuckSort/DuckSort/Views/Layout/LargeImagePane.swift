//
//  LargeImagePane.swift
//  PhotomatorSort
//
//  Full-canvas image viewer for the culling flow. Displays the focused
//  photo at high resolution with pan/zoom support. Uses QuickLook
//  thumbnailing for fast initial load.
//

import AppKit
import QuickLookThumbnailing
import SwiftUI
import ImageIO

final class SynchronizedZoomState: ObservableObject, @unchecked Sendable {
    @Published var zoomScale: CGFloat = 1.0
    @Published var currentAmount: CGFloat = 0.0
    @Published var panOffset: CGSize = .zero
    @Published var accumulatedPan: CGSize = .zero

    func reset() {
        zoomScale = 1.0
        currentAmount = 0.0
        panOffset = .zero
        accumulatedPan = .zero
    }
}

struct LargeImagePane: View {
    let photoSet: PhotoSet
    @ObservedObject var zoomState: SynchronizedZoomState
    var onEdit: (() -> Void)? = nil
    @StateObject private var imageLoader = LargeImageLoader()

    private let minZoom: CGFloat = 0.5
    private let maxZoom: CGFloat = 5.0

    var body: some View {
        ErrorBoundaryView(errorMessage: imageLoader.loadError, retryAction: {
            Task {
                await imageLoader.load(url: photoSet.preferredPreviewURL)
            }
        }) {
            ZStack {
                Color.clear
                    .ignoresSafeArea()

                let highResImage = (imageLoader.loadedURL == photoSet.preferredPreviewURL ? imageLoader.image : nil) ?? LargeImageLoader.cachedImage(for: photoSet.preferredPreviewURL)
                let lowResImage = photoSet.preferredPreviewURL.flatMap {
                    ThumbnailCache.global.image(for: $0, size: CGSize(width: 600, height: 600)) ??
                    ThumbnailCache.global.image(for: $0, size: CGSize(width: 128, height: 128))
                }

                if highResImage != nil || lowResImage != nil {
                    GeometryReader { geometry in
                        ZStack {
                            Color.clear
                            
                            if let lowRes = lowResImage, highResImage == nil {
                                Image(nsImage: lowRes)
                                    .resizable()
                                    .interpolation(.medium)
                                    .scaledToFit()
                                    .scaleEffect(zoomState.zoomScale + zoomState.currentAmount)
                                    .offset(zoomState.panOffset)
                                    .opacity(0.9)
                                    .grayscale(photoSet.pick == -1 ? 0.8 : 0)
                            }
                            
                            if let highRes = highResImage {
                                Image(nsImage: highRes)
                                    .resizable()
                                    .interpolation(.high)
                                    .scaledToFit()
                                    .scaleEffect(zoomState.zoomScale + zoomState.currentAmount)
                                    .offset(zoomState.panOffset)
                                    .transition(.opacity)
                                    .grayscale(photoSet.pick == -1 ? 0.8 : 0)
                            }
                        }
                        .frame(width: geometry.size.width, height: geometry.size.height)
                        .gesture(
                            MagnificationGesture()
                                .onChanged { value in
                                    zoomState.currentAmount = value - 1.0
                                }
                                .onEnded { value in
                                    zoomState.zoomScale = clamp(zoomState.zoomScale + zoomState.currentAmount)
                                    zoomState.currentAmount = 0
                                }
                                .simultaneously(
                                    with: DragGesture(minimumDistance: 4)
                                        .onChanged { value in
                                            if (zoomState.zoomScale + zoomState.currentAmount) > 1.0 {
                                                zoomState.panOffset = CGSize(
                                                    width: zoomState.accumulatedPan.width + value.translation.width,
                                                    height: zoomState.accumulatedPan.height + value.translation.height
                                                )
                                            }
                                        }
                                        .onEnded { _ in
                                            zoomState.accumulatedPan = zoomState.panOffset
                                        }
                                )
                        )
                        .onTapGesture(count: 2) {
                            withAnimation(.spring()) {
                                if zoomState.zoomScale > 1.0 {
                                    zoomState.zoomScale = 1.0
                                    zoomState.panOffset = .zero
                                    zoomState.accumulatedPan = .zero
                                } else if let nsImage = highResImage ?? lowResImage {
                                    let fitScale = min(
                                        geometry.size.width / nsImage.size.width,
                                        geometry.size.height / nsImage.size.height
                                    )
                                    zoomState.zoomScale = max(fitScale * 2.0, 1.5)
                                    zoomState.panOffset = .zero
                                    zoomState.accumulatedPan = .zero
                                }
                            }
                        }
                        .contextMenu {
                            Button("Reveal in Finder") {
                                if let url = photoSet.preferredPreviewURL {
                                    NSWorkspace.shared.activateFileViewerSelecting([url])
                                }
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .clipped()
                } else if imageLoader.loadError == nil {
                    ProgressView()
                        .tint(.white)
                }
            }
        }
        .task(id: photoSet.id) {
            await imageLoader.load(url: photoSet.preferredPreviewURL)
        }
    }

    @MainActor
    func clamp(_ value: CGFloat) -> CGFloat {
        max(minZoom, min(maxZoom, value))
    }
}

// MARK: - High-res image loader

private final class LargeImageCacheWrapper: @unchecked Sendable {
    let cache: NSCache<NSString, NSImage> = {
        let c = NSCache<NSString, NSImage>()
        let memoryGB = Int(ProcessInfo.processInfo.physicalMemory / (1024 * 1024 * 1024))
        if memoryGB >= 32 {
            c.countLimit = 100
            c.totalCostLimit = 600 * 1024 * 1024
        } else if memoryGB >= 16 {
            c.countLimit = 60
            c.totalCostLimit = 350 * 1024 * 1024
        } else {
            c.countLimit = 30
            c.totalCostLimit = 150 * 1024 * 1024
        }
        return c
    }()
}

@MainActor
final class LargeImageLoader: ObservableObject {
    @Published var image: NSImage?
    @Published var loadedURL: URL? = nil
    @Published var loadError: String? = nil

    private static let cacheWrapper = LargeImageCacheWrapper()
    private static let decodeQueue = DispatchQueue(label: "com.ducksort.largeimage.decode", qos: .utility, attributes: .concurrent)
    private static var inFlightTasks: [String: Task<NSImage?, Never>] = [:]
    private static let inFlightLock = NSLock()

    /// Downsamples `cgImage` so that neither side exceeds `maxPixels`.
    /// Performs resizing entirely in CoreGraphics without touching AppKit contexts.
    nonisolated fileprivate static func downsample(cgImage: CGImage, maxPixels: CGFloat) -> CGImage? {
        let width = CGFloat(cgImage.width)
        let height = CGFloat(cgImage.height)
        let scale = min(maxPixels / max(width, height), 1.0)
        guard scale < 1.0 else { return cgImage }
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
              ) else { return cgImage }
        
        context.interpolationQuality = .high
        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: targetW, height: targetH))
        return context.makeImage()
    }

    static func cachedImage(for url: URL?) -> NSImage? {
        guard let url = url else { return nil }
        return cacheWrapper.cache.object(forKey: url.path as NSString)
    }

    /// Fetches an image at high resolution with deduplication of in-flight decoding tasks.
    static func fetchImage(for url: URL) async -> NSImage? {
        let key = url.path as NSString
        if let cached = cacheWrapper.cache.object(forKey: key) {
            return cached
        }

        // Check or register in-flight decoding task
        let task: Task<NSImage?, Never> = inFlightLock.withLock {
            if let existing = inFlightTasks[url.path] {
                return existing
            }

            let newTask = Task<NSImage?, Never>(priority: .userInitiated) {
                defer {
                    _ = inFlightLock.withLock {
                        inFlightTasks.removeValue(forKey: url.path)
                    }
                }

                let ext = url.pathExtension.lowercased()
                let alwaysCreate = FileExtension.rawLikeExtensions.contains(ext)

                // 1. Primary ImageIO decode
                if let cgImage = await decodeThumbnailWithImageIO(url: url, maxPixels: 3072, alwaysCreate: alwaysCreate) {
                    let preview = NSImage(cgImage: cgImage, size: NSSize(width: cgImage.width, height: cgImage.height))
                    let cost = cgImage.width * cgImage.height * 4
                    cacheWrapper.cache.setObject(preview, forKey: key, cost: cost)
                    return preview
                }

                // 2. HEIF fallback
                if FileExtension.heifLikeExtensions.contains(ext) {
                    if let cgImage = await decodeHEIFFallback(url: url, maxPixels: 2048) {
                        let preview = NSImage(cgImage: cgImage, size: NSSize(width: cgImage.width, height: cgImage.height))
                        let cost = cgImage.width * cgImage.height * 4
                        cacheWrapper.cache.setObject(preview, forKey: key, cost: cost)
                        return preview
                    }
                }

                // 3. QuickLook backup
                let request = QLThumbnailGenerator.Request(
                    fileAt: url,
                    size: CGSize(width: 2048, height: 2048),
                    scale: NSScreen.main?.backingScaleFactor ?? 2,
                    representationTypes: .thumbnail
                )
                if let representation = try? await QLThumbnailGenerator.shared.generateBestRepresentation(for: request) {
                    let preview = representation.nsImage
                    let cost = representation.cgImage.width * representation.cgImage.height * 4
                    cacheWrapper.cache.setObject(preview, forKey: key, cost: cost)
                    return preview
                }

                return nil
            }

            inFlightTasks[url.path] = newTask
            return newTask
        }

        return await task.value
    }

    static func preload(url: URL?) {
        guard let url = url else { return }
        if cachedImage(for: url) != nil { return }
        Task(priority: .utility) {
            _ = await fetchImage(for: url)
        }
    }

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

    private static func decodeThumbnailWithImageIO(url: URL, maxPixels: CGFloat, alwaysCreate: Bool) async -> CGImage? {
        await withCheckedContinuation { continuation in
            Self.decodeQueue.async {
                let ext = url.pathExtension.lowercased()
                var sourceOptions: [CFString: Any] = [
                    kCGImageSourceShouldCache: true
                ]
                if let typeHint = FileExtension.typeIdentifierHint(for: ext) {
                    sourceOptions[kCGImageSourceTypeIdentifierHint] = typeHint
                }
                guard let imageSource = CGImageSourceCreateWithURL(url as CFURL, sourceOptions as CFDictionary) else {
                    continuation.resume(returning: nil)
                    return
                }

                let options: [CFString: Any] = [
                    kCGImageSourceCreateThumbnailFromImageAlways: true,
                    kCGImageSourceThumbnailMaxPixelSize: maxPixels,
                    kCGImageSourceCreateThumbnailWithTransform: true,
                    kCGImageSourceShouldCacheImmediately: true,
                    kCGImageSourceShouldAllowFloat: true
                ]
                let thumbnailCG = CGImageSourceCreateThumbnailAtIndex(imageSource, 0, options as CFDictionary)
                continuation.resume(returning: thumbnailCG)
            }
        }
    }

    private static func decodeHEIFFallback(url: URL, maxPixels: CGFloat) async -> CGImage? {
        await withCheckedContinuation { continuation in
            Self.decodeQueue.async {
                let ext = url.pathExtension.lowercased()
                var sourceOptions: [CFString: Any] = [
                    kCGImageSourceShouldCache: true
                ]
                if let typeHint = FileExtension.typeIdentifierHint(for: ext) {
                    sourceOptions[kCGImageSourceTypeIdentifierHint] = typeHint
                }
                guard let source = CGImageSourceCreateWithURL(url as CFURL, sourceOptions as CFDictionary),
                      let rawCG = CGImageSourceCreateImageAtIndex(source, 0, [kCGImageSourceShouldCacheImmediately: true] as CFDictionary) else {
                    continuation.resume(returning: nil)
                    return
                }
                let orientedCG = Self.applyOrientation(from: source, to: rawCG)
                let scaled = Self.downsample(cgImage: orientedCG, maxPixels: maxPixels)
                continuation.resume(returning: scaled ?? orientedCG)
            }
        }
    }

    func load(url: URL?) async {
        loadError = nil
        guard let url = url else {
            image = nil
            loadedURL = nil
            return
        }

        // 1. High-res cache hit
        if let cached = Self.cachedImage(for: url) {
            image = cached
            loadedURL = url
            return
        }

        // 2. Instantly promote existing cached thumbnail as placeholder while high-res decodes
        if let proxy = ThumbnailCache.global.image(for: url, size: CGSize(width: 600, height: 600)) ??
                       ThumbnailCache.global.image(for: url, size: CGSize(width: 128, height: 128)) {
            image = proxy
            loadedURL = url
        }

        let decoded = await Self.fetchImage(for: url)
        if Task.isCancelled { return }

        if let decoded {
            withAnimation(.easeOut(duration: 0.12)) {
                self.image = decoded
                self.loadedURL = url
            }
        } else if image == nil {
            loadError = "Failed to load image"
        }
    }
}
