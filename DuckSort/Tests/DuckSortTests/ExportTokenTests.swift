import Testing
import Foundation
@testable import DuckSort

struct ExportTokenTests {

    @Test
    func tokenResolution_withCompleteMetadata() {
        let base = URL(fileURLWithPath: "/tmp/export")
        let metadata = MetadataSnapshot(
            cameraModel: "Fujifilm X-T5",
            lensModel: "XF 56mm f/1.2 R WR",
            captureDate: Date(timeIntervalSince1970: 1782729600), // 2026-07-29 approx
            aperture: 1.2,
            shutterSpeed: 0.004, // 1/250s
            iso: 800,
            rating: 4,
            pick: 1
        )
        
        let assignedTags = [
            CustomTag(id: UUID(), name: "Landscape", categoryID: UUID(), colorHex: "#FF0000"),
            CustomTag(id: UUID(), name: "Sunset", categoryID: UUID(), colorHex: "#00FF00")
        ]

        let dummyCategoryMap: (UUID) -> String? = { _ in nil }

        // Test year
        let yearFolders = ExportPathRouter.destinationFolders(
            base: base,
            rule: [.year],
            metadata: metadata,
            assignedTags: assignedTags,
            categoryNameProvider: dummyCategoryMap
        )
        #expect(yearFolders.first?.lastPathComponent == "2026")

        // Test month (2026-07-29 -> 07 or 06 depending on timezone, let's format it dynamically to be timezone-independent)
        let calendar = Calendar.current
        let expectedMonth = String(format: "%02d", calendar.component(.month, from: metadata.captureDate!))
        let monthFolders = ExportPathRouter.destinationFolders(
            base: base,
            rule: [.month],
            metadata: metadata,
            assignedTags: assignedTags,
            categoryNameProvider: dummyCategoryMap
        )
        #expect(monthFolders.first?.lastPathComponent == expectedMonth)

        // Test day
        let expectedDay = String(format: "%02d", calendar.component(.day, from: metadata.captureDate!))
        let dayFolders = ExportPathRouter.destinationFolders(
            base: base,
            rule: [.day],
            metadata: metadata,
            assignedTags: assignedTags,
            categoryNameProvider: dummyCategoryMap
        )
        #expect(dayFolders.first?.lastPathComponent == expectedDay)

        // Test camera
        let cameraFolders = ExportPathRouter.destinationFolders(
            base: base,
            rule: [.camera],
            metadata: metadata,
            assignedTags: assignedTags,
            categoryNameProvider: dummyCategoryMap
        )
        #expect(cameraFolders.first?.lastPathComponent == "Fujifilm X-T5")

        // Test lens
        let lensFolders = ExportPathRouter.destinationFolders(
            base: base,
            rule: [.lens],
            metadata: metadata,
            assignedTags: assignedTags,
            categoryNameProvider: dummyCategoryMap
        )
        #expect(lensFolders.first?.lastPathComponent == "XF 56mm f-1.2 R WR") // cleaned by FilenameSanitizer slash -> dash

        // Test iso
        let isoFolders = ExportPathRouter.destinationFolders(
            base: base,
            rule: [.iso],
            metadata: metadata,
            assignedTags: assignedTags,
            categoryNameProvider: dummyCategoryMap
        )
        #expect(isoFolders.first?.lastPathComponent == "ISO 800")

        // Test aperture
        let apertureFolders = ExportPathRouter.destinationFolders(
            base: base,
            rule: [.aperture],
            metadata: metadata,
            assignedTags: assignedTags,
            categoryNameProvider: dummyCategoryMap
        )
        #expect(apertureFolders.first?.lastPathComponent == "f1.2")

        // Test shutterSpeed
        let shutterFolders = ExportPathRouter.destinationFolders(
            base: base,
            rule: [.shutterSpeed],
            metadata: metadata,
            assignedTags: assignedTags,
            categoryNameProvider: dummyCategoryMap
        )
        #expect(shutterFolders.first?.lastPathComponent == "1-250s")

        // Test ratingStars
        let ratingFolders = ExportPathRouter.destinationFolders(
            base: base,
            rule: [.ratingStars],
            metadata: metadata,
            assignedTags: assignedTags,
            categoryNameProvider: dummyCategoryMap
        )
        #expect(ratingFolders.first?.lastPathComponent == "4_stars")

        // Test flagStatus
        let flagFolders = ExportPathRouter.destinationFolders(
            base: base,
            rule: [.flagStatus],
            metadata: metadata,
            assignedTags: assignedTags,
            categoryNameProvider: dummyCategoryMap
        )
        #expect(flagFolders.first?.lastPathComponent == "Flagged")

        // Test primaryTag
        let tagFolders = ExportPathRouter.destinationFolders(
            base: base,
            rule: [.primaryTag],
            metadata: metadata,
            assignedTags: assignedTags,
            categoryNameProvider: dummyCategoryMap
        )
        #expect(tagFolders.first?.lastPathComponent == "Landscape")
    }

    @Test
    func tokenResolution_withMissingMetadata() {
        let base = URL(fileURLWithPath: "/tmp/export")
        let emptyMetadata = MetadataSnapshot()
        let assignedTags: [CustomTag] = []
        let dummyCategoryMap: (UUID) -> String? = { _ in nil }

        let rule: [ExportPathComponent] = [
            .year, .month, .day, .camera, .lens, .iso, .aperture, .shutterSpeed, .ratingStars, .flagStatus, .primaryTag
        ]

        let folders = ExportPathRouter.destinationFolders(
            base: base,
            rule: rule,
            metadata: emptyMetadata,
            assignedTags: assignedTags,
            categoryNameProvider: dummyCategoryMap
        )

        // Make sure the resolved path exists and has all fallbacks correctly formatted
        let resolvedURL = folders.first!
        let components = resolvedURL.pathComponents.suffix(rule.count)
        
        let expected = [
            "Unknown Year",
            "Unknown Month",
            "Unknown Day",
            "Unknown Camera",
            "Unknown Lens",
            "Unknown ISO",
            "Unknown Aperture",
            "Unknown Shutter Speed",
            "0_stars",
            "Unflagged",
            "Untagged"
        ]

        #expect(Array(components) == expected)
    }

    @Test
    func tokenResolution_apertureWholeNumber() {
        let base = URL(fileURLWithPath: "/tmp/export")
        let metadata = MetadataSnapshot(aperture: 4.0)
        let dummyCategoryMap: (UUID) -> String? = { _ in nil }

        let folders = ExportPathRouter.destinationFolders(
            base: base,
            rule: [.aperture],
            metadata: metadata,
            assignedTags: [],
            categoryNameProvider: dummyCategoryMap
        )
        #expect(folders.first?.lastPathComponent == "f4")
    }

    @Test
    func tokenResolution_shutterSpeedSlow() {
        let base = URL(fileURLWithPath: "/tmp/export")
        let metadata = MetadataSnapshot(shutterSpeed: 1.5)
        let dummyCategoryMap: (UUID) -> String? = { _ in nil }

        let folders = ExportPathRouter.destinationFolders(
            base: base,
            rule: [.shutterSpeed],
            metadata: metadata,
            assignedTags: [],
            categoryNameProvider: dummyCategoryMap
        )
        #expect(folders.first?.lastPathComponent == "1.5s")
    }
}
