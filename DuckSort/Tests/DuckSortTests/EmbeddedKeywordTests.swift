import Testing
import Foundation
import ImageIO
import AppKit
@testable import DuckSort

struct EmbeddedKeywordTests {
    @Test
    func mergingKeywords_setsIptcKeywords() {
        let result = XMPTaggingService.mergingKeywords(["Family", "Ceremony"], into: [:])
        let iptc = result[kCGImagePropertyIPTCDictionary] as? [CFString: Any]
        let keywords = iptc?[kCGImagePropertyIPTCKeywords] as? [String]
        #expect(keywords == ["Ceremony", "Family"])
    }

    @Test
    func mergingKeywords_emptySetLeavesPropertiesUnchanged() {
        let original: [CFString: Any] = [kCGImagePropertyTIFFDictionary: ["k": "v"]]
        let result = XMPTaggingService.mergingKeywords([], into: original)
        #expect(result[kCGImagePropertyIPTCDictionary] == nil)
    }

    @Test
    func extractKeywords_fromDcSubjectXMP() {
        let xmp = """
        <x:xmpmeta xmlns:x="adobe:ns:meta/">
          <rdf:RDF xmlns:rdf="http://www.w3.org/1999/02/22-rdf-syntax-ns#">
            <rdf:Description xmlns:dc="http://purl.org/dc/elements/1.1/">
              <dc:subject>
                <rdf:Bag>
                  <rdf:li>Portrait</rdf:li>
                  <rdf:li>Outdoor &amp; Studio</rdf:li>
                  <rdf:li>Client &quot;A&quot;</rdf:li>
                </rdf:Bag>
              </dc:subject>
            </rdf:Description>
          </rdf:RDF>
        </x:xmpmeta>
        """
        let keywords = MetadataReader.extractKeywords(from: xmp)
        #expect(keywords.contains("Portrait"))
        #expect(keywords.contains("Outdoor & Studio"))
        #expect(keywords.contains("Client \"A\""))
    }

    @Test
    func extractKeywords_fromLrHierarchicalSubject() {
        let xmp = """
        <x:xmpmeta xmlns:x="adobe:ns:meta/">
          <rdf:RDF xmlns:rdf="http://www.w3.org/1999/02/22-rdf-syntax-ns#">
            <rdf:Description xmlns:lr="http://ns.adobe.com/lightroom/1.0/">
              <lr:hierarchicalSubject>
                <rdf:Bag>
                  <rdf:li>Location|France|Paris</rdf:li>
                  <rdf:li>Event|Wedding</rdf:li>
                </rdf:Bag>
              </lr:hierarchicalSubject>
            </rdf:Description>
          </rdf:RDF>
        </x:xmpmeta>
        """
        let keywords = MetadataReader.extractKeywords(from: xmp)
        #expect(keywords.contains("Location|France|Paris"))
        #expect(keywords.contains("Paris"))
        #expect(keywords.contains("Event|Wedding"))
        #expect(keywords.contains("Wedding"))
    }

    @Test
    func extractDescription_fromDcDescriptionXMP() {
        let xmp = """
        <x:xmpmeta xmlns:x="adobe:ns:meta/">
          <rdf:RDF xmlns:rdf="http://www.w3.org/1999/02/22-rdf-syntax-ns#">
            <rdf:Description xmlns:dc="http://purl.org/dc/elements/1.1/">
              <dc:description>
                <rdf:Alt>
                  <rdf:li xml:lang="x-default">Sunset over the mountains &amp; lake</rdf:li>
                </rdf:Alt>
              </dc:description>
            </rdf:Description>
          </rdf:RDF>
        </x:xmpmeta>
        """
        let caption = MetadataReader.extractDescription(from: xmp)
        #expect(caption == "Sunset over the mountains & lake")
    }

    @Test
    func metadataReader_readsEmbeddedIptcKeywordsFromImageFile() throws {
        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent("test_embedded_\(UUID().uuidString).jpg")
        defer { try? FileManager.default.removeItem(at: tempURL) }

        // Create a 10x10 dummy bitmap image
        let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: 10,
            pixelsHigh: 10,
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 40,
            bitsPerPixel: 32
        )!

        guard let destination = CGImageDestinationCreateWithURL(
            tempURL as CFURL,
            "public.jpeg" as CFString,
            1,
            nil
        ) else {
            Issue.record("Failed to create CGImageDestination")
            return
        }

        let properties: [CFString: Any] = [
            kCGImagePropertyIPTCDictionary: [
                kCGImagePropertyIPTCKeywords: ["Landscape", "Golden Hour"],
                kCGImagePropertyIPTCCaptionAbstract: "Beautiful scenery"
            ]
        ]

        CGImageDestinationAddImage(destination, rep.cgImage!, properties as CFDictionary)
        CGImageDestinationFinalize(destination)

        let reader = MetadataReader()
        let snapshot = reader.metadata(for: tempURL)

        #expect(snapshot.keywords.contains("Landscape"))
        #expect(snapshot.keywords.contains("Golden Hour"))
        #expect(snapshot.caption == "Beautiful scenery")
    }
}
