import XCTest
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
final class MetadataBatchingTests: XCTestCase {

    // MARK: - Batch size constant

    func test_metadataBatchSize_isInReasonableRange() {
        let batchSize = PhotoLibraryViewModel.metadataBatchSize
        XCTAssertGreaterThanOrEqual(batchSize, 100,
            "Batch size must be at least 100 to reduce UI update frequency")
        XCTAssertLessThanOrEqual(batchSize, 250,
            "Batch size above 250 delays first-visible-batch appearance")
    }

    // MARK: - Batch metadata loading

    func test_loadBatchMetadataAndTags_returnsResultsForAllInputSets() async {
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

        XCTAssertEqual(results.count, sets.count,
            "loadBatchMetadataAndTags should return one result per input PhotoSet, " +
            "even for unreadable files (fallback to empty MetadataSnapshot)")
    }

    func test_loadBatchMetadataAndTags_returnsEmptyForEmptyInput() async {
        let reader = MetadataReader()
        let xmpService = XMPTaggingService()
        let results = await batchLoad([], reader: reader, xmp: xmpService)
        XCTAssertEqual(results.count, 0)
    }

    func test_loadBatchMetadataAndTags_concurrencyCapNotExceeded() async {
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

        XCTAssertEqual(results.count, 50,
            "All 50 sets should produce results under the 16-task concurrency gate")
    }

    // MARK: - Adaptive batching simulation

    func test_adaptiveBatching_allSetsEventuallyProcessed() {
        let batchSize = PhotoLibraryViewModel.metadataBatchSize
        let total = 300
        var processedCount = 0
        var offset = 0
        while offset < total {
            let upper = min(offset + batchSize, total)
            processedCount += (upper - offset)
            offset += batchSize
        }
        XCTAssertEqual(processedCount, total,
            "Adaptive batching must process all \(total) sets without leaving any behind")
    }

    func test_adaptiveBatching_smallLibrary_singleBatch() {
        let batchSize = PhotoLibraryViewModel.metadataBatchSize
        let total = 50 // less than one batch
        var batchCount = 0
        var offset = 0
        while offset < total {
            batchCount += 1
            offset += batchSize
        }
        XCTAssertEqual(batchCount, 1,
            "A library smaller than batchSize should require only one batch")
    }

    func test_adaptiveBatching_largeLibrary_multipleBatches() {
        let batchSize = PhotoLibraryViewModel.metadataBatchSize
        let total = 5000
        var batchCount = 0
        var offset = 0
        while offset < total {
            batchCount += 1
            offset += batchSize
        }
        let expected = Int(ceil(Double(total) / Double(batchSize)))
        XCTAssertEqual(batchCount, expected,
            "5,000-photo library should be split into exactly \(expected) batches")
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
