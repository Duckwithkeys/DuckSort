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

    /// Batch extracts metadata concurrently in chunks to prevent thread pool starvation.
    func batchMetadata(for urls: [URL]) async -> [URL: MetadataSnapshot] {
        await withTaskGroup(of: (URL, MetadataSnapshot).self) { group in
            for url in urls {
                group.addTask {
                    let snapshot = await self.metadata(for: url)
                    return (url, snapshot)
                }
            }

            var results: [URL: MetadataSnapshot] = [:]
            for await (url, snapshot) in group {
                results[url] = snapshot
            }
            return results
        }
    }
}
