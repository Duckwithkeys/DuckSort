import XCTest
@testable import DuckSort

final class SidecarWriteTests: XCTestCase {
    func test_writeExportSidecar_emitsKeywordsAndCapture() async throws {
        let dir = try TempDir.make()
        defer { try? FileManager.default.removeItem(at: dir) }
        let media = dir.appendingPathComponent("IMG_0001.RAF")

        let payload = SidecarPayload(
            tagNames: ["Ceremony", "Family"],
            capture: MetadataSnapshot(
                cameraModel: "X-T5", lensModel: "XF35mm",
                captureDate: nil, aperture: 2.8, shutterSpeed: 0.004, iso: 400
            )
        )

        let service = XMPTaggingService()
        try await service.writeExportSidecar(payload, besideDestinationFile: media)

        let sidecar = dir.appendingPathComponent("IMG_0001.xmp")
        let xml = try String(contentsOf: sidecar, encoding: .utf8)
        XCTAssertTrue(xml.contains("<rdf:li>Ceremony</rdf:li>"))
        XCTAssertTrue(xml.contains("<rdf:li>Family</rdf:li>"))
        XCTAssertTrue(xml.contains("tiff:Model=\"X-T5\""))
        XCTAssertTrue(xml.contains("exif:LensModel=\"XF35mm\""))
        XCTAssertTrue(xml.contains("exif:ISOSpeedRatings=\"400\""))
    }
}
