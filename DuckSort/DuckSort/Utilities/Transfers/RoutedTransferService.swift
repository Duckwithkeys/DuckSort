//
//  RoutedTransferService.swift
//  PhotomatorSort
//
//  Executes copy and move using the same export routing rule.
//  For each photo in the plan it computes a destination folder via
//  ExportPathRouter, then performs the requested operation.
//

import Foundation

actor RoutedTransferService {

    private let sidecarService = XMPTaggingService()

    struct RoutedJob: Sendable {
        let sourceURL: URL
        let destinationFolder: URL
        let photoSet: PhotoSet
        let tagNames: Set<String>
        let metadata: MetadataSnapshot
        let mediaSet: Set<URL>
    }

    /// Per-file item produced by the routing pass. Used to drive both the
    /// size pre-pass and the progress multiplier calculation. Declared at
    /// type scope so the static `chunkedTotalBytes` helper can read it.
    struct FileWalkItem: Sendable {
        let url: URL
        let multiplier: Int
    }

    func execute(
        _ plan: RoutedPlan,
        categoryNameProvider: @Sendable (UUID) -> String?,
        progress: (@Sendable (FileOperationProgress) async -> Void)? = nil
    ) async throws -> RoutedSummary {
        let fm = FileManager.default
        guard fm.isDirectory(atPath: plan.baseDestination.path) else {
            throw TransferError.destinationUnavailable(plan.baseDestination.path)
        }
        if plan.photos.isEmpty {
            return RoutedSummary(
                operation: plan.operation,
                fileCount: 0,
                baseDestination: plan.baseDestination,
                foldersCreated: 0,
                sidecarFailures: 0,
                filesLeftInPlace: 0
            )
        }

        var totalFiles = 0
        var foldersCreated = 0
        var sidecarFailures = 0

        // 0. Compute `destinationFolders` ONCE per photo. Used by phases
        //    1, 3, and 5 below — computing it three times was the dominant
        //    overhead on large routed transfers. Standardized immediately:
        //    a routed folder built from an unsanitized rule component (e.g.
        //    camera model "..") or an empty rule can lexically resolve back
        //    onto the source directory, and `Sorted/..` must compare equal
        //    to its parent for the same-source-and-destination guard below
        //    to catch it (Finding 3).
        struct RoutingResult: Sendable {
            let routed: RoutedPhoto
            let folders: [URL]
        }
        let routingResults: [RoutingResult] = plan.photos.map { routed in
            let folders = ExportPathRouter.destinationFolders(
                base: plan.baseDestination,
                rule: plan.rule,
                metadata: routed.metadata,
                assignedTags: routed.tags,
                categoryNameProvider: categoryNameProvider
            ).map { $0.standardizedFileURL }
            return RoutingResult(routed: routed, folders: folders)
        }

        // Containment guard (Finding 1, Finding 2): every routed folder must
        // stay under the base destination the user chose, checked before any
        // directory is created or byte touched. FilenameSanitizer neutralizes
        // "."/".."-only components and ExportPathRule sanitizes the
        // "No <category>" fallback, but this is the one point that must hold
        // regardless of what produced the folder. Every job's destination
        // sidecar is written beside `dest`, which is always built from one of
        // these same folders (CollisionResolver and FileNaming both derive
        // `dest` from `destinationFolder`), so this single check covers the
        // sidecar path too.
        try Self.verifyContained(routingResults.flatMap(\.folders), under: plan.baseDestination)

        // 1. Pre-walk & compute multipliers
        var walkItems: [FileWalkItem] = []
        walkItems.reserveCapacity(routingResults.reduce(0) { $0 + $1.folders.count * $1.routed.photoSet.allFiles.count })
        for result in routingResults {
            let multiplier = result.folders.count
            for fileURL in result.routed.photoSet.allFiles {
                totalFiles += multiplier
                walkItems.append(FileWalkItem(url: fileURL, multiplier: multiplier))
            }
        }

        // 2. Chunked parallel size computation. Avoids the 1-task-per-file
        //    overhead for very large transfers (1,500+ files) by grouping
        //    stat() syscalls into chunks sized to activeProcessorCount.
        let totalBytes = await Self.chunkedTotalBytes(items: walkItems)

        // 3. Build job list. Computed before any directory is created or
        //    file touched, so the same-source-and-destination guard right
        //    after it can refuse the whole operation before any write
        //    happens.
        var jobs: [RoutedJob] = []
        jobs.reserveCapacity(routingResults.reduce(0) { $0 + $1.folders.count * $1.routed.photoSet.allFiles.count })
        for result in routingResults {
            let routed = result.routed
            let mediaSet = Set(routed.photoSet.mediaFiles.map { $0.standardizedFileURL })
            let tagNames = Set(routed.tags.map(\.name))

            for folder in result.folders {
                for sourceURL in routed.photoSet.allFiles {
                    jobs.append(RoutedJob(
                        sourceURL: sourceURL,
                        destinationFolder: folder,
                        photoSet: routed.photoSet,
                        tagNames: tagNames,
                        metadata: routed.metadata,
                        mediaSet: mediaSet
                    ))
                }
            }
        }

        // 4. A single job whose destination resolves back onto its own
        //    source file is not an error — a mixed plan (some photos
        //    already sitting in their routed folder, others not) must
        //    still move the ones that aren't. Each such job is left alone
        //    below (CollisionResolver resolves it to `.skip`, so it's
        //    never copied or deleted — Finding 1). Only refuse the whole
        //    plan, before any directory is created, when *every* job is
        //    same-location: a plan that would touch nothing is the actual
        //    "wrong destination" case Finding 3 was about.
        let sameLocationFlags = jobs.map { job in
            job.destinationFolder
                .appendingPathComponent(job.sourceURL.lastPathComponent)
                .standardizedFileURL == job.sourceURL.standardizedFileURL
        }
        if !sameLocationFlags.isEmpty && sameLocationFlags.allSatisfy({ $0 }) {
            throw TransferError.sameSourceAndDestination
        }

        // 5. Pre-create directories sequentially to avoid race conditions
        for result in routingResults {
            for folder in result.folders {
                let existed = fm.fileExists(atPath: folder.path)
                try fm.createDirectory(at: folder, withIntermediateDirectories: true)
                if !existed { foldersCreated += 1 }
            }
        }

        // 6. Execute jobs in bounded concurrent task group
        let limit = min(8, ProcessInfo.processInfo.activeProcessorCount)
        let localSidecarService = self.sidecarService
        let startTime = Date()
        var completedBytes: Int64 = 0
        var processed = 0
        // Sources actually copied at least once. Phase 7 only deletes a
        // source that appears here — `.skip` (identical file already at the
        // destination) and same-location resolutions never insert into this
        // set, so a source that was never copied can never be removed
        // (Finding 3).
        var copiedSources = Set<URL>()
        // Sources whose destination sidecar write failed. Phase 7 must not
        // delete a source's orphan `.xmp` unless a fresh export sidecar
        // actually exists at the destination — otherwise a failed write
        // (e.g. a read-only destination) would destroy the only copy of
        // the tagging data with no replacement anywhere (Finding 3).
        var sidecarFailedSources = Set<URL>()
        // Jobs left untouched: an identical file already at the
        // destination (hash match), or a destination that resolved back
        // onto the source itself. Reported on `RoutedSummary` instead of
        // going silent (Finding 2).
        var filesLeftInPlace = 0

        try await withThrowingTaskGroup(of: (Int64, Bool, URL, URL, Bool).self) { group in
            var index = 0
            var runningTasks = 0
            while index < jobs.count && runningTasks < limit {
                let job = jobs[index]
                index += 1
                runningTasks += 1
                group.addTask {
                    try await self.executeJob(job, operation: plan.operation, sidecarService: localSidecarService)
                }
            }

            while let (fileSize, sidecarFailed, sourceURL, dest, copied) = try await group.next() {
                runningTasks -= 1
                processed += 1
                completedBytes += fileSize
                if sidecarFailed {
                    sidecarFailures += 1
                    sidecarFailedSources.insert(sourceURL.standardizedFileURL)
                }
                if copied {
                    copiedSources.insert(sourceURL.standardizedFileURL)
                } else {
                    filesLeftInPlace += 1
                }

                let elapsed = Date().timeIntervalSince(startTime)
                let bps = elapsed > 0 ? Double(completedBytes) / elapsed : 0
                await progress?(FileOperationProgress(
                    completed: processed,
                    total: totalFiles,
                    currentName: dest.lastPathComponent,
                    completedBytes: completedBytes,
                    totalBytes: totalBytes,
                    bytesPerSecond: bps
                ))

                if index < jobs.count {
                    let job = jobs[index]
                    index += 1
                    runningTasks += 1
                    group.addTask {
                        try await self.executeJob(job, operation: plan.operation, sidecarService: localSidecarService)
                    }
                }
            }
        }

        // 7. Clean up original source files for moveOriginals. Only a
        //    source that was actually copied somewhere (present in
        //    `copiedSources`) is removed — a file that was skipped as an
        //    identical duplicate, or whose destination collapsed onto its
        //    own location, was never in `copiedSources` and is left alone
        //    (Finding 3). The orphan `.xmp` is additionally left alone if
        //    the destination sidecar write for that source failed, so a
        //    failed write never leaves zero copies of the tagging data
        //    (Finding 3 follow-up).
        if plan.operation == .moveOriginals {
            for routed in plan.photos {
                let mediaSet = Set(routed.photoSet.mediaFiles.map { $0.standardizedFileURL })
                for sourceURL in routed.photoSet.allFiles {
                    guard copiedSources.contains(sourceURL.standardizedFileURL) else { continue }
                    if fm.fileExists(atPath: sourceURL.path) {
                        try? fm.removeItem(at: sourceURL)
                    }
                    if mediaSet.contains(sourceURL.standardizedFileURL)
                        && !sidecarFailedSources.contains(sourceURL.standardizedFileURL) {
                        let orphan = XMPTaggingService.exportSidecarURL(for: sourceURL)
                        if fm.fileExists(atPath: orphan.path) {
                            try? fm.removeItem(at: orphan)
                        }
                    }
                }
            }
        }

        return RoutedSummary(
            operation: plan.operation,
            fileCount: processed,
            baseDestination: plan.baseDestination,
            foldersCreated: foldersCreated,
            sidecarFailures: sidecarFailures,
            filesLeftInPlace: filesLeftInPlace
        )
    }

    // MARK: - Sidecar writing

    nonisolated private func executeJob(
        _ job: RoutedJob,
        operation: RoutedOperation,
        sidecarService: XMPTaggingService
    ) async throws -> (Int64, Bool, URL, URL, Bool) {
        let fm = FileManager.default
        let resolution = CollisionResolver.resolve(source: job.sourceURL, destinationDir: job.destinationFolder, fileManager: fm)

        let dest: URL
        var skipTransfer = false
        var isSameLocation = false

        switch resolution {
        case .skip:
            dest = job.destinationFolder.appendingPathComponent(job.sourceURL.lastPathComponent)
            skipTransfer = true
        case .overwrite:
            dest = job.destinationFolder.appendingPathComponent(job.sourceURL.lastPathComponent)
            try? fm.removeItem(at: dest)
        case .rename(let uniqueURL):
            dest = uniqueURL
        case .normal(let destURL):
            dest = destURL
        }

        let fileSize = (try? fm.attributesOfItem(atPath: job.sourceURL.path)[.size] as? Int64) ?? 0
        if !skipTransfer {
            isSameLocation = job.sourceURL.standardizedFileURL == dest.standardizedFileURL
            if !isSameLocation {
                try fm.copyItem(at: job.sourceURL, to: dest)
            }
        }
        // No copy exists for this source unless a real transfer happened:
        // `.skip` never wrote anything, and a same-location result means
        // `dest` *is* the source file, not a copy of it. Feeds phase 7's
        // deletion guard (Finding 3).
        let copied = !skipTransfer && !isSameLocation
        
        var sidecarFailed = false
        if !skipTransfer && job.mediaSet.contains(job.sourceURL.standardizedFileURL) {
            let sourceSidecar = XMPTaggingService.exportSidecarURL(for: job.sourceURL)
            let payload = SidecarPayload(
                tagNames: job.tagNames,
                capture: job.metadata,
                iptc: XMPTaggingService.iptcFromPreferences()
            )
            do {
                try sidecarService.writeExportSidecar(
                    payload,
                    besideDestinationFile: dest,
                    mergingSourceSidecar: sourceSidecar
                )
            } catch {
                sidecarFailed = true
            }
        }
        
        return (fileSize, sidecarFailed, job.sourceURL, dest, copied)
    }



    // MARK: - Containment guard

    /// Every routed folder must be `base` itself or a descendant of it.
    /// Throws `TransferError.destinationEscapesBase` for the first folder
    /// that isn't, before `execute` creates any directory or touches any
    /// file. Compares standardized paths with a trailing-slash prefix check
    /// (not a bare `hasPrefix`) so a sibling directory whose name merely
    /// shares `base`'s prefix — e.g. `base` = `/x/dest`, folder = `/x/dest2`
    /// — is correctly rejected rather than treated as contained.
    static func verifyContained(_ folders: [URL], under base: URL) throws {
        let basePath = base.standardizedFileURL.path
        for folder in folders {
            let folderPath = folder.standardizedFileURL.path
            guard folderPath == basePath || folderPath.hasPrefix(basePath + "/") else {
                throw TransferError.destinationEscapesBase(folder)
            }
        }
    }

    // MARK: - Chunked file size computation

    /// Compute total bytes across every file in `items`, applying each
    /// item's multiplier. Groups stat() syscalls into chunks sized to
    /// the active CPU count so 1,500 files don't spawn 1,500 task objects
    /// for trivial work. Multiplier-aware so routed plans (one source →
    /// many destinations) count correctly.
    private static func chunkedTotalBytes(
        items: [FileWalkItem]
    ) async -> Int64 {
        guard !items.isEmpty else { return 0 }
        let cores = max(1, ProcessInfo.processInfo.activeProcessorCount)
        let chunkSize = max(50, items.count / cores)

        return await withTaskGroup(of: Int64.self) { group in
            for chunkStart in stride(from: 0, to: items.count, by: chunkSize) {
                let upper = min(chunkStart + chunkSize, items.count)
                let slice = Array(items[chunkStart..<upper])
                group.addTask {
                    let fm = FileManager.default
                    var sum: Int64 = 0
                    for item in slice {
                        let size = (try? fm.attributesOfItem(atPath: item.url.path)[.size] as? Int64) ?? 0
                        sum += size * Int64(item.multiplier)
                    }
                    return sum
                }
            }
            var total: Int64 = 0
            for await partial in group { total += partial }
            return total
        }
    }

    // MARK: - Unique destination helper

    nonisolated private func uniqueDestinationURL(
        for sourceURL: URL,
        in directory: URL,
        fileManager: FileManager
    ) -> URL {
        FileNaming.uniqueDestinationURL(
            for: sourceURL, in: directory, fileManager: fileManager
        )
    }


}
