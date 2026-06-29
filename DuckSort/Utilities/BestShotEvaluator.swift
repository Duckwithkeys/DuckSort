//
//  BestShotEvaluator.swift
//  DuckSort
//
//  Best Shot AI recommendation engine. Evaluates sharpness metrics via Core Image
//  Laplacian convolution and Vision face landmarks to identify top photos in bursts.
//

import Foundation
import CoreImage
import Vision
import ImageIO

struct BestShotScore: Sendable, Identifiable {
    var id: URL { url }
    let url: URL
    let sharpnessScore: Double
    let faceScore: Double
    let totalScore: Double
}

final class BestShotEvaluator: Sendable {
    static let shared = BestShotEvaluator()
    private let context = CIContext(options: [.useSoftwareRenderer: false])

    private init() {}

    /// Evaluates sharpness score using Laplacian convolution matrix variance.
    func evaluateSharpness(for url: URL) async -> Double {
        guard let imageSource = CGImageSourceCreateWithURL(url as CFURL, nil),
              let cgImage = CGImageSourceCreateImageAtIndex(imageSource, 0, nil) else {
            return 0.0
        }

        let ciImage = CIImage(cgImage: cgImage)
        
        // Laplacian 3x3 filter kernel for edge detection
        let laplacianWeights: [CGFloat] = [
            0,  1, 0,
            1, -4, 1,
            0,  1, 0
        ]
        
        guard let filter = CIFilter(name: "CIConvolution3x3") else { return 0.0 }
        filter.setValue(ciImage, forKey: kCIInputImageKey)
        filter.setValue(CIVector(values: laplacianWeights, count: 9), forKey: "inputWeights")
        filter.setValue(0.0, forKey: "inputBias")

        guard let outputImage = filter.outputImage else { return 0.0 }
        
        // Compute variance approximation using area maximum/extent
        let extent = outputImage.extent
        guard let areaMaxFilter = CIFilter(name: "CIAreaMaximum") else { return 0.0 }
        areaMaxFilter.setValue(outputImage, forKey: kCIInputImageKey)
        areaMaxFilter.setValue(CIVector(cgRect: extent), forKey: kCIInputExtentKey)

        guard let maxOutput = areaMaxFilter.outputImage else { return 0.0 }
        var bitmap = [UInt8](repeating: 0, count: 4)
        context.render(maxOutput, toBitmap: &bitmap, rowBytes: 4, bounds: CGRect(x: 0, y: 0, width: 1, height: 1), format: .RGBA8, colorSpace: nil)

        let intensity = Double(bitmap[0]) / 255.0
        return intensity * 100.0
    }

    /// Finds the Best Shot within a group of burst URLs.
    func findBestShot(in urls: [URL]) async -> BestShotScore? {
        var scores: [BestShotScore] = []

        for url in urls {
            let sharpness = await evaluateSharpness(for: url)
            let faces = (try? await FaceClusteringService.shared.detectFaces(at: url)) ?? []
            let faceScore = Double(faces.count) * 20.0
            let total = sharpness + faceScore

            scores.append(BestShotScore(url: url, sharpnessScore: sharpness, faceScore: faceScore, totalScore: total))
        }

        return scores.max(by: { $0.totalScore < $1.totalScore })
    }
}
