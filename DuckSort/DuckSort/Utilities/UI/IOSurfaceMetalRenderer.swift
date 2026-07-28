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

final class IOSurfaceMetalRenderer: @unchecked Sendable {
    static let shared = IOSurfaceMetalRenderer()

    private let device: MTLDevice?
    private var textureCache: CVMetalTextureCache?

    private init() {
        let dev = MTLCreateSystemDefaultDevice()
        self.device = dev
        if let dev = dev {
            var cache: CVMetalTextureCache?
            CVMetalTextureCacheCreate(kCFAllocatorDefault, nil, dev, nil, &cache)
            self.textureCache = cache
        }
    }

    /// Flushes unused textures from the Metal texture cache.
    func flush() {
        if let cache = textureCache {
            CVMetalTextureCacheFlush(cache, 0)
        }
    }

    /// Wraps a CVPixelBuffer backed by an IOSurface into a Metal texture without CPU copy memory overhead.
    func makeTexture(from pixelBuffer: CVPixelBuffer) -> MTLTexture? {
        guard let cache = textureCache else { return nil }

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
            return nil
        }

        return CVMetalTextureGetTexture(cvTexture)
    }
}
