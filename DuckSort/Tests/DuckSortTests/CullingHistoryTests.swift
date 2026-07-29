import XCTest
@testable import DuckSort

@MainActor
final class CullingHistoryTests: XCTestCase {

    private func createTestContext() -> (PhotoLibraryViewModel, PhotoSet, PhotoSet) {
        let viewModel = PhotoLibraryViewModel()

        let photo1 = PhotoSet(
            id: UUID(),
            baseName: "IMG_0001",
            mediaFiles: [URL(fileURLWithPath: "IMG_0001.jpg")],
            editPath: nil
        )
        let photo2 = PhotoSet(
            id: UUID(),
            baseName: "IMG_0002",
            mediaFiles: [URL(fileURLWithPath: "IMG_0002.jpg")],
            editPath: nil
        )

        viewModel.photoSets = [photo1, photo2]
        return (viewModel, photo1, photo2)
    }

    func test_undoRedo_ratingChange() {
        let (viewModel, photo1, _) = createTestContext()

        // Initially nil rating
        XCTAssertNil(viewModel.photoSets[0].rating)
        XCTAssertFalse(viewModel.canUndo)
        XCTAssertFalse(viewModel.canRedo)

        // Set rating
        viewModel.setRating(5, for: photo1.id)
        XCTAssertEqual(viewModel.photoSets[0].rating, 5)
        XCTAssertTrue(viewModel.canUndo)
        XCTAssertFalse(viewModel.canRedo)

        // Undo
        viewModel.undo()
        XCTAssertNil(viewModel.photoSets[0].rating)
        XCTAssertFalse(viewModel.canUndo)
        XCTAssertTrue(viewModel.canRedo)

        // Redo
        viewModel.redo()
        XCTAssertEqual(viewModel.photoSets[0].rating, 5)
        XCTAssertTrue(viewModel.canUndo)
        XCTAssertFalse(viewModel.canRedo)
    }

    func test_undoRedo_pickFlagChange() {
        let (viewModel, _, photo2) = createTestContext()

        // Initially nil pick
        XCTAssertNil(viewModel.photoSets[1].pick)

        // Set pick to reject (-1)
        viewModel.setPick(-1, for: photo2.id)
        XCTAssertEqual(viewModel.photoSets[1].pick, -1)

        // Undo
        viewModel.undo()
        XCTAssertNil(viewModel.photoSets[1].pick)

        // Redo
        viewModel.redo()
        XCTAssertEqual(viewModel.photoSets[1].pick, -1)
    }

    func test_undoRedo_tagChange() {
        let (viewModel, photo1, _) = createTestContext()
        guard let tag = viewModel.tagStore.tags.first else {
            XCTFail("TagStore tags list is empty")
            return
        }
        
        XCTAssertTrue(viewModel.tagStore.assignedTagIDs(for: photo1.id).isEmpty)

        // Apply tag
        viewModel.applyTag(tag, to: photo1.id)
        XCTAssertTrue(viewModel.tagStore.assignedTagIDs(for: photo1.id).contains(tag.id))

        // Undo
        viewModel.undo()
        XCTAssertFalse(viewModel.tagStore.assignedTagIDs(for: photo1.id).contains(tag.id))

        // Redo
        viewModel.redo()
        XCTAssertTrue(viewModel.tagStore.assignedTagIDs(for: photo1.id).contains(tag.id))
    }

    func test_historyStackDepthLimit() {
        let (viewModel, photo1, _) = createTestContext()

        // Perform 200 rating changes
        for i in 1...200 {
            viewModel.setRating(i % 5 + 1, for: photo1.id)
        }

        // Verify undo stack limit works (it shouldn't exceed our cap of 150)
        var undoCount = 0
        while viewModel.canUndo {
            viewModel.undo()
            undoCount += 1
        }
        XCTAssertEqual(undoCount, 150, "Undo stack should be capped at 150 items")
    }
}
