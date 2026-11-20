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
            if !CGImageDestinationFinalize(destination) {
                throw NSError(domain: "EXIFSanitizer", code: 3, userInfo: [NSLocalizedDescriptionKey: "Failed to finalize sanitized image write"])
            }
            return
        }
        
        var mutableProperties = properties
        
        if stripLocation {
            // ImageIO merges dictionaries over source metadata; kCFNull explicitly deletes the key.
            mutableProperties[kCGImagePropertyGPSDictionary as String] = kCFNull
        }
        
        if stripCameraInfo, var exif = mutableProperties[kCGImagePropertyExifDictionary as String] as? [String: Any] {
            exif[kCGImagePropertyExifBodySerialNumber as String] = kCFNull
            exif[kCGImagePropertyExifLensSerialNumber as String] = kCFNull
            exif[kCGImagePropertyExifCameraOwnerName as String] = kCFNull
            mutableProperties[kCGImagePropertyExifDictionary as String] = exif
        }
        
        CGImageDestinationAddImageFromSource(destination, source, 0, mutableProperties as CFDictionary)
        if !CGImageDestinationFinalize(destination) {
            throw NSError(domain: "EXIFSanitizer", code: 3, userInfo: [NSLocalizedDescriptionKey: "Failed to finalize sanitized image write"])
        }
    }
}
