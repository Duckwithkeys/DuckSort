import Testing
import Foundation
@testable import DuckSort

// Review item 1: `verifyContained` compares standardized paths lexically,
// which never resolves symlinks. `resolvingSymlinksInPath()` only resolves
// path segments that already exist, so a pre-creation check cannot catch a
// symlink planted inside the destination before phase 5 creates the routed
// directories. These tests drive `RoutedTransferService.execute` end to end
// against a real symlink to confirm the post-creation resolved check closes
// that gap.
struct RoutedContainmentTests {
    private func makeRoutedPlan(
        operation: RoutedOperation,
        base: URL,
        media: URL
    ) throws -> RoutedPlan {
        let set = PhotoSet(baseName: media.deletingPathExtension().lastPathComponent, mediaFiles: [media], editPath: nil)
        let routed = RoutedPhoto(
            photoSet: set,
            metadata: MetadataReader().metadata(for: media),
            tags: []
        )
        return RoutedPlan(operation: operation, baseDestination: base, rule: [.camera], photos: [routed])
    }

    private func assertEscapeRefused(operation: RoutedOperation) async throws {
        let base = try TempDir.make()
        let outsideTarget = try TempDir.make()
        let src = try TempDir.make()
        defer {
            try? FileManager.default.removeItem(at: base)
            try? FileManager.default.removeItem(at: outsideTarget)
            try? FileManager.default.removeItem(at: src)
        }

        // The attacker controls the camera model via EXIF, so they can plant
        // a symlink inside the destination whose name matches whatever
        // component the router will produce, then wait for the user to run
        // the transfer.
        let link = base.appendingPathComponent("X-T5")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: outsideTarget)

        let media = src.appendingPathComponent("IMG_0001.jpg")
        try ImageFixture.writeJPEG(to: media, cameraModel: "X-T5", lensModel: "XF35mm", iso: 400)
        let originalBytes = try Data(contentsOf: media)

        let plan = try makeRoutedPlan(operation: operation, base: base, media: media)

        do {
            _ = try await RoutedTransferService().execute(plan, categoryNameProvider: { _ in nil })
            Issue.record("Expected TransferError.destinationEscapesBase to be thrown")
        } catch TransferError.destinationEscapesBase {
            // expected
        } catch {
            Issue.record("Expected destinationEscapesBase, got \(error)")
        }

        let outsideFile = outsideTarget.appendingPathComponent("IMG_0001.jpg")
        #expect(!FileManager.default.fileExists(atPath: outsideFile.path))
        #expect(FileManager.default.fileExists(atPath: media.path))
        #expect(try Data(contentsOf: media) == originalBytes)
    }

    @Test
    func copyOriginals_symlinkedRoutedFolder_refusesAndLeavesOutsideUntouched() async throws {
        try await assertEscapeRefused(operation: .copyOriginals)
    }

    @Test
    func moveOriginals_symlinkedRoutedFolder_refusesAndLeavesSourceUntouched() async throws {
        try await assertEscapeRefused(operation: .moveOriginals)
    }

    // Positive control: a base destination reached only through a symlink
    // (not one containing a planted symlink) must still work, with files
    // landing under the real directory the link points at. Both sides of
    // the resolved containment check must resolve the same way, or this
    // would start throwing `destinationEscapesBase` for every user whose
    // destination lives under a symlinked path (macOS `/tmp` and `/var`
    // are themselves symlinks).
    @Test
    func copyOriginals_baseReachedThroughSymlink_stillLandsUnderRealBase() async throws {
        let realBase = try TempDir.make()
        let linkContainer = try TempDir.make()
        let src = try TempDir.make()
        defer {
            try? FileManager.default.removeItem(at: realBase)
            try? FileManager.default.removeItem(at: linkContainer)
            try? FileManager.default.removeItem(at: src)
        }

        let link = linkContainer.appendingPathComponent("link")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: realBase)

        let media = src.appendingPathComponent("IMG_0001.jpg")
        try ImageFixture.writeJPEG(to: media, cameraModel: "X-T5", lensModel: "XF35mm", iso: 400)
        let originalBytes = try Data(contentsOf: media)

        let plan = try makeRoutedPlan(operation: .copyOriginals, base: link, media: media)
        let summary = try await RoutedTransferService().execute(plan, categoryNameProvider: { _ in nil })

        #expect(summary.fileCount == 1)
        let expected = realBase.appendingPathComponent("X-T5").appendingPathComponent("IMG_0001.jpg")
        #expect(FileManager.default.fileExists(atPath: expected.path))
        #expect(try Data(contentsOf: expected) == originalBytes)
    }

    // Review item 5: `base == "/"` used to make every folder appear to
    // escape, because "/" + "/" is "//" and no real path starts with that.
    @Test
    func verifyContained_baseIsRoot_descendantAndBaseItselfAreContained() throws {
        let base = URL(fileURLWithPath: "/", isDirectory: true)
        try RoutedTransferService.verifyContained([base], under: base)
        try RoutedTransferService.verifyContained([URL(fileURLWithPath: "/tmp", isDirectory: true)], under: base)
    }
}
