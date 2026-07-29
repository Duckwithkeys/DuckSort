//
//  IOSurfaceMetalRenderer.swift
//  DuckSort
//
//  Zero-copy hardware memory mapping renderer. Wraps CVPixelBuffer and IOSurface
//  buffers directly into Metal texture VRAM for high-performance zero-copy rendering.
//

import Foundation
import Metal
import CoreVideo
import AppKit
import Accelerate

struct ImageHistogramResult: Sendable {
    let red: [vImagePixelCount]
    let green: [vImagePixelCount]
    let blue: [vImagePixelCount]
    let alpha: [vImagePixelCount]
    let highlightClippingPercent: Float
    let shadowClippingPercent: Float
}

final class IOSurfaceMetalRenderer: @unchecked Sendable {
    static let shared = IOSurfaceMetalRenderer()

    private let device: MTLDevice?
    private var textureCache: CVMetalTextureCache?

    private init() {
        let dev = MTLCreateSystemDefaultDevice()
        self.device = dev
        if let dev = dev {
            var cache: CVMetalTextureCache?
            let result = CVMetalTextureCacheCreate(kCFAllocatorDefault, nil, dev, nil, &cache)
            if result != kCVReturnSuccess {
                AppLogger.ui.error("Failed to create CVMetalTextureCache: \(result)")
            }
            self.textureCache = cache
        } else {
            AppLogger.ui.error("Failed to create system default Metal device.")
        }
    }

    /// Flushes unused textures from the Metal texture cache.
    func flush() {
        if let cache = textureCache {
            CVMetalTextureCacheFlush(cache, 0)
        }
    }

    /// Computes 256-bin RGB luminance histograms and clipping metrics using Accelerate vImage.
    func computeHistogram(from cgImage: CGImage) -> ImageHistogramResult? {
        AppLogger.ui.debug("Computing luminance histogram for image: \(cgImage.width)x\(cgImage.height)")

        var format = vImage_CGImageFormat(
            bitsPerComponent: 8,
            bitsPerPixel: 32,
            colorSpace: nil,
            bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.first.rawValue),
            version: 0,
            decode: nil,
            renderingIntent: .defaultIntent
        )

        var srcBuffer = vImage_Buffer()
        guard vImageBuffer_InitWithCGImage(&srcBuffer, &format, nil, cgImage, vImage_Flags(kvImageNoFlags)) == kvImageNoError else {
            AppLogger.ui.error("vImageBuffer_InitWithCGImage failed for histogram calculation")
            return nil
        }
        defer { free(srcBuffer.data) }

        let r = UnsafeMutablePointer<vImagePixelCount>.allocate(capacity: 256)
        let g = UnsafeMutablePointer<vImagePixelCount>.allocate(capacity: 256)
        let b = UnsafeMutablePointer<vImagePixelCount>.allocate(capacity: 256)
        let a = UnsafeMutablePointer<vImagePixelCount>.allocate(capacity: 256)

        defer {
            r.deallocate()
            g.deallocate()
            b.deallocate()
            a.deallocate()
        }

        r.initialize(repeating: 0, count: 256)
        g.initialize(repeating: 0, count: 256)
        b.initialize(repeating: 0, count: 256)
        a.initialize(repeating: 0, count: 256)

        var histogram: [UnsafeMutablePointer<vImagePixelCount>?] = [r, g, b, a]
        let error = histogram.withUnsafeMutableBufferPointer { ptr in
            vImageHistogramCalculation_ARGB8888(&srcBuffer, ptr.baseAddress!, vImage_Flags(kvImageNoFlags))
        }

        guard error == kvImageNoError else {
            AppLogger.ui.error("vImageHistogramCalculation_ARGB8888 failed with error \(error)")
            return nil
        }

        let redBins = Array(UnsafeBufferPointer(start: r, count: 256))
        let greenBins = Array(UnsafeBufferPointer(start: g, count: 256))
        let blueBins = Array(UnsafeBufferPointer(start: b, count: 256))
        let alphaBins = Array(UnsafeBufferPointer(start: a, count: 256))

        let totalPixels = Float(cgImage.width * cgImage.height)
        let overexposedPixels = Float(redBins[255] + greenBins[255] + blueBins[255]) / 3.0
        let underexposedPixels = Float(redBins[0] + greenBins[0] + blueBins[0]) / 3.0

        let highlightClip = totalPixels > 0 ? (overexposedPixels / totalPixels) * 100.0 : 0.0
        let shadowClip = totalPixels > 0 ? (underexposedPixels / totalPixels) * 100.0 : 0.0

        return ImageHistogramResult(
            red: redBins,
            green: greenBins,
            blue: blueBins,
            alpha: alphaBins,
            highlightClippingPercent: highlightClip,
            shadowClippingPercent: shadowClip
        )
    }

    /// Wraps a CVPixelBuffer backed by an IOSurface into a Metal texture without CPU copy memory overhead.
    func makeTexture(from pixelBuffer: CVPixelBuffer) -> MTLTexture? {
        guard let cache = textureCache else {
            AppLogger.ui.error("makeTexture failed: CVMetalTextureCache is nil")
            return nil
        }

        let width = CVPixelBufferGetWidth(pixelBuffer)
        let height = CVPixelBufferGetHeight(pixelBuffer)

        var cvTexture: CVMetalTexture?
        let result = CVMetalTextureCacheCreateTextureFromImage(
            kCFAllocatorDefault,
            cache,
            pixelBuffer,
            nil,
            .bgra8Unorm,
            width,
            height,
            0,
            &cvTexture
        )

        guard result == kCVReturnSuccess, let cvTexture = cvTexture else {
            AppLogger.ui.error("CVMetalTextureCacheCreateTextureFromImage failed with result \(result)")
            return nil
        }

        return CVMetalTextureGetTexture(cvTexture)
    }
}
