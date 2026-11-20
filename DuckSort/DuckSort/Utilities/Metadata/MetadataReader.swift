//
//  MetadataReader.swift
//  PhotomatorSort
//

import Foundation
import ImageIO

struct MetadataReader: Sendable {
    private static let keysToPrecompile = [
        "tiff:Make", "Make", "tiff:Model", "Model",
        "exifEX:LensModel", "exif:LensModel", "aux:Lens", "LensModel", "Lens",
        "exif:FocalLengthIn35mmFilm", "exifEX:FocalLengthIn35mmFilm", "FocalLengthIn35mmFilm",
        "exif:FocalLength", "FocalLength", "exif:ISOSpeedRatings",
        "exif:RecommendedExposureIndex", "exifEX:RecommendedExposureIndex", "ISOSpeedRatings",
        "exif:FNumber", "exif:ApertureValue", "FNumber",
        "exif:Fired", "stEvt:action", "Fired", "exif:Flash", "Flash",
        "tiff:ImageWidth", "exif:PixelXDimension", "ImageWidth",
        "tiff:ImageLength", "exif:PixelYDimension", "ImageLength",
        "exif:DateTimeOriginal", "xmp:CreateDate", "photoshop:DateCreated", "CreateDate", "DateTimeOriginal"
    ]

    private static let precompiledAttrRegexes: [String: NSRegularExpression] = {
        var dict: [String: NSRegularExpression] = [:]
        for key in keysToPrecompile {
            let pattern = #"\b"# + NSRegularExpression.escapedPattern(for: key) + #"\s*=\s*["']([^"']+)["']"#
            dict[key] = try! NSRegularExpression(pattern: pattern, options: [])
        }
        return dict
    }()

    private static let precompiledTagRegexes: [String: NSRegularExpression] = {
        var dict: [String: NSRegularExpression] = [:]
        for key in keysToPrecompile {
            let pattern = #"<"# + NSRegularExpression.escapedPattern(for: key) + #"\b[^>]*>([^<]+)</"# + NSRegularExpression.escapedPattern(for: key) + #">"#
            dict[key] = try! NSRegularExpression(pattern: pattern, options: [])
        }
        return dict
    }()

    private static let seqRegexes: [String: NSRegularExpression] = {
        var dict: [String: NSRegularExpression] = [:]
        let keys = ["exif:ISOSpeedRatings"]
        for key in keys {
            let pattern = #"<"# + NSRegularExpression.escapedPattern(for: key) + #"\b[^>]*>.*?<rdf:li[^>]*>([^<]+)</rdf:li>.*?</"# + NSRegularExpression.escapedPattern(for: key) + #">"#
            dict[key] = try! NSRegularExpression(pattern: pattern, options: [.dotMatchesLineSeparators])
        }
        return dict
    }()

    func metadata(for url: URL) -> MetadataSnapshot {
        AppLogger.metadata.debug("Reading metadata: \(url.lastPathComponent)")

        if url.pathExtension.lowercased() == "xmp" {
            if let data = try? Data(contentsOf: url), let xmlString = String(data: data, encoding: .utf8) {
                return parseXMPText(xmlString)
            }
        }

        // Wrap in autoreleasepool to bound the lifetime of transient ObjC
        // bridge objects (CGImageSource, NSDictionary) during batch loads.
        // Without this, rapid serial calls to metadata(for:) can cause
        // a temporary memory spike before ARC can drain the pool.
        return autoreleasepool {
            let ext = url.pathExtension.lowercased()
            let shouldCache = FileExtension.heifLikeExtensions.contains(ext)
            var options: [CFString: Any] = [kCGImageSourceShouldCache: shouldCache]
            if let typeHint = FileExtension.typeIdentifierHint(for: ext) {
                options[kCGImageSourceTypeIdentifierHint] = typeHint
            }
            guard let source = CGImageSourceCreateWithURL(url as CFURL, options as CFDictionary),
                  let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as NSDictionary?
            else {
                let attrs = try? FileManager.default.attributesOfItem(atPath: url.path)
                let fileSize = (attrs?[.size] as? Int64) ?? Int64.max
                if fileSize <= 1_048_576,
                   let data = try? Data(contentsOf: url),
                   let xmlString = String(data: data, encoding: .utf8) {
                    AppLogger.metadata.info("Falling back to XMP text parse for \(url.lastPathComponent)")
                    return parseXMPText(xmlString)
                }
                // File system fallback for missing source
                AppLogger.metadata.info("Falling back to file attributes for \(url.lastPathComponent)")
                var snapshot = MetadataSnapshot()
                if let fileCreationDate = attrs?[.creationDate] as? Date {
                    snapshot.captureDate = fileCreationDate
                }
                return snapshot
            }

            let tiff = properties[kCGImagePropertyTIFFDictionary] as? NSDictionary
            let exif = properties[kCGImagePropertyExifDictionary] as? NSDictionary
            let gps = properties[kCGImagePropertyGPSDictionary] as? NSDictionary
            let iptc = properties[kCGImagePropertyIPTCDictionary] as? NSDictionary
            let png = properties[kCGImagePropertyPNGDictionary] as? NSDictionary

            let cameraModel = tiff?[kCGImagePropertyTIFFModel] as? String
            let lensModel = exif?[kCGImagePropertyExifLensModel] as? String

            // Exif datetime -> TIFF datetime -> IPTC datetime
            var captureDateString = exif?[kCGImagePropertyExifDateTimeOriginal] as? String
                ?? tiff?[kCGImagePropertyTIFFDateTime] as? String

            if captureDateString == nil, let iptc = iptc {
                if let dateStr = iptc[kCGImagePropertyIPTCDateCreated] as? String {
                    if let timeStr = iptc[kCGImagePropertyIPTCTimeCreated] as? String {
                        captureDateString = "\(dateStr) \(timeStr)"
                    } else {
                        captureDateString = dateStr
                    }
                }
            }

            var captureDate = captureDateString.flatMap(Self.parseExifDate)

            let aperture = exif?[kCGImagePropertyExifFNumber] as? Double
            let shutterSpeed = exif?[kCGImagePropertyExifExposureTime] as? Double
            let isoArray = exif?[kCGImagePropertyExifISOSpeedRatings] as? [Int]

            // Advanced fields
            let focalLength = exif?[kCGImagePropertyExifFocalLength] as? Double
            let focalLengthIn35mm = exif?[kCGImagePropertyExifFocalLenIn35mmFilm] as? Double
            let whiteBalanceRaw = exif?[kCGImagePropertyExifWhiteBalance] as? Int
            let flashRaw = exif?[kCGImagePropertyExifFlash] as? Int
            let exposureProgramRaw = exif?[kCGImagePropertyExifExposureProgram] as? Int
            let meteringModeRaw = exif?[kCGImagePropertyExifMeteringMode] as? Int
            let exposureBias = exif?[kCGImagePropertyExifExposureBiasValue] as? Double

            let pixelWidth = properties[kCGImagePropertyPixelWidth] as? Int
            let pixelHeight = properties[kCGImagePropertyPixelHeight] as? Int
            let orientation = properties[kCGImagePropertyOrientation] as? Int
            let colorSpaceRaw = properties[kCGImagePropertyColorModel] as? String
            let profileName = properties[kCGImagePropertyProfileName] as? String

            var gpsLatitude = gps?[kCGImagePropertyGPSLatitude] as? Double
            if let lat = gpsLatitude,
               let latRef = (gps?[kCGImagePropertyGPSLatitudeRef] as? String)?.uppercased(),
               latRef == "S" {
                gpsLatitude = -abs(lat)
            }
            var gpsLongitude = gps?[kCGImagePropertyGPSLongitude] as? Double
            if let lon = gpsLongitude,
               let lonRef = (gps?[kCGImagePropertyGPSLongitudeRef] as? String)?.uppercased(),
               lonRef == "W" {
                gpsLongitude = -abs(lon)
            }
            var gpsAltitude = gps?[kCGImagePropertyGPSAltitude] as? Double
            if let alt = gpsAltitude,
               let altRef = gps?[kCGImagePropertyGPSAltitudeRef] as? Int,
               altRef == 1 {
                gpsAltitude = -abs(alt)
            }

            var rating: Int? = nil
            var pick: Int? = nil
            var keywords = Set<String>()
            var caption: String? = nil

            if let iptc = iptc {
                rating = iptc[kCGImagePropertyIPTCStarRating] as? Int

                if let kwList = iptc[kCGImagePropertyIPTCKeywords] as? [String] {
                    for kw in kwList {
                        let trimmed = kw.trimmingCharacters(in: .whitespacesAndNewlines)
                        if !trimmed.isEmpty { keywords.insert(trimmed) }
                    }
                } else if let kwList = iptc[kCGImagePropertyIPTCKeywords] as? [Any] {
                    for kw in kwList {
                        if let s = kw as? String {
                            let trimmed = s.trimmingCharacters(in: .whitespacesAndNewlines)
                            if !trimmed.isEmpty { keywords.insert(trimmed) }
                        }
                    }
                } else if let kwStr = iptc[kCGImagePropertyIPTCKeywords] as? String {
                    let parts = kwStr.components(separatedBy: CharacterSet(charactersIn: ",;"))
                    for p in parts {
                        let trimmed = p.trimmingCharacters(in: .whitespacesAndNewlines)
                        if !trimmed.isEmpty { keywords.insert(trimmed) }
                    }
                }

                if let iptcCaption = iptc[kCGImagePropertyIPTCCaptionAbstract] as? String
                    ?? iptc[kCGImagePropertyIPTCHeadline] as? String
                    ?? iptc[kCGImagePropertyIPTCObjectName] as? String {
                    let trimmed = iptcCaption.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !trimmed.isEmpty { caption = trimmed }
                }
            }

            if caption == nil, let tiffDesc = tiff?[kCGImagePropertyTIFFImageDescription] as? String {
                let trimmed = tiffDesc.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty { caption = trimmed }
            }

            if caption == nil, let exifComment = exif?[kCGImagePropertyExifUserComment] as? String {
                let trimmed = exifComment.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty { caption = trimmed }
            }

            if let png = png {
                if let pngDesc = png["Description"] as? String ?? png["Comment"] as? String {
                    let trimmed = pngDesc.trimmingCharacters(in: .whitespacesAndNewlines)
                    if caption == nil, !trimmed.isEmpty { caption = trimmed }
                }
                if let pngKw = png["Keywords"] as? [String] {
                    for kw in pngKw {
                        let trimmed = kw.trimmingCharacters(in: .whitespacesAndNewlines)
                        if !trimmed.isEmpty { keywords.insert(trimmed) }
                    }
                }
            }

            // Always check embedded XMP for tags, ratings, and capture date
            if let metadata = CGImageSourceCopyMetadataAtIndex(source, 0, nil) {
                if let xmpData = CGImageMetadataCreateXMPData(metadata, nil) as Data?,
                   let xmpString = String(data: xmpData, encoding: .utf8) {
                    let xmpSnapshot = parseXMPText(xmpString)
                    if rating == nil { rating = xmpSnapshot.rating }
                    if pick == nil   { pick   = xmpSnapshot.pick   }
                    if captureDate == nil { captureDate = xmpSnapshot.captureDate }
                    if caption == nil { caption = xmpSnapshot.caption }
                    keywords.formUnion(xmpSnapshot.keywords)
                } else {
                    CGImageMetadataEnumerateTagsUsingBlock(metadata, nil, nil) { path, tag in
                        let pathStr = path as String
                        if pathStr.contains("subject") || pathStr.contains("Keywords") || pathStr.contains("keywords") {
                            if let val = CGImageMetadataTagCopyValue(tag) as? String {
                                let trimmed = val.trimmingCharacters(in: .whitespacesAndNewlines)
                                if !trimmed.isEmpty { keywords.insert(trimmed) }
                            } else if let valArray = CGImageMetadataTagCopyValue(tag) as? [String] {
                                for v in valArray {
                                    let trimmed = v.trimmingCharacters(in: .whitespacesAndNewlines)
                                    if !trimmed.isEmpty { keywords.insert(trimmed) }
                                }
                            }
                        } else if pathStr.contains("description") || pathStr.contains("Caption") {
                            if caption == nil, let val = CGImageMetadataTagCopyValue(tag) as? String {
                                let trimmed = val.trimmingCharacters(in: .whitespacesAndNewlines)
                                if !trimmed.isEmpty { caption = trimmed }
                            }
                        }
                        return true
                    }
                }
            }

            // Also check Finder tags and Finder keywords stored in macOS extended attributes
            let finderTags = Self.readFinderTags(from: url)
            keywords.formUnion(finderTags)

            // Final File System Fallback
            if captureDate == nil {
                if let attrs = try? FileManager.default.attributesOfItem(atPath: url.path),
                   let fileCreationDate = attrs[.creationDate] as? Date {
                    captureDate = fileCreationDate
                }
            }

            return MetadataSnapshot(
                cameraModel: cameraModel,
                lensModel: lensModel,
                captureDate: captureDate,
                aperture: aperture,
                shutterSpeed: shutterSpeed,
                iso: isoArray?.first,
                rating: rating,
                pick: pick,
                focalLength: focalLength,
                focalLengthIn35mm: focalLengthIn35mm,
                whiteBalance: Self.whiteBalanceLabel(whiteBalanceRaw),
                flashFired: Self.flashFired(flashRaw),
                flashMode: Self.flashModeLabel(flashRaw),
                pixelWidth: pixelWidth,
                pixelHeight: pixelHeight,
                orientation: orientation,
                colorSpace: Self.colorSpaceLabel(colorSpaceRaw),
                colorProfile: profileName,
                gpsLatitude: gpsLatitude,
                gpsLongitude: gpsLongitude,
                gpsAltitude: gpsAltitude,
                exposureProgram: Self.exposureProgramLabel(exposureProgramRaw),
                meteringMode: Self.meteringModeLabel(meteringModeRaw),
                exposureBias: exposureBias,
                caption: caption,
                keywords: keywords
            )
        } // end autoreleasepool
    }
    private static func whiteBalanceLabel(_ raw: Int?) -> String? {
        guard let raw else { return nil }
        switch raw {
        case 0: return "Auto"
        case 1: return "Manual"
        default: return "Unknown (\(raw))"
        }
    }

    private static func flashFired(_ raw: Int?) -> Bool? {
        guard let raw else { return nil }
        // Bit 0 indicates whether the flash fired.
        return (raw & 0x1) == 0x1
    }

    private static func flashModeLabel(_ raw: Int?) -> String? {
        guard let raw else { return nil }
        switch raw & 0x18 {
        case 0x08: return "On"
        case 0x10: return "Off"
        case 0x18: return "Auto"
        default:   return "Unknown"
        }
    }

    private static func exposureProgramLabel(_ raw: Int?) -> String? {
        guard let raw else { return nil }
        switch raw {
        case 0: return "Not defined"
        case 1: return "Manual"
        case 2: return "Program AE"
        case 3: return "Aperture-priority AE"
        case 4: return "Shutter speed priority AE"
        case 5: return "Creative (Slow speed)"
        case 6: return "Action (High speed)"
        case 7: return "Portrait"
        case 8: return "Landscape"
        default: return "Unknown (\(raw))"
        }
    }

    private static func meteringModeLabel(_ raw: Int?) -> String? {
        guard let raw else { return nil }
        switch raw {
        case 0: return "Unknown"
        case 1: return "Average"
        case 2: return "Center-weighted average"
        case 3: return "Spot"
        case 4: return "Multi-spot"
        case 5: return "Pattern"
        case 6: return "Partial"
        default: return "Other (\(raw))"
        }
    }

    private static func colorSpaceLabel(_ raw: String?) -> String? {
        guard let raw else { return nil }
        switch raw {
        case String(kCGImagePropertyColorModelRGB): return "sRGB / RGB"
        case String(kCGImagePropertyColorModelGray): return "Grayscale"
        case String(kCGImagePropertyColorModelCMYK): return "CMYK"
        case String(kCGImagePropertyColorModelLab): return "Lab"
        default: return raw
        }
    }

    nonisolated(unsafe) private static let isoFormatterFractional: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    nonisolated(unsafe) private static let isoFormatterPlain: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()

    private static let gregorianCalendar: Calendar = {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = .current
        return cal
    }()

    static func parseExifDate(_ string: String) -> Date? {
        let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 10 else { return nil }

        // Attempt 1: ISO8601 formatting (with/without fractional seconds or offsets)
        if let date = isoFormatterFractional.date(from: trimmed) {
            return date
        }
        if let date = isoFormatterPlain.date(from: trimmed) {
            return date
        }

        // Attempt 2: Direct numeric separator scanning (safely handles YYYY:MM:DD, YYYY-MM-DD, YYYY/MM/DD)
        let utf8 = Array(trimmed.utf8)
        
        func parseSlice(start: Int, len: Int) -> Int? {
            guard start + len <= utf8.count else { return nil }
            var val = 0
            for i in 0..<len {
                let char = utf8[start + i]
                guard char >= 48 && char <= 57 else { return nil }
                val = val * 10 + Int(char - 48)
            }
            return val
        }

        guard let year = parseSlice(start: 0, len: 4),
              let month = parseSlice(start: 5, len: 2),
              let day = parseSlice(start: 8, len: 2)
        else {
            return nil
        }

        var hour = 0
        var minute = 0
        var second = 0

        if utf8.count >= 19 {
            if let h = parseSlice(start: 11, len: 2),
               let m = parseSlice(start: 14, len: 2),
               let s = parseSlice(start: 17, len: 2) {
                hour = h
                minute = m
                second = s
            }
        }

        var dateComponents = DateComponents()
        dateComponents.year = year
        dateComponents.month = month
        dateComponents.day = day
        dateComponents.hour = hour
        dateComponents.minute = minute
        dateComponents.second = second

        return gregorianCalendar.date(from: dateComponents)
    }

    private func parseXMPText(_ xml: String) -> MetadataSnapshot {
        let xmlRange = NSRange(xml.startIndex..., in: xml)

        func extractValue(forKeys keys: [String]) -> String? {
            for key in keys {
                guard xml.contains(key) else { continue }
                // Check attribute: key="val" or key='val'
                if let regex = Self.precompiledAttrRegexes[key],
                   let match = regex.firstMatch(in: xml, options: [], range: xmlRange),
                   let range = Range(match.range(at: 1), in: xml) {
                    return String(xml[range])
                }
                // Check tag: <key>val</key>
                if let regex = Self.precompiledTagRegexes[key],
                   let match = regex.firstMatch(in: xml, options: [], range: xmlRange),
                   let range = Range(match.range(at: 1), in: xml) {
                    return String(xml[range])
                }
            }
            return nil
        }

        func extractSeqValue(forKey key: String) -> String? {
            guard xml.contains(key) else { return nil }
            if let regex = Self.seqRegexes[key],
               let match = regex.firstMatch(in: xml, options: [], range: xmlRange),
               let range = Range(match.range(at: 1), in: xml) {
                return String(xml[range])
            }
            return nil
        }

        // 1. Camera Model
        let make = extractValue(forKeys: ["tiff:Make", "Make"])
        let model = extractValue(forKeys: ["tiff:Model", "Model"])
        var cameraModel: String? = nil
        if let make, let model {
            cameraModel = model.range(of: make, options: .caseInsensitive) != nil ? model : "\(make) \(model)"
        } else {
            cameraModel = model ?? make
        }

        // 2. Lens Model
        let lensModel = extractValue(forKeys: ["exifEX:LensModel", "exif:LensModel", "aux:Lens", "LensModel", "Lens"])

        // 3. Focal Length & 35mm Equivalent
        func parseRational(_ str: String) -> Double? {
            if str.contains("/") {
                let parts = str.components(separatedBy: "/")
                if parts.count == 2, let num = Double(parts[0]), let den = Double(parts[1]), den > 0 {
                    return num / den
                }
                return nil
            }
            return Double(str)
        }

        let focalLength = extractValue(forKeys: ["exif:FocalLength", "FocalLength"]).flatMap(parseRational)
        let focalLengthIn35mm = extractValue(forKeys: ["exif:FocalLengthIn35mmFilm", "exifEX:FocalLengthIn35mmFilm", "FocalLengthIn35mmFilm"]).flatMap(parseRational)

        // 4. ISO
        var iso: Int? = nil
        if let isoStr = extractSeqValue(forKey: "exif:ISOSpeedRatings") ?? extractValue(forKeys: ["exif:ISOSpeedRatings", "exif:RecommendedExposureIndex", "exifEX:RecommendedExposureIndex", "ISOSpeedRatings"]) {
            iso = Int(isoStr)
        }

        // 5. Aperture (prefer FNumber; convert APEX ApertureValue via 2^(Av/2))
        var aperture: Double? = nil
        if let fnStr = extractValue(forKeys: ["exif:FNumber", "FNumber"]) {
            aperture = parseRational(fnStr)
        } else if let avStr = extractValue(forKeys: ["exif:ApertureValue"]),
                  let av = parseRational(avStr) {
            aperture = pow(2.0, av / 2.0)
        }

        // 6. Flash Fired
        var flashFired: Bool? = nil
        if let flashStr = extractValue(forKeys: ["exif:Fired", "Fired"]) {
            flashFired = flashStr.lowercased() == "true" || flashStr == "1"
        } else if let flashRawStr = extractValue(forKeys: ["exif:Flash", "Flash"]) {
            if let rawInt = Int(flashRawStr) {
                flashFired = (rawInt & 0x1) == 0x1
            } else {
                flashFired = flashRawStr.lowercased().contains("true") || flashRawStr.lowercased().contains("fired")
            }
        }

        // 7. Width and Height
        var width: Int? = nil
        var height: Int? = nil
        if let wStr = extractValue(forKeys: ["tiff:ImageWidth", "exif:PixelXDimension", "ImageWidth"]) { width = Int(wStr) }
        if let hStr = extractValue(forKeys: ["tiff:ImageLength", "exif:PixelYDimension", "ImageLength"]) { height = Int(hStr) }

        // 8. Date created
        var captureDate: Date? = nil
        if let dateStr = extractValue(forKeys: ["exif:DateTimeOriginal", "xmp:CreateDate", "photoshop:DateCreated", "CreateDate", "DateTimeOriginal"]) {
            captureDate = Self.parseExifDate(dateStr)
        }

        // 9. Star Rating & Pick/Reject Flags
        let rating = XMPTaggingService.extractRating(from: xml)
        let pick = XMPTaggingService.extractPick(from: xml)

        // 10. Keywords & Caption
        let keywords = Self.extractKeywords(from: xml)
        let caption = Self.extractDescription(from: xml)

        return MetadataSnapshot(
            cameraModel: cameraModel,
            lensModel: lensModel,
            captureDate: captureDate,
            aperture: aperture,
            shutterSpeed: nil,
            iso: iso,
            rating: rating,
            pick: pick,
            focalLength: focalLength,
            focalLengthIn35mm: focalLengthIn35mm,
            whiteBalance: nil,
            flashFired: flashFired,
            flashMode: nil,
            pixelWidth: width,
            pixelHeight: height,
            orientation: nil,
            colorSpace: nil,
            colorProfile: nil,
            gpsLatitude: nil,
            gpsLongitude: nil,
            gpsAltitude: nil,
            exposureProgram: nil,
            meteringMode: nil,
            exposureBias: nil,
            caption: caption,
            keywords: keywords
        )
    }

    static func extractKeywords(from xml: String) -> Set<String> {
        XMPTaggingService.extractKeywords(from: xml)
    }

    /// Reads macOS Finder tags and Finder keywords stored in file extended attributes (`xattr`).
    static func readFinderTags(from url: URL) -> Set<String> {
        var result = Set<String>()
        let path = url.path
        let length = getxattr(path, "com.apple.metadata:kMDItemUserTags", nil, 0, 0, 0)
        if length > 0 {
            var data = Data(count: length)
            let bytesRead = data.withUnsafeMutableBytes {
                getxattr(path, "com.apple.metadata:kMDItemUserTags", $0.baseAddress, length, 0, 0)
            }
            if bytesRead > 0,
               let plist = try? PropertyListSerialization.propertyList(from: data, options: [], format: nil) as? [String] {
                for tag in plist {
                    let name = tag.components(separatedBy: "\n").first?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                    if !name.isEmpty {
                        result.insert(name)
                    }
                }
            }
        }
        let kwLength = getxattr(path, "com.apple.metadata:kMDItemKeywords", nil, 0, 0, 0)
        if kwLength > 0 {
            var data = Data(count: kwLength)
            let bytesRead = data.withUnsafeMutableBytes {
                getxattr(path, "com.apple.metadata:kMDItemKeywords", $0.baseAddress, kwLength, 0, 0)
            }
            if bytesRead > 0,
               let plist = try? PropertyListSerialization.propertyList(from: data, options: [], format: nil) as? [String] {
                for kw in plist {
                    let trimmed = kw.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !trimmed.isEmpty {
                        result.insert(trimmed)
                    }
                }
            }
        }
        return result
    }

    static func extractDescription(from xml: String) -> String? {
        XMPTaggingService.extractDescription(from: xml)
    }

    static func unescapeXMP(_ value: String) -> String {
        XMPTaggingService.unescape(value)
    }
}


