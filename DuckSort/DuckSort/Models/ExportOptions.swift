//
//  ExportOptions.swift
//  PhotomatorSort
//

import Foundation



struct MetadataSnapshot: Sendable {
    var cameraModel: String? = nil
    var lensModel: String? = nil
    var captureDate: Date? = nil
    var aperture: Double? = nil
    var shutterSpeed: Double? = nil
    var iso: Int? = nil
    var rating: Int? = nil
    var pick: Int? = nil

    // Advanced EXIF fields
    var focalLength: Double? = nil
    var focalLengthIn35mm: Double? = nil
    var whiteBalance: String? = nil
    var flashFired: Bool? = nil
    var flashMode: String? = nil
    var pixelWidth: Int? = nil
    var pixelHeight: Int? = nil
    var orientation: Int? = nil
    var colorSpace: String? = nil
    var colorProfile: String? = nil
    var gpsLatitude: Double? = nil
    var gpsLongitude: Double? = nil
    var gpsAltitude: Double? = nil
    var exposureProgram: String? = nil
    var meteringMode: String? = nil
    var exposureBias: Double? = nil
    var caption: String? = nil
    var keywords: Set<String> = []

    init(
        cameraModel: String? = nil,
        lensModel: String? = nil,
        captureDate: Date? = nil,
        aperture: Double? = nil,
        shutterSpeed: Double? = nil,
        iso: Int? = nil,
        rating: Int? = nil,
        pick: Int? = nil,
        focalLength: Double? = nil,
        focalLengthIn35mm: Double? = nil,
        whiteBalance: String? = nil,
        flashFired: Bool? = nil,
        flashMode: String? = nil,
        pixelWidth: Int? = nil,
        pixelHeight: Int? = nil,
        orientation: Int? = nil,
        colorSpace: String? = nil,
        colorProfile: String? = nil,
        gpsLatitude: Double? = nil,
        gpsLongitude: Double? = nil,
        gpsAltitude: Double? = nil,
        exposureProgram: String? = nil,
        meteringMode: String? = nil,
        exposureBias: Double? = nil,
        caption: String? = nil,
        keywords: Set<String> = []
    ) {
        self.cameraModel = cameraModel
        self.lensModel = lensModel
        self.captureDate = captureDate
        self.aperture = aperture
        self.shutterSpeed = shutterSpeed
        self.iso = iso
        self.rating = rating
        self.pick = pick
        self.focalLength = focalLength
        self.focalLengthIn35mm = focalLengthIn35mm
        self.whiteBalance = whiteBalance
        self.flashFired = flashFired
        self.flashMode = flashMode
        self.pixelWidth = pixelWidth
        self.pixelHeight = pixelHeight
        self.orientation = orientation
        self.colorSpace = colorSpace
        self.colorProfile = colorProfile
        self.gpsLatitude = gpsLatitude
        self.gpsLongitude = gpsLongitude
        self.gpsAltitude = gpsAltitude
        self.exposureProgram = exposureProgram
        self.meteringMode = meteringMode
        self.exposureBias = exposureBias
        self.caption = caption
        self.keywords = keywords
    }
}

/// Photographer / copyright / contact metadata that gets embedded into
/// every export sidecar when the user has opted in via Settings → Copyright.
/// All fields are optional — only the ones the user has filled in are
/// written to the XMP packet.
struct IPTCMetadata: Sendable, Equatable {
    var creatorName: String?
    var copyrightNotice: String?
    var contactEmail: String?
    var contactPhone: String?
    var contactWebsite: String?
    var rightsUsageTerms: String?
}

/// Everything an export sidecar records for one destination file:
/// the custom tag keywords, the capture metadata snapshot, and any
/// IPTC/copyright fields the user has configured.
struct SidecarPayload: Sendable {
    let tagNames: Set<String>
    let capture: MetadataSnapshot
    let iptc: IPTCMetadata
}

struct FileOperationProgress: Sendable {
    let completed: Int
    let total: Int
    let currentName: String
    
    // Bytes tracking
    let completedBytes: Int64
    let totalBytes: Int64
    let bytesPerSecond: Double

    var displayText: String {
        "\(completed)/\(total): \(currentName)"
    }
}

