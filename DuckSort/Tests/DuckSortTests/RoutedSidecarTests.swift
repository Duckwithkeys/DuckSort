import Testing
import Foundation
import ImageIO
@testable import DuckSort

struct RoutedSidecarTests {
    private func copySet(_ dir: URL) throws -> RoutedPhoto {
        let media = dir.appendingPathComponent("IMG_0001.jpg")
        try ImageFixture.writeJPEG(to: media, cameraModel: "X-T5", lensModel: "XF35mm", iso: 400)
        let set = PhotoSet(baseName: "IMG_0001", mediaFiles: [media], editPath: nil)
        return RoutedPhoto(
            photoSet: set,
            metadata: MetadataReader().metadata(for: media),
            tags: [CustomTag(name: "Family", categoryID: UUID())]
        )
    }

    @Test
    func copyOriginals_writesSidecar() async throws {
        let src = try TempDir.make(); let dst = try TempDir.make()
        defer { try? FileManager.default.removeItem(at: src); try? FileManager.default.removeItem(at: dst) }
        let routed = try copySet(src)

        let plan = RoutedPlan(
            operation: .copyOriginals,
            baseDestination: dst,
            rule: [],
            photos: [routed]
        )
        let summary = try await RoutedTransferService().execute(plan, categoryNameProvider: { _ in nil })

        #expect(summary.sidecarFailures == 0)
        let sidecar = dst.appendingPathComponent("IMG_0001.xmp")
        #expect(try String(contentsOf: sidecar, encoding: .utf8).contains("<rdf:li>Family</rdf:li>"))
    }


    @Test
    func moveOriginals_writesSidecarAndRemovesOrphan() async throws {
        let src = try TempDir.make(); let dst = try TempDir.make()
        defer { try? FileManager.default.removeItem(at: src); try? FileManager.default.removeItem(at: dst) }

        let media = src.appendingPathComponent("IMG_0007.jpg")
        try ImageFixture.writeJPEG(to: media, cameraModel: "X-T5", lensModel: "XF35mm", iso: 400)

        // Write a pre-existing source orphan sidecar beside the media file.
        try XMPTaggingService().writeExportSidecar(
            SidecarPayload(tagNames: ["Old"], capture: MetadataSnapshot(), iptc: IPTCMetadata()),
            besideDestinationFile: media
        )

        let set = PhotoSet(baseName: "IMG_0007", mediaFiles: [media], editPath: nil)
        let routed = RoutedPhoto(
            photoSet: set,
            metadata: MetadataReader().metadata(for: media),
            tags: [CustomTag(name: "Family", categoryID: UUID())]
        )

        let plan = RoutedPlan(
            operation: .moveOriginals,
            baseDestination: dst,
            rule: [],
            photos: [routed]
        )
        let summary = try await RoutedTransferService().execute(plan, categoryNameProvider: { _ in nil })

        #expect(summary.sidecarFailures == 0)

        let destSidecar = dst.appendingPathComponent("IMG_0007.xmp")
        #expect(FileManager.default.fileExists(atPath: destSidecar.path))
        let destContents = try String(contentsOf: destSidecar, encoding: .utf8)
        #expect(destContents.contains("<rdf:li>Family</rdf:li>"))

        #expect(!(FileManager.default.fileExists(atPath: media.path)))

        let srcOrphan = src.appendingPathComponent("IMG_0007.xmp")
        #expect(!(FileManager.default.fileExists(atPath: srcOrphan.path)))
    }

    // Finding 1: a camera model of ".." used to reach
    // `folder.appendingPathComponent(...)` unchanged and climb from
    // `base/<date>` to `<parentOfBase>/<date>`, landing the copy and its
    // sidecar beside an unrelated file one level above the chosen
    // destination. FilenameSanitizer now neutralizes it to "Unknown Camera",
    // so the copy must land under `base` and the sentinel planted at the
    // escape target must be left untouched.
    @Test
    func copyOriginals_cameraModelDotDot_writesUnderBaseAndLeavesParentAlone() async throws {
        let parent = try TempDir.make()
        defer { try? FileManager.default.removeItem(at: parent) }
        let base = parent.appendingPathComponent("Sorted", isDirectory: true)
        try FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)

        let src = try TempDir.make()
        defer { try? FileManager.default.removeItem(at: src) }
        let media = src.appendingPathComponent("IMG_0001.jpg")
        try ImageFixture.writeJPEG(to: media, cameraModel: "..", lensModel: "XF35mm", iso: 400)

        let metadata = MetadataReader().metadata(for: media)
        let dateFolderName: String
        if let date = metadata.captureDate {
            dateFolderName = ExportPathRouter.defaultDateFolderFormatter(date)
        } else {
            dateFolderName = "Unknown Date"
        }

        // Pre-create the folder an unsanitized ".." would have escaped to
        // (one level above `base`, i.e. inside `parent`) with a sentinel
        // .xmp already sitting there, mimicking the pre-existing file the
        // exploit would have overwritten.
        let escapeDir = parent.appendingPathComponent(dateFolderName, isDirectory: true)
        try FileManager.default.createDirectory(at: escapeDir, withIntermediateDirectories: true)
        let sentinel = escapeDir.appendingPathComponent("IMG_0001.xmp")
        let sentinelContents = "SENTINEL-DO-NOT-TOUCH"
        try sentinelContents.write(to: sentinel, atomically: true, encoding: .utf8)

        let set = PhotoSet(baseName: "IMG_0001", mediaFiles: [media], editPath: nil)
        let routed = RoutedPhoto(photoSet: set, metadata: metadata, tags: [])

        let plan = RoutedPlan(
            operation: .copyOriginals,
            baseDestination: base,
            rule: [.cameraModel, .captureDate],
            photos: [routed]
        )
        let summary = try await RoutedTransferService().execute(plan, categoryNameProvider: { _ in nil })
        #expect(summary.fileCount == 1)

        let expectedFolder = base
            .appendingPathComponent("Unknown Camera", isDirectory: true)
            .appendingPathComponent(dateFolderName, isDirectory: true)
        #expect(FileManager.default.fileExists(atPath: expectedFolder.appendingPathComponent("IMG_0001.jpg").path))
        #expect(FileManager.default.fileExists(atPath: expectedFolder.appendingPathComponent("IMG_0001.xmp").path))

        // Nothing new appeared beside the sentinel, and the sentinel itself
        // is untouched.
        #expect(!FileManager.default.fileExists(atPath: escapeDir.appendingPathComponent("IMG_0001.jpg").path))
        #expect(try String(contentsOf: sentinel, encoding: .utf8) == sentinelContents)
    }

    // Finding 1 / Finding 2: defense in depth. Even though the sanitizer
    // fixes above mean legitimate routing can no longer produce a folder
    // outside `base`, `RoutedTransferService.verifyContained` is the single
    // point that must hold regardless of what produced a routed folder, so
    // it is tested directly against URLs outside, equal to, and inside base.
    @Test
    func verifyContained_folderOutsideBase_throws() throws {
        let base = URL(fileURLWithPath: "/tmp/DuckSortTests-containment/dest", isDirectory: true)

        // Ancestor of base: escapes.
        do {
            try RoutedTransferService.verifyContained(
                [URL(fileURLWithPath: "/tmp/DuckSortTests-containment")], under: base
            )
            Issue.record("Expected TransferError.destinationEscapesBase to be thrown")
        } catch TransferError.destinationEscapesBase {
            // expected
        } catch {
            Issue.record("Expected destinationEscapesBase, got \(error)")
        }

        // Sibling directory whose name shares base's prefix as a string but
        // is not a descendant (e.g. "/x/dest" vs "/x/dest2"). A naive
        // `hasPrefix(basePath)` without the trailing "/" would wrongly allow
        // this.
        let sibling = base.deletingLastPathComponent().appendingPathComponent("dest2", isDirectory: true)
        do {
            try RoutedTransferService.verifyContained([sibling], under: base)
            Issue.record("Expected TransferError.destinationEscapesBase to be thrown")
        } catch TransferError.destinationEscapesBase {
            // expected
        } catch {
            Issue.record("Expected destinationEscapesBase, got \(error)")
        }

        // Equal to base and a descendant of base: both allowed.
        try RoutedTransferService.verifyContained([base], under: base)
        try RoutedTransferService.verifyContained([base.appendingPathComponent("Sub")], under: base)
    }
}
