//
//  AutoTagEngine.swift
//  DuckSort
//
//  Pure evaluation engine: takes a MetadataSnapshot and a set of enabled
//  AutoTagRule instances, returns matching AutoTagSuggestion arrays.
//  No I/O, fast, called on-demand when a photo is focused in the large
//  viewer.
//

import Foundation

final class AutoTagEngine: Sendable {
    static let shared = AutoTagEngine()

    /// Evaluates Vision ML scene classifications for a photo URL and converts them to AutoTagSuggestions.
    func visionSuggestions(for url: URL, confidenceThreshold: Float = 0.3) async -> [AutoTagSuggestion] {
        guard let classifications = try? await VisionEngineActor.shared.classifyImage(at: url, confidenceThreshold: confidenceThreshold) else {
            return []
        }

        return classifications.map { classification in
            let label = classification.identifier.components(separatedBy: ",").first?.capitalized ?? classification.identifier
            let confidenceEnum: Confidence = classification.confidence >= 0.7 ? .high : (classification.confidence >= 0.4 ? .medium : .low)
            return AutoTagSuggestion(
                tagName: label,
                reason: "Vision ML: \(Int(classification.confidence * 100))% match",
                categoryID: nil,
                confidence: confidenceEnum,
                source: .visionML
            )
        }
    }
}



// MARK: - MetadataSnapshot helper

extension MetadataSnapshot {
    /// Returns `true` if any EXIF field is populated.
    var hasAnyField: Bool {
        cameraModel != nil
        || lensModel != nil
        || captureDate != nil
        || aperture != nil
        || shutterSpeed != nil
        || iso != nil
        || rating != nil
        || pick != nil
        || focalLength != nil
        || focalLengthIn35mm != nil
        || whiteBalance != nil
        || flashFired != nil
        || flashMode != nil
        || pixelWidth != nil
        || pixelHeight != nil
        || orientation != nil
        || colorSpace != nil
        || colorProfile != nil
        || gpsLatitude != nil
        || gpsLongitude != nil
        || gpsAltitude != nil
        || exposureProgram != nil
        || meteringMode != nil
        || exposureBias != nil
        || caption != nil
        || !keywords.isEmpty
    }
}
