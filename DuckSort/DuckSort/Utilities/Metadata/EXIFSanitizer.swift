//
//  EXIFSanitizer.swift
//  DuckSort
//
//  Privacy utility that strips sensitive EXIF metadata (GPS location,
//  camera serial numbers, owner names) before exporting assets.
//

import Foundation
import ImageIO

struct EXIFSanitizer: Sendable {
    
    /// Sanitizes an image file by creating a new version stripped of location and PII metadata.
    static func sanitizeImage(at sourceURL: URL, destinationURL: URL, stripLocation: Bool = true, stripCameraInfo: Bool = false) throws {
        guard let source = CGImageSourceCreateWithURL(sourceURL as CFURL, nil),
              let type = CGImageSourceGetType(source) else {
            throw NSError(domain: "EXIFSanitizer", code: 1, userInfo: [NSLocalizedDescriptionKey: "Failed to create image source"])
        }
        
        guard let destination = CGImageDestinationCreateWithURL(destinationURL as CFURL, type, 1, nil) else {
            throw NSError(domain: "EXIFSanitizer", code: 2, userInfo: [NSLocalizedDescriptionKey: "Failed to create image destination"])
        }
        
        guard let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [String: Any] else {
            CGImageDestinationAddImageFromSource(destination, source, 0, nil)
            CGImageDestinationFinalize(destination)
            return
        }
        
        var mutableProperties = properties
        
        if stripLocation {
            mutableProperties.removeValue(forKey: kCGImagePropertyGPSDictionary as String)
        }
        
        if stripCameraInfo, var exif = mutableProperties[kCGImagePropertyExifDictionary as String] as? [String: Any] {
            exif.removeValue(forKey: kCGImagePropertyExifBodySerialNumber as String)
            exif.removeValue(forKey: kCGImagePropertyExifLensSerialNumber as String)
            exif.removeValue(forKey: kCGImagePropertyExifCameraOwnerName as String)
            mutableProperties[kCGImagePropertyExifDictionary as String] = exif
        }
        
        CGImageDestinationAddImageFromSource(destination, source, 0, mutableProperties as CFDictionary)
        if !CGImageDestinationFinalize(destination) {
            throw NSError(domain: "EXIFSanitizer", code: 3, userInfo: [NSLocalizedDescriptionKey: "Failed to finalize sanitized image write"])
        }
    }
}
