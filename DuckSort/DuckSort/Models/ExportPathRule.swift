//
//  ExportPathRule.swift
//  PhotomatorSort
//
//  Folder rules used to build the destination path for a photo during
//  copy, move, or JPEG export. Rules are an ordered list of components.
//  Each component contributes one folder level beneath the base destination.
//

import Foundation

enum ExportPathComponent: Codable, Hashable, Identifiable, Sendable {
    case cameraModel
    case lensModel
    case captureDate
    case tagCategory(UUID)        // category id
    case customText(String)
    case year
    case month
    case day
    case camera
    case lens
    case iso
    case aperture
    case shutterSpeed
    case ratingStars
    case flagStatus
    case primaryTag

    var id: String {
        switch self {
        case .cameraModel:            return "cameraModel"
        case .lensModel:              return "lensModel"
        case .captureDate:            return "captureDate"
        case .tagCategory(let id):    return "tagCategory:\(id.uuidString)"
        case .customText(let text):   return "customText:\(text)"
        case .year:                   return "year"
        case .month:                  return "month"
        case .day:                    return "day"
        case .camera:                 return "camera"
        case .lens:                   return "lens"
        case .iso:                    return "iso"
        case .aperture:               return "aperture"
        case .shutterSpeed:           return "shutterSpeed"
        case .ratingStars:            return "ratingStars"
        case .flagStatus:             return "flagStatus"
        case .primaryTag:             return "primaryTag"
        }
    }

    var displayName: String {
        switch self {
        case .cameraModel:            return "Camera Model (Legacy)"
        case .lensModel:              return "Lens Model (Legacy)"
        case .captureDate:            return "Capture Date (Legacy)"
        case .tagCategory:            return "Tag Category"
        case .customText:             return "Custom Text"
        case .year:                   return "Year"
        case .month:                  return "Month"
        case .day:                    return "Day"
        case .camera:                 return "Camera"
        case .lens:                   return "Lens"
        case .iso:                    return "ISO"
        case .aperture:               return "Aperture"
        case .shutterSpeed:           return "Shutter Speed"
        case .ratingStars:            return "Rating"
        case .flagStatus:             return "Flag Status"
        case .primaryTag:             return "Primary Tag"
        }
    }

    var systemImage: String {
        switch self {
        case .cameraModel:            return "camera"
        case .lensModel:              return "camera.macro"
        case .captureDate:            return "calendar"
        case .tagCategory:            return "tag"
        case .customText:             return "textformat"
        case .year:                   return "calendar.badge.clock"
        case .month:                  return "calendar.badge.plus"
        case .day:                    return "calendar"
        case .camera:                 return "camera.fill"
        case .lens:                   return "camera.aperture"
        case .iso:                    return "slider.horizontal.3"
        case .aperture:               return "f.circle"
        case .shutterSpeed:           return "timer"
        case .ratingStars:            return "star"
        case .flagStatus:             return "flag"
        case .primaryTag:             return "tag.fill"
        }
    }
}

struct ExportPathRule: Codable, Identifiable, Hashable, Sendable {
    var id: UUID
    var name: String
    var components: [ExportPathComponent]

    init(
        id: UUID = UUID(),
        name: String = "Untitled Rule",
        components: [ExportPathComponent] = []
    ) {
        self.id = id
        self.name = name
        self.components = components
    }

    static let defaultRule: ExportPathRule = ExportPathRule(
        name: "Camera / People / Scene / Action",
        components: [.cameraModel, .tagCategory(UUID()), .tagCategory(UUID()), .tagCategory(UUID())]
    )
}

// MARK: - Router

enum ExportPathRouter {
    /// Build a destination folder for a single photo by walking the rule's components.
    /// Tag categories are resolved using `categoryNameProvider` (category id -> name).
    static func destinationFolders(
        base: URL,
        rule: [ExportPathComponent],
        metadata: MetadataSnapshot,
        assignedTags: [CustomTag],
        categoryNameProvider: (UUID) -> String?,
        dateFolderFormatter: (Date) -> String = defaultDateFolderFormatter
    ) -> [URL] {
        var currentFolders: [URL] = [base]

        for component in rule {
            var nextFolders: [URL] = []
            for folder in currentFolders {
                switch component {
                case .cameraModel:
                    let name = FilenameSanitizer.clean(
                        metadata.cameraModel ?? "",
                        fallback: "Unknown Camera"
                    )
                    nextFolders.append(folder.appendingPathComponent(name))

                case .lensModel:
                    let name = FilenameSanitizer.clean(
                        metadata.lensModel ?? "",
                        fallback: "Unknown Lens"
                    )
                    nextFolders.append(folder.appendingPathComponent(name))

                case .captureDate:
                    let name: String
                    if let date = metadata.captureDate {
                        name = dateFolderFormatter(date)
                    } else {
                        name = "Unknown Date"
                    }
                    nextFolders.append(folder.appendingPathComponent(name))

                case .tagCategory(let categoryID):
                    let categoryName = categoryNameProvider(categoryID) ?? "Uncategorized"
                    let matching = assignedTags
                        .filter { $0.categoryID == categoryID }
                        .map { FilenameSanitizer.clean($0.name, fallback: "Unnamed") }

                    if matching.isEmpty {
                        nextFolders.append(folder.appendingPathComponent("No \(categoryName)"))
                    } else {
                        for tag in matching {
                            nextFolders.append(folder.appendingPathComponent(tag))
                        }
                    }

                case .customText(let text):
                    let cleaned = FilenameSanitizer.clean(text, fallback: "")
                    if !cleaned.isEmpty {
                        nextFolders.append(folder.appendingPathComponent(cleaned))
                    } else {
                        nextFolders.append(folder)
                    }

                case .year:
                    let name: String
                    if let date = metadata.captureDate {
                        name = String(format: "%04d", Calendar.current.component(.year, from: date))
                    } else {
                        name = "Unknown Year"
                    }
                    nextFolders.append(folder.appendingPathComponent(name))

                case .month:
                    let name: String
                    if let date = metadata.captureDate {
                        name = String(format: "%02d", Calendar.current.component(.month, from: date))
                    } else {
                        name = "Unknown Month"
                    }
                    nextFolders.append(folder.appendingPathComponent(name))

                case .day:
                    let name: String
                    if let date = metadata.captureDate {
                        name = String(format: "%02d", Calendar.current.component(.day, from: date))
                    } else {
                        name = "Unknown Day"
                    }
                    nextFolders.append(folder.appendingPathComponent(name))

                case .camera:
                    let name = FilenameSanitizer.clean(
                        metadata.cameraModel ?? "",
                        fallback: "Unknown Camera"
                    )
                    nextFolders.append(folder.appendingPathComponent(name))

                case .lens:
                    let name = FilenameSanitizer.clean(
                        metadata.lensModel ?? "",
                        fallback: "Unknown Lens"
                    )
                    nextFolders.append(folder.appendingPathComponent(name))

                case .iso:
                    let name: String
                    if let iso = metadata.iso {
                        name = "ISO \(iso)"
                    } else {
                        name = "Unknown ISO"
                    }
                    nextFolders.append(folder.appendingPathComponent(name))

                case .aperture:
                    let name: String
                    if let aperture = metadata.aperture {
                        let valStr = aperture.truncatingRemainder(dividingBy: 1) == 0
                            ? String(format: "%.0f", aperture)
                            : String(format: "%.1f", aperture)
                        name = "f\(valStr)"
                    } else {
                        name = "Unknown Aperture"
                    }
                    nextFolders.append(folder.appendingPathComponent(name))

                case .shutterSpeed:
                    let name: String
                    if let value = metadata.shutterSpeed, value > 0 {
                        if value >= 1 {
                            name = String(format: "%.1fs", value)
                        } else {
                            name = "1-\(Int(round(1.0 / value)))s"
                        }
                    } else {
                        name = "Unknown Shutter Speed"
                    }
                    nextFolders.append(folder.appendingPathComponent(name))

                case .ratingStars:
                    let rating = metadata.rating ?? 0
                    nextFolders.append(folder.appendingPathComponent("\(rating)_stars"))

                case .flagStatus:
                    let flag = metadata.pick ?? 0
                    let name: String
                    if flag == 1 {
                        name = "Flagged"
                    } else if flag == -1 {
                        name = "Rejected"
                    } else {
                        name = "Unflagged"
                    }
                    nextFolders.append(folder.appendingPathComponent(name))

                case .primaryTag:
                    let name = FilenameSanitizer.clean(
                        assignedTags.first?.name ?? "",
                        fallback: "Untagged"
                    )
                    nextFolders.append(folder.appendingPathComponent(name))
                }
            }
            currentFolders = nextFolders
        }

        return currentFolders
    }

    /// Pretty-print a rule for the configuration UI.
    static func describe(
        _ rule: [ExportPathComponent],
        categoryNameProvider: (UUID) -> String?
    ) -> String {
        rule.map { component in
            switch component {
            case .cameraModel:            return "Camera Model (Legacy)"
            case .lensModel:              return "Lens Model (Legacy)"
            case .captureDate:            return "Date (Legacy)"
            case .tagCategory(let id):
                return categoryNameProvider(id) ?? "Tag"
            case .customText(let text):   return text
            case .year:                   return "Year"
            case .month:                  return "Month"
            case .day:                    return "Day"
            case .camera:                 return "Camera"
            case .lens:                   return "Lens"
            case .iso:                    return "ISO"
            case .aperture:               return "Aperture"
            case .shutterSpeed:           return "Shutter"
            case .ratingStars:            return "Rating"
            case .flagStatus:             return "Flag"
            case .primaryTag:             return "Primary Tag"
            }
        }.joined(separator: " / ")
    }

    /// Cached DateFormatter shared across every routed photo. DateFormatter
    /// creation is ~50–100µs per call; allocating one per photo on a 5,000
    /// photo transfer would cost ~0.25–0.5s for no good reason.
    private static let cachedDateFolderFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()

    static func defaultDateFolderFormatter(_ date: Date) -> String {
        cachedDateFolderFormatter.string(from: date)
    }
}
