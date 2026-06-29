//
//  PerceptualHashEngine.swift
//  DuckSort
//
//  Perceptual difference hashing (dHash) engine. Computes 64-bit image hashes
//  and Hamming distances off the main thread to group burst shots and near-duplicates.
//

import Foundation
import ImageIO
import CoreGraphics

struct PhotoHashResult: Sendable, Identifiable {
    var id: URL { url }
    let url: URL
    let hash: UInt64
}

struct BurstGroup: Sendable, Identifiable {
    let id: UUID = UUID()
    let primaryURL: URL
    let memberURLs: [URL]
}

final class PerceptualHashEngine: Sendable {
    static let shared = PerceptualHashEngine()

    private init() {}

    /// Computes a 64-bit difference hash (dHash) for an image URL off the main thread.
    func computeDHash(for url: URL) async -> UInt64? {
        guard let imageSource = CGImageSourceCreateWithURL(url as CFURL, nil),
              let cgImage = CGImageSourceCreateImageAtIndex(imageSource, 0, nil) else {
            return nil
        }

        let width = 9
        let height = 8
        let colorSpace = CGColorSpaceCreateDeviceGray()
        var rawData = [UInt8](repeating: 0, count: width * height)

        guard let context = CGContext(
            data: &rawData,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.none.rawValue
        ) else {
            return nil
        }

        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))

        var hash: UInt64 = 0
        var bitIndex = 0

        for row in 0..<height {
            for col in 0..<(width - 1) {
                let leftPixel = rawData[row * width + col]
                let rightPixel = rawData[row * width + col + 1]

                if leftPixel > rightPixel {
                    hash |= (1 << bitIndex)
                }
                bitIndex += 1
            }
        }

        return hash
    }

    /// Computes the Hamming distance between two 64-bit perceptual hashes.
    func hammingDistance(_ hash1: UInt64, _ hash2: UInt64) -> Int {
        return (hash1 ^ hash2).nonzeroBitCount
    }

    /// Clusters photo URLs into burst groups based on a maximum Hamming distance threshold (e.g. <= 10).
    func groupBurstShots(urls: [URL], maxDistance: Int = 10) async -> [BurstGroup] {
        var hashResults: [PhotoHashResult] = []

        await withTaskGroup(of: PhotoHashResult?.self) { group in
            for url in urls {
                group.addTask {
                    if let hash = await self.computeDHash(for: url) {
                        return PhotoHashResult(url: url, hash: hash)
                    }
                    return nil
                }
            }

            for await result in group {
                if let result = result {
                    hashResults.append(result)
                }
            }
        }

        var visited = Set<URL>()
        var groups: [BurstGroup] = []

        for item in hashResults {
            guard !visited.contains(item.url) else { continue }
            visited.insert(item.url)

            var members: [URL] = [item.url]

            for other in hashResults {
                guard !visited.contains(other.url) else { continue }
                if hammingDistance(item.hash, other.hash) <= maxDistance {
                    visited.insert(other.url)
                    members.append(other.url)
                }
            }

            if members.count > 1 {
                groups.append(BurstGroup(primaryURL: item.url, memberURLs: members))
            }
        }

        return groups
    }
}
