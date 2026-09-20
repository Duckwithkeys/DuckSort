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

        // This plan has exactly one job, and it is same-location, so the
        // "every job is same-location" rule (Finding 1) still throws here —
        // a single-file plan that would touch nothing is exactly the
        // "wrong destination" case the guard exists for.
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

        // Single-photo plan, so this is also the "every job is
        // same-location" case (Finding 1) — the guard still fires here.
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
        // the routed folder resolves onto its own directory. This is a
        // single-job plan, so "every job is same-location" (Finding 1)
        // still holds and the whole plan is refused rather than silently
        // no-op-ing. See `moveOriginals_mixedPlan_...` below for the case
        // where only *some* jobs are same-location.
        let plan = RoutedPlan(
            operation: .moveOriginals,
            baseDestination: dst,
            rule: [.camera],
            photos: [routed]
        )

        do {
            _ = try await RoutedTransferService().execute(plan, categoryNameProvider: { _ in nil })
        } catch TransferError.sameSourceAndDestination {
            // Expected
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

    // MARK: - Finding 1 / Finding 2: mixed plans

    @Test
    func moveOriginals_mixedPlan_movesOnlyTheFileNotAlreadyRouted() async throws {
        let src = try TempDir.make(); let dst = try TempDir.make()
        defer {
            try? FileManager.default.removeItem(at: src)
            try? FileManager.default.removeItem(at: dst)
        }
        let cameraDir = dst.appendingPathComponent("X-T5")
        try FileManager.default.createDirectory(at: cameraDir, withIntermediateDirectories: true)

        // Fixture A already lives exactly where the rule would route it —
        // one job in this plan is same-location.
        let alreadyRouted = cameraDir.appendingPathComponent("AlreadyRouted.jpg")
        try ImageFixture.writeJPEG(to: alreadyRouted, cameraModel: "X-T5", lensModel: "XF35mm", iso: 400)
        let alreadyRoutedBytes = try Data(contentsOf: alreadyRouted)

        // Fixture B has not been routed yet — its job is not same-location.
        let toMove = src.appendingPathComponent("ToMove.jpg")
        try ImageFixture.writeJPEG(to: toMove, cameraModel: "X-T5", lensModel: "XF35mm", iso: 400)
        let toMoveBytes = try Data(contentsOf: toMove)

        let routedA = RoutedPhoto(
            photoSet: PhotoSet(baseName: "AlreadyRouted", mediaFiles: [alreadyRouted], editPath: nil),
            metadata: MetadataReader().metadata(for: alreadyRouted),
            tags: []
        )
        let routedB = RoutedPhoto(
            photoSet: PhotoSet(baseName: "ToMove", mediaFiles: [toMove], editPath: nil),
            metadata: MetadataReader().metadata(for: toMove),
            tags: []
        )
        let plan = RoutedPlan(
            operation: .moveOriginals,
            baseDestination: dst,
            rule: [.camera],
            photos: [routedA, routedB]
        )

        // Not every job is same-location (only A's is), so the whole plan
        // must not be refused (Finding 1).
        let summary = try await RoutedTransferService().execute(plan, categoryNameProvider: { _ in nil })

        // A: left in place, untouched, byte-identical.
        #expect(FileManager.default.fileExists(atPath: alreadyRouted.path))
        #expect(try Data(contentsOf: alreadyRouted) == alreadyRoutedBytes)

        // B: moved into the routed folder; original gone.
        let movedB = cameraDir.appendingPathComponent("ToMove.jpg")
        #expect(!FileManager.default.fileExists(atPath: toMove.path))
        #expect(FileManager.default.fileExists(atPath: movedB.path))
        #expect(try Data(contentsOf: movedB) == toMoveBytes)

        // Finding 2: the left-in-place file is counted, not silently dropped.
        #expect(summary.filesLeftInPlace == 1)
        #expect(summary.fileCount == 2)
    }

    // MARK: - Finding 3: orphan sidecar survives a failed sidecar write

    @Test
    func moveOriginals_destinationSidecarWriteFails_keepsSourceOrphanSidecar() async throws {
        let src = try TempDir.make(); let dst = try TempDir.make()
        defer {
            try? FileManager.default.removeItem(at: src)
            try? FileManager.default.removeItem(at: dst)
        }

        let media = src.appendingPathComponent("IMG_0007.jpg")
        try ImageFixture.writeJPEG(to: media, cameraModel: "X-T5", lensModel: "XF35mm", iso: 400)

        // Pre-existing source orphan sidecar — this must survive if the
        // destination sidecar write fails, since deleting it would leave
        // zero copies of the tagging data anywhere.
        try XMPTaggingService().writeExportSidecar(
            SidecarPayload(tagNames: ["Family"], capture: MetadataSnapshot(), iptc: IPTCMetadata()),
            besideDestinationFile: media
        )
        let srcOrphan = src.appendingPathComponent("IMG_0007.xmp")
        let originalOrphanBytes = try Data(contentsOf: srcOrphan)

        // Force the destination sidecar write to fail without touching the
        // media copy: pre-create the destination's ".xmp" path as a
        // directory, so `writeExportSidecar`'s `String.write(to:...)` can't
        // replace it with a file. The JPEG copy uses a different path
        // (".jpg") and is unaffected.
        let destSidecarAsDirectory = dst.appendingPathComponent("IMG_0007.xmp")
        try FileManager.default.createDirectory(at: destSidecarAsDirectory, withIntermediateDirectories: true)

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

        #expect(summary.sidecarFailures == 1)

        // The media file still moves — sidecar failure doesn't block that.
        #expect(!FileManager.default.fileExists(atPath: media.path))
        #expect(FileManager.default.fileExists(atPath: dst.appendingPathComponent("IMG_0007.jpg").path))

        // The source orphan sidecar must survive: the destination write
        // failed, so there is no copy of the tagging data to replace it.
        #expect(FileManager.default.fileExists(atPath: srcOrphan.path))
        #expect(try Data(contentsOf: srcOrphan) == originalOrphanBytes)
    }
}
