import Testing
import Foundation
@testable import DuckSort

// Finding 3: Move Originals must never delete a source file that the
// routed transfer did not actually copy somewhere else. These tests drive
// `RoutedTransferService.execute` end to end against the real filesystem,
// following the shape of `RoutedSidecarTests`.
struct RoutedMoveSafetyTests {

    /// Recursively finds every regular file under `root` (excluding
    /// `excludedPath`) whose bytes match `bytes`. Used to prove a copy
    /// exists somewhere other than the source, without hard-coding the
    /// exact sanitized name a later fix (Task 2) will produce for it.
    private func filesWithIdenticalContent(
        to bytes: Data,
        under root: URL,
        excludingPath excludedPath: String
    ) -> [URL] {
        guard let enumerator = FileManager.default.enumerator(at: root, includingPropertiesForKeys: nil) else {
            return []
        }
        var matches: [URL] = []
        for case let url as URL in enumerator {
            var isDir: ObjCBool = false
            guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir), !isDir.boolValue else { continue }
            guard url.path != excludedPath else { continue }
            if let data = try? Data(contentsOf: url), data == bytes {
                matches.append(url)
            }
        }
        return matches
    }

    @Test
    func moveOriginals_baseEqualsSourceWithEmptyRule_throwsAndKeepsSource() async throws {
        let src = try TempDir.make()
        defer { try? FileManager.default.removeItem(at: src) }

        let media = src.appendingPathComponent("IMG.jpg")
        try ImageFixture.writeJPEG(to: media, cameraModel: "X-T5", lensModel: "XF35mm", iso: 400)
        try XMPTaggingService().writeExportSidecar(
            SidecarPayload(tagNames: ["Family"], capture: MetadataSnapshot(), iptc: IPTCMetadata()),
            besideDestinationFile: media
        )
        let originalBytes = try Data(contentsOf: media)
        let xmp = src.appendingPathComponent("IMG.xmp")
        #expect(FileManager.default.fileExists(atPath: xmp.path))

        let set = PhotoSet(baseName: "IMG", mediaFiles: [media], editPath: nil)
        let routed = RoutedPhoto(
            photoSet: set,
            metadata: MetadataReader().metadata(for: media),
            tags: []
        )
        let plan = RoutedPlan(
            operation: .moveOriginals,
            baseDestination: src,
            rule: [],
            photos: [routed]
        )

        do {
            _ = try await RoutedTransferService().execute(plan, categoryNameProvider: { _ in nil })
            Issue.record("Expected TransferError.sameSourceAndDestination to be thrown")
        } catch TransferError.sameSourceAndDestination {
            // expected
        } catch {
            Issue.record("Expected sameSourceAndDestination, got \(error)")
        }

        #expect(FileManager.default.fileExists(atPath: media.path))
        #expect(try Data(contentsOf: media) == originalBytes)
        #expect(FileManager.default.fileExists(atPath: xmp.path))
    }

    @Test
    func moveOriginals_cameraModelDotDot_doesNotDeleteSource() async throws {
        let src = try TempDir.make()
        defer { try? FileManager.default.removeItem(at: src) }
        let sortedDir = src.appendingPathComponent("Sorted")
        try FileManager.default.createDirectory(at: sortedDir, withIntermediateDirectories: true)

        // EXIF Model ".." makes the camera-first rule route the file back
        // onto `Sorted/..`, which lexically resolves to `src` — the file's
        // own directory.
        let media = src.appendingPathComponent("IMG.jpg")
        try ImageFixture.writeJPEG(to: media, cameraModel: "..", lensModel: "XF35mm", iso: 400)
        let originalBytes = try Data(contentsOf: media)

        let set = PhotoSet(baseName: "IMG", mediaFiles: [media], editPath: nil)
        let routed = RoutedPhoto(
            photoSet: set,
            metadata: MetadataReader().metadata(for: media),
            tags: []
        )
        let plan = RoutedPlan(
            operation: .moveOriginals,
            baseDestination: sortedDir,
            rule: [.camera],
            photos: [routed]
        )

        var thrown: Error?
        do {
            _ = try await RoutedTransferService().execute(plan, categoryNameProvider: { _ in nil })
        } catch {
            thrown = error
        }

        // The source must survive no matter what: either the operation
        // throws (this task's fix), or — after Task 2 sanitizes ".." in
        // routed path components — it succeeds and produces a copy at a
        // different path. Either outcome is safe as long as the only
        // existing copy of the file is never destroyed.
        #expect(FileManager.default.fileExists(atPath: media.path))
        #expect(try Data(contentsOf: media) == originalBytes)

        if thrown == nil {
            let copies = filesWithIdenticalContent(to: originalBytes, under: src, excludingPath: media.path)
            #expect(!copies.isEmpty, "Expected a copy to exist somewhere other than the source when execute did not throw")
        }
    }

    @Test
    func moveOriginals_alreadyRoutedFile_isNotDeleted() async throws {
        let dst = try TempDir.make()
        defer { try? FileManager.default.removeItem(at: dst) }
        let cameraDir = dst.appendingPathComponent("X-T5")
        try FileManager.default.createDirectory(at: cameraDir, withIntermediateDirectories: true)

        let media = cameraDir.appendingPathComponent("IMG.jpg")
        try ImageFixture.writeJPEG(to: media, cameraModel: "X-T5", lensModel: "XF35mm", iso: 400)
        let originalBytes = try Data(contentsOf: media)

        let set = PhotoSet(baseName: "IMG", mediaFiles: [media], editPath: nil)
        let routed = RoutedPhoto(
            photoSet: set,
            metadata: MetadataReader().metadata(for: media),
            tags: []
        )
        // The file already lives exactly where the rule would route it, so
        // the routed folder resolves onto its own directory.
        let plan = RoutedPlan(
            operation: .moveOriginals,
            baseDestination: dst,
            rule: [.camera],
            photos: [routed]
        )

        do {
            _ = try await RoutedTransferService().execute(plan, categoryNameProvider: { _ in nil })
        } catch TransferError.sameSourceAndDestination {
            // Expected: destination collapses onto the source, so the
            // whole plan is refused rather than silently no-op-ing.
        } catch {
            Issue.record("Expected sameSourceAndDestination, got \(error)")
        }

        #expect(FileManager.default.fileExists(atPath: media.path))
        #expect(try Data(contentsOf: media) == originalBytes)
    }

    @Test
    func copyOriginals_sameLocation_doesNotDeleteOrCorrupt() async throws {
        let dst = try TempDir.make()
        defer { try? FileManager.default.removeItem(at: dst) }
        let cameraDir = dst.appendingPathComponent("X-T5")
        try FileManager.default.createDirectory(at: cameraDir, withIntermediateDirectories: true)

        let media = cameraDir.appendingPathComponent("IMG.jpg")
        try ImageFixture.writeJPEG(to: media, cameraModel: "X-T5", lensModel: "XF35mm", iso: 400)
        let originalBytes = try Data(contentsOf: media)

        let set = PhotoSet(baseName: "IMG", mediaFiles: [media], editPath: nil)
        let routed = RoutedPhoto(
            photoSet: set,
            metadata: MetadataReader().metadata(for: media),
            tags: []
        )
        let plan = RoutedPlan(
            operation: .copyOriginals,
            baseDestination: dst,
            rule: [.camera],
            photos: [routed]
        )

        do {
            _ = try await RoutedTransferService().execute(plan, categoryNameProvider: { _ in nil })
            Issue.record("Expected TransferError.sameSourceAndDestination to be thrown")
        } catch TransferError.sameSourceAndDestination {
            // expected: same-location is an error for both operations
        } catch {
            Issue.record("Expected sameSourceAndDestination, got \(error)")
        }

        #expect(FileManager.default.fileExists(atPath: media.path))
        #expect(try Data(contentsOf: media) == originalBytes)
    }
}
