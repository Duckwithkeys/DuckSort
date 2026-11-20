//
//  MetadataReaderActor.swift
//  DuckSort
//
//  Offloads all EXIF and image metadata extraction to a dedicated global actor
//  to prevent main thread blocking and memory spikes during batch operations.
//

import Foundation
import ImageIO

@globalActor
actor MetadataActor {
    static let shared = MetadataActor()
}

@MetadataActor
final class MetadataReaderActor {
    static let shared = MetadataReaderActor()
    private let syncReader = MetadataReader()

    private init() {}

    /// Asynchronously extracts metadata for a given file URL off the main thread.
    func metadata(for url: URL) async -> MetadataSnapshot {
        return syncReader.metadata(for: url)
    }

    /// Batch extracts metadata concurrently in bounded parallel chunks off-actor
    /// so ImageIO calls run across cores without thread pool starvation.
    nonisolated func batchMetadata(for urls: [URL]) async -> [URL: MetadataSnapshot] {
        guard !urls.isEmpty else { return [:] }
        let workerCount = min(8, max(1, ProcessInfo.processInfo.activeProcessorCount))
        let chunkSize = max(1, (urls.count + workerCount - 1) / workerCount)
        let reader = MetadataReader()

        return await withTaskGroup(of: [(URL, MetadataSnapshot)].self) { group in
            for start in stride(from: 0, to: urls.count, by: chunkSize) {
                let end = min(start + chunkSize, urls.count)
                let slice = Array(urls[start..<end])
                group.addTask {
                    var chunkResults: [(URL, MetadataSnapshot)] = []
                    chunkResults.reserveCapacity(slice.count)
                    for url in slice {
                        chunkResults.append((url, reader.metadata(for: url)))
                    }
                    return chunkResults
                }
            }

            var results: [URL: MetadataSnapshot] = [:]
            results.reserveCapacity(urls.count)
            for await chunk in group {
                for (url, snapshot) in chunk {
                    results[url] = snapshot
                }
            }
            return results
        }
    }
}
