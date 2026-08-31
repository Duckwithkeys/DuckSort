import Testing
import Foundation
import ImageIO
@testable import DuckSort

struct ImageFixtureTests {
    @Test
    func fixtureWritesReadableExif() throws {
        let dir = try TempDir.make()
        defer { try? FileManager.default.removeItem(at: dir) }
        let url = dir.appendingPathComponent("IMG_0001.jpg")
        try ImageFixture.writeJPEG(to: url, cameraModel: "X-T5", lensModel: "XF35mm", iso: 400)

        let snapshot = MetadataReader().metadata(for: url)
        #expect(snapshot.cameraModel == "X-T5")
        #expect(snapshot.iso == 400)
    }
}
