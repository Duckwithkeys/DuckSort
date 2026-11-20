import Foundation
import ImageIO
import Testing
@testable import DuckSort

@Suite("AuditRegressionTests")
struct AuditRegressionTests {

    @Test("mergeDescription updates and clears existing dc:description without NSRangeException")
    func mergeDescription_updatesAndClearsSafely() {
        let initial = """
        <?xpacket begin="" id="W5M0MpCehiHzreSzNTczkc9d"?>
        <x:xmpmeta xmlns:x="adobe:ns:meta/">
          <rdf:RDF xmlns:rdf="http://www.w3.org/1999/02/22-rdf-syntax-ns#">
            <rdf:Description rdf:about="" xmlns:dc="http://purl.org/dc/elements/1.1/">
              <dc:description>
                Original very long caption text that shrinks the string when removed
              </dc:description>
            </rdf:Description>
          </rdf:RDF>
        </x:xmpmeta>
        <?xpacket end="w"?>
        """

        let replaced = XMPTaggingService.mergeDescription("New short caption", into: initial)
        #expect(replaced.contains("New short caption"))
        #expect(!replaced.contains("Original very long caption"))

        let cleared = XMPTaggingService.mergeDescription(nil, into: replaced)
        #expect(!cleared.contains("<dc:description>"))
        #expect(!cleared.contains("New short caption"))
    }

    @Test("applyTagNames handles self-closing rdf:Description and special regex chars ($1, \\)")
    func applyTagNames_selfClosingAndSpecialChars() throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let mediaURL = tempDir.appendingPathComponent("IMG_0001.JPG")
        let xmpURL = tempDir.appendingPathComponent("IMG_0001.xmp")
        try Data([0xFF, 0xD8, 0xFF, 0xD9]).write(to: mediaURL)

        let selfClosingXMP = """
        <?xpacket begin="" id="W5M0MpCehiHzreSzNTczkc9d"?>
        <x:xmpmeta xmlns:x="adobe:ns:meta/">
          <rdf:RDF xmlns:rdf="http://www.w3.org/1999/02/22-rdf-syntax-ns#">
            <rdf:Description rdf:about="" xmlns:dc="http://purl.org/dc/elements/1.1/"/>
          </rdf:RDF>
        </x:xmpmeta>
        <?xpacket end="w"?>
        """
        try selfClosingXMP.write(to: xmpURL, atomically: true, encoding: .utf8)

        let photoSet = PhotoSet(baseName: "IMG_0001", mediaFiles: [mediaURL], editPath: nil)
        let service = XMPTaggingService()
        try service.applyTagNames(["Price $100", "Path\\Test"], to: photoSet)

        let written = try String(contentsOf: xmpURL, encoding: .utf8)
        #expect(!written.contains("<<rdf:Description"))
        #expect(written.contains("Price $100"))
        #expect(written.contains("Path\\Test"))
    }

    @Test("deterministicTagHash is stable and order-independent")
    func deterministicTagHash_isStable() {
        let h1 = XMPTaggingService.deterministicTagHash(["Portrait", "Wedding", "VIP"])
        let h2 = XMPTaggingService.deterministicTagHash(["VIP", "Portrait", "Wedding"])
        let h3 = XMPTaggingService.deterministicTagHash(["Portrait"])
        #expect(h1 == h2)
        #expect(h1 != h3)
        #expect(h1.count == 64)
    }

    @Test("EXIFSanitizer strips GPS dictionary from JPEG using kCFNull")
    func exifSanitizer_stripsGPS() throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let srcURL = tempDir.appendingPathComponent("with_gps.jpg")
        let dstURL = tempDir.appendingPathComponent("sanitized.jpg")

        // Create a 1x1 JPEG with GPS metadata attached.
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let ctx = CGContext(
            data: nil, width: 2, height: 2, bitsPerComponent: 8, bytesPerRow: 8,
            space: colorSpace, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
        )!
        let cgImage = ctx.makeImage()!
        let dest = CGImageDestinationCreateWithURL(srcURL as CFURL, "public.jpeg" as CFString, 1, nil)!
        let props: [CFString: Any] = [
            kCGImagePropertyGPSDictionary: [
                kCGImagePropertyGPSLatitude: 37.7749,
                kCGImagePropertyGPSLatitudeRef: "N",
                kCGImagePropertyGPSLongitude: 122.4194,
                kCGImagePropertyGPSLongitudeRef: "W"
            ]
        ]
        CGImageDestinationAddImage(dest, cgImage, props as CFDictionary)
        #expect(CGImageDestinationFinalize(dest))

        try EXIFSanitizer.sanitizeImage(at: srcURL, destinationURL: dstURL, stripLocation: true)

        let sanitizedSource = CGImageSourceCreateWithURL(dstURL as CFURL, nil)!
        let sanitizedProps = CGImageSourceCopyPropertiesAtIndex(sanitizedSource, 0, nil) as? [String: Any]
        #expect(sanitizedProps?[kCGImagePropertyGPSDictionary as String] == nil)
    }

    @Test("InsightsCalculator classifies fractional focal lengths and f/2.8 accurately")
    func insightsCalculator_bucketsAccurate() {
        let id1 = UUID()
        let id2 = UUID()
        let meta: [UUID: MetadataSnapshot] = [
            id1: MetadataSnapshot(aperture: 2.8, focalLength: 24.5),
            id2: MetadataSnapshot(aperture: 2.0, focalLength: 50.2)
        ]
        let report = InsightsCalculator.compute(photoMetadata: meta, photoSets: [], photoSetIndex: [:])

        let focalMap = Dictionary(uniqueKeysWithValues: report.focalLengthBuckets.map { ($0.label, $0.count) })
        #expect(focalMap["25–35mm"] == 1)
        #expect(focalMap["36–50mm"] == 1)
        #expect(focalMap["135mm+"] == 0)

        let apMap = Dictionary(uniqueKeysWithValues: report.apertureBuckets.map { ($0.label, $0.count) })
        #expect(apMap["f/2.8"] == 1)
        #expect(apMap["f/1.8–f/2"] == 1)
    }

    @Test("FolderTreeIndex does not match sibling directories sharing a path prefix")
    func folderTreeIndex_prefixBoundary() {
        let source = URL(fileURLWithPath: "/tmp/Photos")
        let sibling = URL(fileURLWithPath: "/tmp/Photos2/Sub")
        let child = URL(fileURLWithPath: "/tmp/Photos/Day1")

        let index = FolderTreeIndex.build(
            from: [sibling: [UUID()], child: [UUID()]],
            sourceDirectories: [source]
        )
        #expect(index.cachedSubfolders[source] == [child])
        #expect(FolderTreeIndex.relativePath(of: child, relativeTo: source) == "Day1")
        #expect(FolderTreeIndex.relativePath(of: sibling, relativeTo: source) == "Sub")
    }

    @Test("TagHotkeyRules allows modified shortcuts while reserving plain keys")
    func tagHotkeyRules_allowsModifiers() {
        #expect(TagHotkeyRules.reservedReason(for: "1") != nil)
        #expect(TagHotkeyRules.reservedReason(for: "s") != nil)
        #expect(TagHotkeyRules.reservedReason(for: "cmd+1") == nil)
        #expect(TagHotkeyRules.reservedReason(for: "opt+s") == nil)
    }

    @Test("FilenameSanitizer strips control characters")
    func filenameSanitizer_stripsControlChars() {
        let cleaned = FilenameSanitizer.clean("Canon\0EOS\u{07}R5")
        #expect(cleaned == "CanonEOSR5")
    }

    @Test("PhotoIndexStore removes stale rating and pick entries on re-index")
    func photoIndexStore_reIndexRemovesStaleBuckets() {
        let store = PhotoIndexStore()
        var photo = PhotoSet(baseName: "IMG_1", mediaFiles: [URL(fileURLWithPath: "/tmp/IMG_1.JPG")], editPath: nil)
        photo.rating = 5
        photo.pick = 1
        store.index(photo)
        #expect(store.photos(matchingRating: 5).count == 1)

        photo.rating = 3
        photo.pick = -1
        store.index(photo)
        #expect(store.photos(matchingRating: 5).isEmpty)
        #expect(store.photos(matchingRating: 3).count == 1)
    }

    @Test("CullingUndoManager ignores empty snapshots and supports clear")
    func cullingUndoManager_emptyAndClear() {
        var mgr = CullingUndoManager()
        mgr.registerUndo(beforeStates: [])
        #expect(!mgr.canUndo)

        mgr.registerUndo(beforeStates: [CullingState(photoSetID: UUID(), rating: 4, pick: 1, tagIDs: [])])
        #expect(mgr.canUndo)

        mgr.clear()
        #expect(!mgr.canUndo)
        #expect(!mgr.canRedo)
    }
}
