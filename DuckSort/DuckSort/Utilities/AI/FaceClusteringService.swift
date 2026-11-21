//
//  FaceClusteringService.swift
//  DuckSort
//
//  Apple Neural Engine (ANE) accelerated face detection and clustering service.
//  Groups detected subjects locally without third-party cloud uploads.
//

import Accelerate
import Foundation
import Vision
import ImageIO

struct DetectedFaceResult: Sendable, Identifiable {
    let id: UUID
    let boundingBox: CGRect
    let confidence: Float
}

struct FaceCluster: Sendable, Identifiable {
    let id: UUID
    let photoURL: URL
    let faces: [DetectedFaceResult]
}

struct FaceEmbedding: Sendable {
    let boundingBox: CGRect
    /// Unit-normalized Vision feature-print vector for a cropped face.
    let vector: [Float]
}

/// On-device interactive face recognition learner.
/// Learns face embeddings whenever the user tags a photo with a person tag,
/// then predicts matching people on subsequent photos for one-keystroke (`Y`)
/// human approval — never auto-applying tags without confirmation.
actor FaceRecognitionEngine {
    static let shared = FaceRecognitionEngine()

    struct LearnedPerson: Sendable {
        let tagName: String
        let categoryID: UUID?
        var exemplars: [[Float]]
    }

    private var embeddingCache: [String: [FaceEmbedding]] = [:]
    private let maxCachedPhotos = 500
    private var learnedPeople: [String: LearnedPerson] = [:] // keyed by lowercased tagName
    private let maxExemplarsPerPerson = 12

    var learnedPeopleCount: Int { learnedPeople.count }

    func reset() {
        learnedPeople.removeAll()
    }

    /// Learns face embeddings from `url` and associates them with `tagName`.
    /// Only learns cleanly from photos with 1–2 prominent faces so group crowd
    /// shots don't pollute an individual's face signature.
    @discardableResult
    func learnPerson(tagName: String, categoryID: UUID?, from url: URL) async -> Bool {
        let faces = await faceEmbeddings(for: url)
        guard !faces.isEmpty, faces.count <= 2 else { return false }

        // If 2 faces are present, pick the largest (most prominent) face crop.
        let primary = faces.max(by: {
            ($0.boundingBox.width * $0.boundingBox.height) < ($1.boundingBox.width * $1.boundingBox.height)
        })!

        let key = tagName.lowercased()
        var person = learnedPeople[key] ?? LearnedPerson(tagName: tagName, categoryID: categoryID, exemplars: [])

        // Avoid storing near-duplicate exemplars from burst frames (cos sim > 0.96).
        let isDuplicate = person.exemplars.contains { Self.cosineSimilarity($0, primary.vector) > 0.96 }
        if !isDuplicate {
            person.exemplars.append(primary.vector)
            if person.exemplars.count > maxExemplarsPerPerson {
                person.exemplars.removeFirst()
            }
            learnedPeople[key] = person
            AppLogger.vision.info("Learned face sample for '\(tagName)' (\(person.exemplars.count) samples)")
            return true
        }
        return false
    }

    /// Predicts which learned people appear in `url`, sorted by highest confidence.
    /// Returns suggestions ready for the AI Vision Machine Learning sidebar.
    func predictPeople(for url: URL) async -> [AutoTagSuggestion] {
        guard !learnedPeople.isEmpty else { return [] }
        let faces = await faceEmbeddings(for: url)
        guard !faces.isEmpty else { return [] }

        var bestByPerson: [String: (person: LearnedPerson, score: Float)] = [:]

        for face in faces {
            for (key, person) in learnedPeople where !person.exemplars.isEmpty {
                var topScore: Float = 0
                for exemplar in person.exemplars {
                    let sim = Self.cosineSimilarity(face.vector, exemplar)
                    if sim > topScore { topScore = sim }
                }
                if topScore >= 0.72 {
                    if let existing = bestByPerson[key] {
                        if topScore > existing.score {
                            bestByPerson[key] = (person, topScore)
                        }
                    } else {
                        bestByPerson[key] = (person, topScore)
                    }
                }
            }
        }

        return bestByPerson.values
            .sorted { $0.score > $1.score }
            .prefix(5)
            .map { match in
                let pct = Int((match.score * 100).rounded())
                let samples = match.person.exemplars.count
                let confidence: Confidence = match.score >= 0.82 ? .high : .medium
                return AutoTagSuggestion(
                    tagName: match.person.tagName,
                    reason: "Face Match • \(pct)% (\(samples) sample\(samples == 1 ? "" : "s"))",
                    categoryID: match.person.categoryID,
                    confidence: confidence,
                    source: .faceRecognition
                )
            }
    }

    /// Extracts (or returns cached) unit-normalized Vision feature-print embeddings
    /// for every detected face crop in `url`.
    func faceEmbeddings(for url: URL) async -> [FaceEmbedding] {
        let key = url.standardizedFileURL.path
        if let cached = embeddingCache[key] {
            return cached
        }

        let extracted = await Task.detached(priority: .utility) {
            Self.extractFaceEmbeddingsSync(at: url)
        }.value

        if embeddingCache.count >= maxCachedPhotos {
            embeddingCache.removeAll(keepingCapacity: true)
        }
        embeddingCache[key] = extracted
        return extracted
    }

    nonisolated private static func extractFaceEmbeddingsSync(at url: URL) -> [FaceEmbedding] {
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceThumbnailMaxPixelSize: 1024,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCache: false
        ]
        guard let imageSource = CGImageSourceCreateWithURL(url as CFURL, nil),
              let cgImage = CGImageSourceCreateThumbnailAtIndex(imageSource, 0, options as CFDictionary) else {
            return []
        }

        let detectRequest = VNDetectFaceRectanglesRequest()
        detectRequest.preferBackgroundProcessing = true
        let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
        do {
            try handler.perform([detectRequest])
        } catch {
            return []
        }

        guard let observations = detectRequest.results, !observations.isEmpty else {
            return []
        }

        let imgW = CGFloat(cgImage.width)
        let imgH = CGFloat(cgImage.height)
        var embeddings: [FaceEmbedding] = []

        // Process up to 6 largest faces in a frame so crowd shots stay fast.
        let sortedFaces = observations
            .sorted { ($0.boundingBox.width * $0.boundingBox.height) > ($1.boundingBox.width * $1.boundingBox.height) }
            .prefix(6)

        for obs in sortedFaces {
            let box = obs.boundingBox
            // Vision uses bottom-left normalized coords; CGImage.cropping uses top-left pixel coords.
            let padX = box.width * 0.15
            let padY = box.height * 0.15
            let minX = max(0, (box.minX - padX) * imgW)
            let maxX = min(imgW, (box.maxX + padX) * imgW)
            let minY = max(0, (1.0 - (box.maxY + padY)) * imgH)
            let maxY = min(imgH, (1.0 - (box.minY - padY)) * imgH)
            let cropRect = CGRect(x: minX, y: minY, width: max(1, maxX - minX), height: max(1, maxY - minY)).integral

            guard cropRect.width >= 24, cropRect.height >= 24,
                  let faceCrop = cgImage.cropping(to: cropRect) else {
                continue
            }

            let fpRequest = VNGenerateImageFeaturePrintRequest()
            fpRequest.preferBackgroundProcessing = true
            let cropHandler = VNImageRequestHandler(cgImage: faceCrop, options: [:])
            do {
                try cropHandler.perform([fpRequest])
            } catch {
                continue
            }

            guard let fpObs = fpRequest.results?.first as? VNFeaturePrintObservation,
                  fpObs.elementType == .float else {
                continue
            }
            let count = fpObs.elementCount
            let requiredBytes = count * MemoryLayout<Float>.stride
            let data = fpObs.data
            guard count > 0, data.count >= requiredBytes else { continue }

            var raw = [Float](repeating: 0, count: count)
            data.withUnsafeBytes { rawBuf in
                if let base = rawBuf.bindMemory(to: Float.self).baseAddress {
                    for i in 0..<count { raw[i] = base[i] }
                }
            }

            var sumSq: Float = 0
            vDSP_svesq(raw, 1, &sumSq, vDSP_Length(count))
            let norm = sqrt(sumSq)
            guard norm > 0 else { continue }
            var normalized = [Float](repeating: 0, count: count)
            var divisor = norm
            vDSP_vsdiv(raw, 1, &divisor, &normalized, 1, vDSP_Length(count))

            embeddings.append(FaceEmbedding(boundingBox: box, vector: normalized))
        }

        return embeddings
    }

    nonisolated static func cosineSimilarity(_ a: [Float], _ b: [Float]) -> Float {
        guard a.count == b.count, !a.isEmpty else { return 0 }
        var dot: Float = 0
        vDSP_dotpr(a, 1, b, 1, &dot, vDSP_Length(a.count))
        return dot
    }
}

final class FaceClusteringService: Sendable {
    static let shared = FaceClusteringService()

    private init() {}

    /// Detects faces in a photo file using Vision and Neural Engine hardware acceleration options.
    func detectFaces(at url: URL) async throws -> [DetectedFaceResult] {
        try await Task.detached(priority: .userInitiated) {
            let options: [CFString: Any] = [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceThumbnailMaxPixelSize: 1024,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceShouldCache: false
            ]

            guard let imageSource = CGImageSourceCreateWithURL(url as CFURL, nil),
                  let cgImage = CGImageSourceCreateThumbnailAtIndex(imageSource, 0, options as CFDictionary) else {
                return []
            }

            let request = VNDetectFaceRectanglesRequest()
            // Prefer Apple Neural Engine (ANE) / GPU processing pipeline
            request.preferBackgroundProcessing = true

            let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
            try handler.perform([request])

            guard let observations = request.results else {
                return []
            }

            return observations.map { observation in
                DetectedFaceResult(
                    id: UUID(),
                    boundingBox: observation.boundingBox,
                    confidence: observation.confidence
                )
            }
        }.value
    }

    /// Clusters photo URLs based on face presence and count.
    func clusterPhotos(urls: [URL]) async -> [FaceCluster] {
        let semaphore = AsyncSemaphore(limit: 8)
        return await withTaskGroup(of: FaceCluster?.self) { group in
            for url in urls {
                group.addTask {
                    do {
                        try await semaphore.acquire()
                        defer { Task { await semaphore.release() } }
                        guard let faces = try? await self.detectFaces(at: url), !faces.isEmpty else {
                            return nil
                        }
                        return FaceCluster(id: UUID(), photoURL: url, faces: faces)
                    } catch {
                        return nil
                    }
                }
            }

            var clusters: [FaceCluster] = []
            for await cluster in group {
                if let cluster = cluster {
                    clusters.append(cluster)
                }
            }
            return clusters
        }
    }
}
