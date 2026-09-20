import Testing
import Foundation
@testable import DuckSort

struct SidecarWriteTests {
    @Test
    func writeExportSidecar_emitsKeywordsAndCapture() async throws {
        let dir = try TempDir.make()
        defer { try? FileManager.default.removeItem(at: dir) }
        let media = dir.appendingPathComponent("IMG_0001.RAF")

        let payload = SidecarPayload(
            tagNames: ["Ceremony", "Family"],
            capture: MetadataSnapshot(
                cameraModel: "X-T5", lensModel: "XF35mm",
                captureDate: nil, aperture: 2.8, shutterSpeed: 0.004, iso: 400
            ),
            iptc: IPTCMetadata()
        )

        let service = XMPTaggingService()
        try service.writeExportSidecar(payload, besideDestinationFile: media)

        let sidecar = dir.appendingPathComponent("IMG_0001.xmp")
        let xml = try String(contentsOf: sidecar, encoding: .utf8)
        #expect(xml.contains("<rdf:li>Ceremony</rdf:li>"))
        #expect(xml.contains("<rdf:li>Family</rdf:li>"))
        #expect(xml.contains("tiff:Model=\"X-T5\""))
        #expect(xml.contains("exif:LensModel=\"XF35mm\""))
        #expect(xml.contains("exif:ISOSpeedRatings=\"400\""))
    }

    @Test
    func writeExportSidecar_escapesQuoteInAttributeValue() async throws {
        let dir = try TempDir.make()
        defer { try? FileManager.default.removeItem(at: dir) }
        let media = dir.appendingPathComponent("IMG_0002.RAF")
        let payload = SidecarPayload(
            tagNames: [],
            capture: MetadataSnapshot(cameraModel: "Cam \"Pro\"", lensModel: nil,
                                      captureDate: nil, aperture: nil, shutterSpeed: nil, iso: nil),
            iptc: IPTCMetadata()
        )
        try XMPTaggingService().writeExportSidecar(payload, besideDestinationFile: media)
        let xml = try String(contentsOf: dir.appendingPathComponent("IMG_0002.xmp"), encoding: .utf8)
        #expect(xml.contains("tiff:Model=\"Cam &quot;Pro&quot;\""))
        #expect(!(xml.contains("\"Pro\"")))
    }

    @Test
    func writeExportSidecar_mergesIntoExistingSidecar() async throws {
        let dir = try TempDir.make()
        defer { try? FileManager.default.removeItem(at: dir) }
        
        let sourceSidecar = dir.appendingPathComponent("IMG_0003.xmp")
        
        let initialXMP = """
        <x:xmpmeta xmlns:x="adobe:ns:meta/" x:xmptk="XMP Core 6.0.0">
          <rdf:RDF xmlns:rdf="http://www.w3.org/1999/02/22-rdf-syntax-ns#">
            <rdf:Description rdf:about=""
                xmlns:xmp="http://ns.adobe.com/xap/1.0/"
                xmlns:dc="http://purl.org/dc/elements/1.1/"
                xmlns:customNs="http://example.com/custom/"
                xmp:Rating="4"
                customNs:CustomProp="KeepMe">
              <dc:subject>
                <rdf:Bag>
                  <rdf:li>InitialTag</rdf:li>
                </rdf:Bag>
              </dc:subject>
            </rdf:Description>
          </rdf:RDF>
        </x:xmpmeta>
        """
        try initialXMP.write(to: sourceSidecar, atomically: true, encoding: .utf8)
        
        let destMedia = dir.appendingPathComponent("IMG_0003_dest.RAF")
        let payload = SidecarPayload(
            tagNames: ["NewTag"],
            capture: MetadataSnapshot(
                cameraModel: "X-T5", lensModel: "XF35mm",
                captureDate: nil, aperture: 2.8, shutterSpeed: 0.004, iso: 400, rating: 5
            ),
            iptc: IPTCMetadata()
        )
        
        let service = XMPTaggingService()
        try service.writeExportSidecar(payload, besideDestinationFile: destMedia, mergingSourceSidecar: sourceSidecar)
        
        let destSidecar = dir.appendingPathComponent("IMG_0003_dest.xmp")
        let mergedXML = try String(contentsOf: destSidecar, encoding: .utf8)
        
        #expect(mergedXML.contains("customNs:CustomProp=\"KeepMe\""))
        #expect(mergedXML.contains("xmp:Rating=\"5\""))
        #expect(mergedXML.contains("tiff:Model=\"X-T5\""))
        #expect(mergedXML.contains("exif:LensModel=\"XF35mm\""))
        #expect(mergedXML.contains("<rdf:li>NewTag</rdf:li>"))
    }

    // MARK: - Symlinked sidecar refusal (Finding 4)

    private struct SymlinkFixture {
        let dir: URL
        let outside: URL
        let photoSet: PhotoSet
        let sidecar: URL
        let secret: URL
        let secretContents: String
    }

    /// `IMG.jpg` (real fixture) beside `IMG.xmp -> outside/secret.txt`, a
    /// UTF-8 text file outside the photo folder. Mirrors the exploit: an
    /// attacker-planted sidecar symlink pointing at a file the victim cares
    /// about (an SSH key, credentials, etc).
    private func makeSymlinkFixture() throws -> SymlinkFixture {
        let dir = try TempDir.make()
        let outside = try TempDir.make()
        let media = dir.appendingPathComponent("IMG.jpg")
        try ImageFixture.writeJPEG(to: media, cameraModel: "X-T5", lensModel: "XF35mm", iso: 400)

        let secret = outside.appendingPathComponent("secret.txt")
        let secretContents = "SECRET-KEY-DATA-\(UUID().uuidString)"
        try secretContents.write(to: secret, atomically: true, encoding: .utf8)

        let sidecar = dir.appendingPathComponent("IMG.xmp")
        try FileManager.default.createSymbolicLink(at: sidecar, withDestinationURL: secret)

        let photoSet = PhotoSet(baseName: "IMG", mediaFiles: [media], editPath: nil)
        return SymlinkFixture(dir: dir, outside: outside, photoSet: photoSet, sidecar: sidecar, secret: secret, secretContents: secretContents)
    }

    private func cleanup(_ fixture: SymlinkFixture) {
        try? FileManager.default.removeItem(at: fixture.dir)
        try? FileManager.default.removeItem(at: fixture.outside)
    }

    /// Asserts the symlink at `sidecar` was neither followed nor replaced:
    /// still a symlink, and the file it points at still holds its original
    /// bytes.
    private func assertSymlinkAndTargetUntouched(_ fixture: SymlinkFixture) throws {
        let type = try FileManager.default.attributesOfItem(atPath: fixture.sidecar.path)[.type] as? FileAttributeType
        #expect(type == .typeSymbolicLink)
        #expect(try String(contentsOf: fixture.secret, encoding: .utf8) == fixture.secretContents)
    }

    @Test
    func symlinkSidecar_updatePermanentTags_throwsAndLeavesLinkAndTargetUntouched() async throws {
        let fixture = try makeSymlinkFixture()
        defer { cleanup(fixture) }
        let service = XMPTaggingService()

        do {
            try service.updatePermanentTags(rating: 5, pick: nil, for: fixture.photoSet)
            Issue.record("Expected SidecarError.notRegularFile to be thrown")
        } catch SidecarError.notRegularFile {
            // expected
        } catch {
            Issue.record("Expected SidecarError.notRegularFile, got \(error)")
        }

        try assertSymlinkAndTargetUntouched(fixture)
    }

    @Test
    func symlinkSidecar_updateCaptionSet_throwsAndLeavesLinkAndTargetUntouched() async throws {
        let fixture = try makeSymlinkFixture()
        defer { cleanup(fixture) }
        let service = XMPTaggingService()

        do {
            try service.updateCaption("Golden hour", for: fixture.photoSet)
            Issue.record("Expected SidecarError.notRegularFile to be thrown")
        } catch SidecarError.notRegularFile {
            // expected
        } catch {
            Issue.record("Expected SidecarError.notRegularFile, got \(error)")
        }

        try assertSymlinkAndTargetUntouched(fixture)
    }

    @Test
    func symlinkSidecar_updateCaptionClear_throwsAndLeavesLinkAndTargetUntouched() async throws {
        let fixture = try makeSymlinkFixture()
        defer { cleanup(fixture) }
        let service = XMPTaggingService()

        do {
            try service.updateCaption(nil, for: fixture.photoSet)
            Issue.record("Expected SidecarError.notRegularFile to be thrown")
        } catch SidecarError.notRegularFile {
            // expected
        } catch {
            Issue.record("Expected SidecarError.notRegularFile, got \(error)")
        }

        try assertSymlinkAndTargetUntouched(fixture)
    }

    @Test
    func symlinkSidecar_applyTagNames_throwsAndLeavesLinkAndTargetUntouched() async throws {
        let fixture = try makeSymlinkFixture()
        defer { cleanup(fixture) }
        let service = XMPTaggingService()

        do {
            try service.applyTagNames(["Family"], to: fixture.photoSet)
            Issue.record("Expected SidecarError.notRegularFile to be thrown")
        } catch SidecarError.notRegularFile {
            // expected
        } catch {
            Issue.record("Expected SidecarError.notRegularFile, got \(error)")
        }

        try assertSymlinkAndTargetUntouched(fixture)
    }

    @Test
    func symlinkSidecar_clear_throwsAndLeavesLinkAndTargetUntouched() async throws {
        let fixture = try makeSymlinkFixture()
        defer { cleanup(fixture) }
        let service = XMPTaggingService()

        do {
            try service.clear(for: fixture.photoSet)
            Issue.record("Expected SidecarError.notRegularFile to be thrown")
        } catch SidecarError.notRegularFile {
            // expected
        } catch {
            Issue.record("Expected SidecarError.notRegularFile, got \(error)")
        }

        try assertSymlinkAndTargetUntouched(fixture)
    }

    @Test
    func regularSidecar_roundTripsRatingPickCaptionAndTags() async throws {
        let dir = try TempDir.make()
        defer { try? FileManager.default.removeItem(at: dir) }
        let media = dir.appendingPathComponent("IMG.jpg")
        try ImageFixture.writeJPEG(to: media, cameraModel: "X-T5", lensModel: "XF35mm", iso: 400)
        let set = PhotoSet(baseName: "IMG", mediaFiles: [media], editPath: nil)
        let service = XMPTaggingService()

        try service.applyTagNames(["Family", "Ceremony"], to: set)
        try service.updatePermanentTags(rating: 4, pick: 1, for: set)
        try service.updateCaption("Golden hour", for: set)

        let data = service.readSidecarData(from: set)
        #expect(data.tags == ["Family", "Ceremony"])
        #expect(data.rating == 4)
        #expect(data.pick == 1)
        #expect(data.description == "Golden hour")

        let sidecar = dir.appendingPathComponent("IMG.xmp")
        let type = try FileManager.default.attributesOfItem(atPath: sidecar.path)[.type] as? FileAttributeType
        #expect(type == .typeRegular)

        // updatePermanentTags used to hand-roll the xmp:Rating / xmpDM:pick
        // attribute upsert without declaring their namespaces, unlike every
        // other attribute writer which goes through mergeAttributes. Both
        // namespaces must be present for a reader that cares about them.
        let xml = try String(contentsOf: sidecar, encoding: .utf8)
        #expect(xml.contains("xmlns:xmp=\"http://ns.adobe.com/xap/1.0/\""))
        #expect(xml.contains("xmlns:xmpDM=\"http://ns.adobe.com/xmp/1.0/DynamicMedia/\""))
    }

    // Review item 4: `looksLikeXMP` passes on a lone `<x:xmpmeta` marker
    // even with no `<rdf:Description>` tag to attach an attribute to.
    // `mergeAttributes` silently hands such content back unchanged in that
    // case; `updateSidecarRatingPick` must throw instead of pretending the
    // write happened.
    @Test
    func updatePermanentTags_looksLikeXMPButNoDescriptionTag_throwsNotXMPAndLeavesBytesUnchanged() async throws {
        let dir = try TempDir.make()
        defer { try? FileManager.default.removeItem(at: dir) }
        let media = dir.appendingPathComponent("IMG.jpg")
        try ImageFixture.writeJPEG(to: media, cameraModel: "X-T5", lensModel: "XF35mm", iso: 400)
        let sidecar = dir.appendingPathComponent("IMG.xmp")
        let content = "<x:xmpmeta xmlns:x=\"adobe:ns:meta/\">not really XMP, no Description tag</x:xmpmeta>"
        try content.write(to: sidecar, atomically: true, encoding: .utf8)

        let set = PhotoSet(baseName: "IMG", mediaFiles: [media], editPath: nil)
        let service = XMPTaggingService()

        do {
            try service.updatePermanentTags(rating: 5, pick: nil, for: set)
            Issue.record("Expected SidecarError.notXMP to be thrown")
        } catch SidecarError.notXMP {
            // expected
        } catch {
            Issue.record("Expected SidecarError.notXMP, got \(error)")
        }

        #expect(try String(contentsOf: sidecar, encoding: .utf8) == content)
    }

    // Review item 6: `writeSidecar` (backing `applyTagNames` and `clear`)
    // used to overwrite a regular non-XMP `.xmp` with a fresh packet, or
    // delete it outright when clearing tags. Align with the rating/caption
    // paths: refuse instead of touching content that doesn't look like XMP.
    @Test
    func regularNonXMPSidecar_applyTagNames_throwsNotXMPAndLeavesBytesUnchanged() async throws {
        let dir = try TempDir.make()
        defer { try? FileManager.default.removeItem(at: dir) }
        let media = dir.appendingPathComponent("IMG.jpg")
        try ImageFixture.writeJPEG(to: media, cameraModel: "X-T5", lensModel: "XF35mm", iso: 400)
        let sidecar = dir.appendingPathComponent("IMG.xmp")
        let plainText = "just some notes, not XMP at all"
        try plainText.write(to: sidecar, atomically: true, encoding: .utf8)

        let set = PhotoSet(baseName: "IMG", mediaFiles: [media], editPath: nil)
        let service = XMPTaggingService()

        do {
            try service.applyTagNames(["Family"], to: set)
            Issue.record("Expected SidecarError.notXMP to be thrown")
        } catch SidecarError.notXMP {
            // expected
        } catch {
            Issue.record("Expected SidecarError.notXMP, got \(error)")
        }

        #expect(try String(contentsOf: sidecar, encoding: .utf8) == plainText)
    }

    @Test
    func regularNonXMPSidecar_clear_throwsNotXMPAndLeavesBytesUnchanged() async throws {
        let dir = try TempDir.make()
        defer { try? FileManager.default.removeItem(at: dir) }
        let media = dir.appendingPathComponent("IMG.jpg")
        try ImageFixture.writeJPEG(to: media, cameraModel: "X-T5", lensModel: "XF35mm", iso: 400)
        let sidecar = dir.appendingPathComponent("IMG.xmp")
        let plainText = "just some notes, not XMP at all"
        try plainText.write(to: sidecar, atomically: true, encoding: .utf8)

        let set = PhotoSet(baseName: "IMG", mediaFiles: [media], editPath: nil)
        let service = XMPTaggingService()

        do {
            try service.clear(for: set)
            Issue.record("Expected SidecarError.notXMP to be thrown")
        } catch SidecarError.notXMP {
            // expected
        } catch {
            Issue.record("Expected SidecarError.notXMP, got \(error)")
        }

        #expect(FileManager.default.fileExists(atPath: sidecar.path))
        #expect(try String(contentsOf: sidecar, encoding: .utf8) == plainText)
    }

    @Test
    func regularNonXMPSidecar_updatePermanentTags_throwsNotXMPAndLeavesBytesUnchanged() async throws {
        let dir = try TempDir.make()
        defer { try? FileManager.default.removeItem(at: dir) }
        let media = dir.appendingPathComponent("IMG.jpg")
        try ImageFixture.writeJPEG(to: media, cameraModel: "X-T5", lensModel: "XF35mm", iso: 400)
        let sidecar = dir.appendingPathComponent("IMG.xmp")
        let plainText = "just some notes, not XMP at all"
        try plainText.write(to: sidecar, atomically: true, encoding: .utf8)

        let set = PhotoSet(baseName: "IMG", mediaFiles: [media], editPath: nil)
        let service = XMPTaggingService()

        do {
            try service.updatePermanentTags(rating: 5, pick: nil, for: set)
            Issue.record("Expected SidecarError.notXMP to be thrown")
        } catch SidecarError.notXMP {
            // expected
        } catch {
            Issue.record("Expected SidecarError.notXMP, got \(error)")
        }

        #expect(try String(contentsOf: sidecar, encoding: .utf8) == plainText)
    }
}
