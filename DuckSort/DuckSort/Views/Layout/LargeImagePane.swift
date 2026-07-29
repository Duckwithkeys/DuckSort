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
                                    .interpolation(.low)
                                    .scaledToFit()
                                    .scaleEffect(zoomState.zoomScale + zoomState.currentAmount)
                                    .offset(zoomState.panOffset)
                                    .blur(radius: 12)
                                    .opacity(0.8)
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
            imageLoader.image = nil
            imageLoader.loadedURL = nil
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

private final class PreloadsWrapper: @unchecked Sendable {
    let cache = NSCache<NSString, AnyObject>()
}

@MainActor
final class LargeImageLoader: ObservableObject {
    @Published var image: NSImage?
    @Published var loadedURL: URL? = nil
    @Published var loadError: String? = nil

    private static let cacheWrapper = LargeImageCacheWrapper()
    private static let activePreloadsWrapper = PreloadsWrapper()

    nonisolated private static func cost(for image: NSImage) -> Int {
        if let rep = image.representations.first {
            let w = rep.pixelsWide
            let h = rep.pixelsHigh
            if w > 0 && h > 0 {
                return w * h * 4
            }
        }
        return Int(image.size.width * image.size.height * 4)
    }

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

    static func preload(url: URL?) {
        guard let url = url else { return }
        let key = url.path as NSString
        let cacheW = cacheWrapper
        let activePreloadsW = activePreloadsWrapper
        if cacheW.cache.object(forKey: key) != nil {
            return
        }
        if activePreloadsW.cache.object(forKey: key) != nil {
            return
        }
        activePreloadsW.cache.setObject(true as AnyObject, forKey: key)

        let ext = url.pathExtension.lowercased()
        let alwaysCreate = FileExtension.rawLikeExtensions.contains(ext)
        Task.detached(priority: .utility) {
            let taskKey = url.path as NSString
            defer { activePreloadsW.cache.removeObject(forKey: taskKey) }
            let options = [kCGImageSourceShouldCache: false] as CFDictionary
            if let imageSource = CGImageSourceCreateWithURL(url as CFURL, options) {
                let options: [CFString: Any] = [
                    alwaysCreate ? kCGImageSourceCreateThumbnailFromImageAlways : kCGImageSourceCreateThumbnailFromImageIfAbsent: true,
                    kCGImageSourceThumbnailMaxPixelSize: CGFloat(2048),
                    kCGImageSourceCreateThumbnailWithTransform: true
                ]
                if let thumbnailCG = CGImageSourceCreateThumbnailAtIndex(imageSource, 0, options as CFDictionary) {
                    let previewImage = NSImage(cgImage: thumbnailCG, size: NSSize(width: thumbnailCG.width, height: thumbnailCG.height))
                    let cost = thumbnailCG.width * thumbnailCG.height * 4
                    cacheW.cache.setObject(previewImage, forKey: taskKey, cost: cost)
                    return
                }
            }

            // HEIF-friendly fallback when CGImageSource refuses the file.
            if FileExtension.heifLikeExtensions.contains(ext) {
                let options = [kCGImageSourceShouldCache: false] as CFDictionary
                if let source = CGImageSourceCreateWithURL(url as CFURL, options),
                   let cgImage = CGImageSourceCreateImageAtIndex(source, 0, nil),
                   let scaledCG = downsample(cgImage: cgImage, maxPixels: 2048) {
                    let previewImage = NSImage(cgImage: scaledCG, size: NSSize(width: scaledCG.width, height: scaledCG.height))
                    let cost = scaledCG.width * scaledCG.height * 4
                    cacheW.cache.setObject(previewImage, forKey: taskKey, cost: cost)
                }
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

        let key = url.path as NSString
        let cache = Self.cacheWrapper.cache
        let cached = cache.object(forKey: key)
        if cached != nil {
            image = cached
            loadedURL = url
            return
        }

        image = nil
        loadedURL = nil

        // 1. Try to load using the fast ImageIO CGImageSource in a detached task
        // We load as CGImage (which is thread-safe and has no Sendable restrictions)
        let ext = url.pathExtension.lowercased()
        let alwaysCreate = FileExtension.rawLikeExtensions.contains(ext)
        let decodeTask = Task.detached(priority: .userInitiated) { () -> CGImage? in
            if Task.isCancelled { return nil }
            let sourceOptions = [kCGImageSourceShouldCache: false] as CFDictionary
            guard let imageSource = CGImageSourceCreateWithURL(url as CFURL, sourceOptions) else { return nil }
            if Task.isCancelled { return nil }
            let options: [CFString: Any] = [
                alwaysCreate ? kCGImageSourceCreateThumbnailFromImageAlways : kCGImageSourceCreateThumbnailFromImageIfAbsent: true,
                kCGImageSourceThumbnailMaxPixelSize: CGFloat(3072),
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceShouldCacheImmediately: true,
                kCGImageSourceShouldAllowFloat: true
            ]
            guard let thumbnailCG = CGImageSourceCreateThumbnailAtIndex(imageSource, 0, options as CFDictionary) else { return nil }
            return thumbnailCG
        }

        let cgImage = await withTaskCancellationHandler {
            await decodeTask.value
        } onCancel: {
            decodeTask.cancel()
        }

        if let cgImage {
            if Task.isCancelled { return }
            // Instantiate NSImage on the Main Actor
            let previewImage = NSImage(cgImage: cgImage, size: NSSize(width: cgImage.width, height: cgImage.height))
            let cost = cgImage.width * cgImage.height * 4
            cache.setObject(previewImage, forKey: key, cost: cost)
            image = previewImage
            loadedURL = url
            return
        }

        // 1b. HEIF/HEIC native fallback. Some HEIC bursts return nil from
        // CGImageSourceCreateThumbnailAtIndex; we load and scale via CGImageSource + CGContext.
        if FileExtension.heifLikeExtensions.contains(ext) {
            if Task.isCancelled { return }
            let fallbackTask = Task.detached(priority: .userInitiated) { () -> CGImage? in
                if Task.isCancelled { return nil }
                let sourceOptions = [kCGImageSourceShouldCache: false] as CFDictionary
                guard let source = CGImageSourceCreateWithURL(url as CFURL, sourceOptions),
                      let cg = CGImageSourceCreateImageAtIndex(source, 0, nil) else { return nil }
                return Self.downsample(cgImage: cg, maxPixels: 2048)
            }
            if let cgImage = await fallbackTask.value {
                if Task.isCancelled { return }
                let previewImage = NSImage(cgImage: cgImage, size: NSSize(width: cgImage.width, height: cgImage.height))
                let cost = cgImage.width * cgImage.height * 4
                cache.setObject(previewImage, forKey: key, cost: cost)
                image = previewImage
                loadedURL = url
                return
            }
        }

        if Task.isCancelled { return }

        // 2. Try QuickLook as a backup
        let request = QLThumbnailGenerator.Request(
            fileAt: url,
            size: CGSize(width: 2048, height: 2048),
            scale: NSScreen.main?.backingScaleFactor ?? 2,
            representationTypes: .thumbnail
        )

        do {
            let representation = try await QLThumbnailGenerator.shared.generateBestRepresentation(for: request)
            if Task.isCancelled { return }
            let nsImage = representation.nsImage
            let cost = representation.cgImage.width * representation.cgImage.height * 4
            cache.setObject(nsImage, forKey: key, cost: cost)
            image = nsImage
            loadedURL = url
            return
        } catch is CancellationError {
            // Task was cancelled, do not write fallback to cache or change state
            return
        } catch {
            if Task.isCancelled { return }
            // 3. Last fallback: load the file Data in a background thread to avoid blocking MainActor,
            // then instantiate the NSImage on the Main Actor.
            let fallbackTask = Task.detached(priority: .userInitiated, operation: {
                if Task.isCancelled { throw CancellationError() }
                return try Data(contentsOf: url)
            })

            do {
                let data = try await withTaskCancellationHandler {
                    try await fallbackTask.value
                } onCancel: {
                    fallbackTask.cancel()
                }

                if Task.isCancelled { return }
                if let nsImage = NSImage(data: data) {
                    let cost = Self.cost(for: nsImage)
                    cache.setObject(nsImage, forKey: key, cost: cost)
                    image = nsImage
                    loadedURL = url
                } else {
                    throw NSError(domain: "DuckSort", code: -1, userInfo: [NSLocalizedDescriptionKey: "Failed to decode image data"])
                }
            } catch {
                if Task.isCancelled { return }
                loadError = error.localizedDescription
                AppLogger.ui.error("LargeImageLoader failed to load \(url.path): \(error.localizedDescription)")
            }
        }
    }
}
