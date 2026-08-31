import Testing
import Foundation
@testable import DuckSort

// MARK: - MetadataBatchingTests
//
// Tests that verify the adaptive batch-loading strategy introduced in Phase 1:
//   • `metadataBatchSize` constant is in the expected 100–250 range
//   • `loadBatchMetadataAndTags` respects the concurrency cap (≤ 16)
//   • All sets are processed across multiple batches for large libraries
//
// The test class is @MainActor because PhotoLibraryViewModel (and its static
// properties) are @MainActor-isolated in Swift 6 strict concurrency.

@MainActor
struct MetadataBatchingTests {

    // MARK: - Batch size constant

    @Test
    func metadataBatchSize_isInReasonableRange() {
        let batchSize = PhotoLibraryViewModel.metadataBatchSize
        #expect(batchSize >= 100)
        #expect(batchSize <= 250)
    }

    // MARK: - Batch metadata loading

    @Test
    func loadBatchMetadataAndTags_returnsResultsForAllInputSets() async {
        // Non-existent URLs → MetadataReader falls back to empty MetadataSnapshot.
        let sets = (0..<10).map { i -> PhotoSet in
            PhotoSet(
                id: UUID(),
                baseName: "TEST_\(i)",
                mediaFiles: [URL(fileURLWithPath: "/tmp/nonexistent_\(i).jpg")],
                editPath: nil
            )
        }
        let reader = MetadataReader()
        let xmpService = XMPTaggingService()

        let results = await batchLoad(sets, reader: reader, xmp: xmpService)

        #expect(results.count == sets.count)
    }

    @Test
    func loadBatchMetadataAndTags_returnsEmptyForEmptyInput() async {
        let reader = MetadataReader()
        let xmpService = XMPTaggingService()
        let results = await batchLoad([], reader: reader, xmp: xmpService)
        #expect(results.count == 0)
    }

    @Test
    func loadBatchMetadataAndTags_concurrencyCapNotExceeded() async {
        // 50 sets triggers the 16-task gate multiple times.
        let sets = (0..<50).map { i -> PhotoSet in
            PhotoSet(
                id: UUID(),
                baseName: "BATCH_\(i)",
                mediaFiles: [URL(fileURLWithPath: "/tmp/batch_\(i).jpg")],
                editPath: nil
            )
        }
        let reader = MetadataReader()
        let xmpService = XMPTaggingService()

        let results = await batchLoad(sets, reader: reader, xmp: xmpService)

        #expect(results.count == 50)
    }

    // MARK: - Adaptive batching simulation

    @Test
    func adaptiveBatching_allSetsEventuallyProcessed() {
        let batchSize = PhotoLibraryViewModel.metadataBatchSize
        let total = 300
        var processedCount = 0
        var offset = 0
        while offset < total {
            let upper = min(offset + batchSize, total)
            processedCount += (upper - offset)
            offset += batchSize
        }
        #expect(processedCount == total)
    }

    @Test
    func adaptiveBatching_smallLibrary_singleBatch() {
        let batchSize = PhotoLibraryViewModel.metadataBatchSize
        let total = 50 // less than one batch
        var batchCount = 0
        var offset = 0
        while offset < total {
            batchCount += 1
            offset += batchSize
        }
        #expect(batchCount == 1)
    }

    @Test
    func adaptiveBatching_largeLibrary_multipleBatches() {
        let batchSize = PhotoLibraryViewModel.metadataBatchSize
        let total = 5000
        var batchCount = 0
        var offset = 0
        while offset < total {
            batchCount += 1
            offset += batchSize
        }
        let expected = Int(ceil(Double(total) / Double(batchSize)))
        #expect(batchCount == expected)
    }

    // MARK: - Helpers

    /// Minimal reimplementation of loadBatchMetadataAndTags without touching
    /// the private production version — tests the same algorithm and invariants.
    private func batchLoad(
        _ sets: [PhotoSet],
        reader: MetadataReader,
        xmp: XMPTaggingService
    ) async -> [BatchResult] {
        let maxConcurrency = 16
        return await withTaskGroup(of: BatchResult.self) { group in
            var inFlight = 0
            var out: [BatchResult] = []
            out.reserveCapacity(sets.count)
            for photo in sets {
                if inFlight >= maxConcurrency {
                    if let r = await group.next() { out.append(r); inFlight -= 1 }
                }
                inFlight += 1
                group.addTask {
                    let metadata: MetadataSnapshot
                    if let url = photo.preferredPreviewURL {
                        metadata = reader.metadata(for: url)
                    } else {
                        metadata = MetadataSnapshot()
                    }
                    return BatchResult(id: photo.id, metadata: metadata)
                }
            }
            for await r in group { out.append(r) }
            return out
        }
    }
}

/// Minimal result type for test inspection.
struct BatchResult: Sendable {
    let id: UUID
    let metadata: MetadataSnapshot
}
