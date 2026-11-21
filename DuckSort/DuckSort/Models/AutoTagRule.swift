//
//  AutoTagRule.swift
//  DuckSort
//
//  Data models for the auto-tagging feature. Rules are evaluated against
//  a photo's EXIF metadata when it is focused in the large viewer, and
//  matching suggestions are offered to the user.
//

import Foundation

// MARK: - Suggestion

enum SuggestionSource: String, Codable, Sendable {
    case visionML = "AI Vision ML"
    case exifRule = "EXIF Camera Rule"
}

/// A single tag suggestion produced by the auto-tag engine. Ephemeral —
/// not persisted. Created on every focus of a photo.
struct AutoTagSuggestion: Identifiable, Sendable {
    let id: UUID = UUID()
    let tagName: String           // e.g. "Fuji", "Wide Angle"
    let reason: String            // e.g. "Camera: Fujifilm X-T5" or "35mm eq. 24mm"
    let categoryID: UUID?         // nil = suggest new tag, not = existing category
    let confidence: Confidence    // .high, .medium, .low
    let source: SuggestionSource  // .visionML or .exifRule
}

enum Confidence: String, Codable, Sendable {
    case high
    case medium
    case low
}
