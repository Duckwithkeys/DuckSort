import Testing
import Foundation
@testable import DuckSort

@MainActor
struct CullingHistoryTests {

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

    @Test
    func undoRedo_ratingChange() {
        let (viewModel, photo1, _) = createTestContext()

        // Initially nil rating
        #expect(viewModel.photoSets[0].rating == nil)
        #expect(!(viewModel.canUndo))
        #expect(!(viewModel.canRedo))

        // Set rating
        viewModel.setRating(5, for: photo1.id)
        #expect(viewModel.photoSets[0].rating == 5)
        #expect(viewModel.canUndo)
        #expect(!(viewModel.canRedo))

        // Undo
        viewModel.undo()
        #expect(viewModel.photoSets[0].rating == nil)
        #expect(!(viewModel.canUndo))
        #expect(viewModel.canRedo)

        // Redo
        viewModel.redo()
        #expect(viewModel.photoSets[0].rating == 5)
        #expect(viewModel.canUndo)
        #expect(!(viewModel.canRedo))
    }

    @Test
    func undoRedo_pickFlagChange() {
        let (viewModel, _, photo2) = createTestContext()

        // Initially nil pick
        #expect(viewModel.photoSets[1].pick == nil)

        // Set pick to reject (-1)
        viewModel.setPick(-1, for: photo2.id)
        #expect(viewModel.photoSets[1].pick == -1)

        // Undo
        viewModel.undo()
        #expect(viewModel.photoSets[1].pick == nil)

        // Redo
        viewModel.redo()
        #expect(viewModel.photoSets[1].pick == -1)
    }

    @Test
    func undoRedo_tagChange() throws {
        let (viewModel, photo1, _) = createTestContext()
        let tag = try #require(viewModel.tagStore.tags.first, "TagStore tags list is empty")
        
        #expect(viewModel.tagStore.assignedTagIDs(for: photo1.id).isEmpty)

        // Apply tag
        viewModel.applyTag(tag, to: photo1.id)
        #expect(viewModel.tagStore.assignedTagIDs(for: photo1.id).contains(tag.id))

        // Undo
        viewModel.undo()
        #expect(!(viewModel.tagStore.assignedTagIDs(for: photo1.id).contains(tag.id)))

        // Redo
        viewModel.redo()
        #expect(viewModel.tagStore.assignedTagIDs(for: photo1.id).contains(tag.id))
    }

    @Test
    func historyStackDepthLimit() {
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
        #expect(undoCount == 150)
    }
}
