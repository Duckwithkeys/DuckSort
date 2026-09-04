import Testing
import Foundation
@testable import DuckSort

@MainActor
struct PhotoSortingTests {
    @Test
    func sortByName_ascendingAndDescending() {
        let vm = PhotoLibraryViewModel()
        let setA = PhotoSet(baseName: "Alpha", mediaFiles: [], editPath: nil)
        let setB = PhotoSet(baseName: "Bravo", mediaFiles: [], editPath: nil)
        let setC = PhotoSet(baseName: "Charlie", mediaFiles: [], editPath: nil)

        vm.photoSets = [setB, setC, setA]
        vm.sortOrder = .name
        vm.sortDirection = .ascending
        vm.updateDerivedState()

        #expect(vm.filteredPhotoSets.map(\.baseName) == ["Alpha", "Bravo", "Charlie"])

        vm.sortDirection = .descending
        vm.updateDerivedState()

        #expect(vm.filteredPhotoSets.map(\.baseName) == ["Charlie", "Bravo", "Alpha"])
    }

    @Test
    func sortByDate_ascendingAndDescending() {
        let vm = PhotoLibraryViewModel()
        let set1 = PhotoSet(baseName: "Photo1", mediaFiles: [], editPath: nil)
        let set2 = PhotoSet(baseName: "Photo2", mediaFiles: [], editPath: nil)
        let set3 = PhotoSet(baseName: "Photo3", mediaFiles: [], editPath: nil)

        let date1 = Date(timeIntervalSince1970: 1000)
        let date2 = Date(timeIntervalSince1970: 2000)
        let date3 = Date(timeIntervalSince1970: 3000)

        vm.photoSets = [set2, set1, set3]
        vm.setPhotoMetadata(for: set1.id, metadata: MetadataSnapshot(captureDate: date1))
        vm.setPhotoMetadata(for: set2.id, metadata: MetadataSnapshot(captureDate: date2))
        vm.setPhotoMetadata(for: set3.id, metadata: MetadataSnapshot(captureDate: date3))

        vm.sortOrder = .date
        vm.sortDirection = .ascending
        vm.updateDerivedState()

        #expect(vm.filteredPhotoSets.map(\.baseName) == ["Photo1", "Photo2", "Photo3"])

        vm.sortDirection = .descending
        vm.updateDerivedState()

        #expect(vm.filteredPhotoSets.map(\.baseName) == ["Photo3", "Photo2", "Photo1"])
    }

    @Test
    func sortByFileSize_ascendingAndDescending() throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let fileSmall = tempDir.appendingPathComponent("small.jpg")
        let fileMedium = tempDir.appendingPathComponent("medium.jpg")
        let fileLarge = tempDir.appendingPathComponent("large.jpg")

        try Data(repeating: 0, count: 100).write(to: fileSmall)
        try Data(repeating: 0, count: 500).write(to: fileMedium)
        try Data(repeating: 0, count: 1000).write(to: fileLarge)

        let setSmall = PhotoSet(baseName: "Small", mediaFiles: [fileSmall], editPath: nil)
        let setMedium = PhotoSet(baseName: "Medium", mediaFiles: [fileMedium], editPath: nil)
        let setLarge = PhotoSet(baseName: "Large", mediaFiles: [fileLarge], editPath: nil)

        let vm = PhotoLibraryViewModel()
        vm.photoSets = [setMedium, setLarge, setSmall]
        vm.sortOrder = .size
        vm.sortDirection = .ascending
        vm.updateDerivedState()

        #expect(vm.filteredPhotoSets.map(\.baseName) == ["Small", "Medium", "Large"])

        vm.sortDirection = .descending
        vm.updateDerivedState()

        #expect(vm.filteredPhotoSets.map(\.baseName) == ["Large", "Medium", "Small"])
    }

    @Test
    func sortByOption_directAssignment() {
        let vm = PhotoLibraryViewModel()
        let setA = PhotoSet(baseName: "Alpha", mediaFiles: [], editPath: nil)
        let setB = PhotoSet(baseName: "Bravo", mediaFiles: [], editPath: nil)
        let setC = PhotoSet(baseName: "Charlie", mediaFiles: [], editPath: nil)

        vm.photoSets = [setB, setC, setA]
        vm.sortOption = .nameAscending
        vm.updateDerivedState()

        #expect(vm.filteredPhotoSets.map(\.baseName) == ["Alpha", "Bravo", "Charlie"])

        vm.sortOption = .nameDescending
        vm.updateDerivedState()

        #expect(vm.filteredPhotoSets.map(\.baseName) == ["Charlie", "Bravo", "Alpha"])
    }
}
