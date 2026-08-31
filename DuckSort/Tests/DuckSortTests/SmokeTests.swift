import Testing
import Foundation
@testable import DuckSort

struct SmokeTests {
    @Test
    func metadataSnapshot_defaultsAreNil() {
        let snapshot = MetadataSnapshot()
        #expect(snapshot.cameraModel == nil)
        #expect(snapshot.captureDate == nil)
    }

    @Test
    func photoFilterRule_matchesCorrectly() {
        let setWithEdit = PhotoSet(id: UUID(), baseName: "photo1", mediaFiles: [URL(fileURLWithPath: "photo1.jpg")], editPath: URL(fileURLWithPath: "photo1.photo-edit"))
        let setWithoutEdit = PhotoSet(id: UUID(), baseName: "photo2", mediaFiles: [URL(fileURLWithPath: "photo2.jpg")], editPath: nil)
        
        #expect(PhotoFilterRule.allPhotos.matches(setWithEdit))
        #expect(PhotoFilterRule.allPhotos.matches(setWithoutEdit))
        
        #expect(PhotoFilterRule.editedOnly.matches(setWithEdit))
        #expect(!(PhotoFilterRule.editedOnly.matches(setWithoutEdit)))
        
        #expect(!(PhotoFilterRule.uneditedOnly.matches(setWithEdit)))
        #expect(PhotoFilterRule.uneditedOnly.matches(setWithoutEdit))
    }
}
