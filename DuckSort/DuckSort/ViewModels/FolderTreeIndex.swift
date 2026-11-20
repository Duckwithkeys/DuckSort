//
//  FolderTreeIndex.swift
//  PhotomatorSort
//
//  Pre-computed O(1) folder hierarchy index used by the recursive sidebar.
//

import Foundation

struct FolderTreeIndex: Sendable {
    var cachedSubfolders: [URL: [URL]] = [:]
    var cachedSubfolderCounts: [URL: Int] = [:]
    var childSubfoldersIndex: [String: [String]] = [:]
    var recursivePhotoCountIndex: [String: Int] = [:]
    var childFolderURLs: [String: [URL]] = [:]

    static func build(
        from photoSetsBySubfolder: [URL: Set<UUID>],
        sourceDirectories: [URL]
    ) -> FolderTreeIndex {
        var subfoldersMap: [URL: [URL]] = [:]
        var subfolderPhotoCounts: [URL: Int] = [:]

        let allSubfolders = Array(photoSetsBySubfolder.keys)

        for sourceURL in sourceDirectories {
            let standardizedSource = sourceURL.standardizedFileURL.path
            let sourcePrefix = standardizedSource.hasSuffix("/") ? standardizedSource : standardizedSource + "/"
            var subfoldersSet = Set<URL>()

            for parentDir in allSubfolders {
                let parentPath = parentDir.path
                if parentPath.hasPrefix(sourcePrefix) {
                    subfoldersSet.insert(parentDir)
                }
            }

            let sorted = subfoldersSet.sorted { $0.path < $1.path }
            subfoldersMap[sourceURL] = sorted
        }

        for subfolders in subfoldersMap.values {
            for subfolder in subfolders {
                subfolderPhotoCounts[subfolder] = photoSetsBySubfolder[subfolder]?.count ?? 0
            }
        }

        var childAccum: [String: Set<String>] = [:]
        var photoCountByPath: [String: Int] = [:]
        childAccum.reserveCapacity(photoSetsBySubfolder.count * 2)
        photoCountByPath.reserveCapacity(photoSetsBySubfolder.count)

        let rootURL = URL(fileURLWithPath: "/")
        for (folder, sets) in photoSetsBySubfolder {
            let folderPath = folder.path
            photoCountByPath[folderPath, default: 0] += sets.count

            var current = folder
            while current.path != "/" && current.path != rootURL.path {
                let parent = current.deletingLastPathComponent()
                let parentPath = parent.path

                if parentPath != "/" && parentPath != rootURL.path {
                    var bucket = childAccum[parentPath, default: Set()]
                    bucket.insert(current.path)
                    childAccum[parentPath] = bucket
                }

                if current != folder {
                    photoCountByPath[current.path, default: 0] += sets.count
                }

                current = parent
            }
        }

        var childPaths: [String: [String]] = [:]
        var childURLs: [String: [URL]] = [:]
        childPaths.reserveCapacity(childAccum.count)
        childURLs.reserveCapacity(childAccum.count)
        for (parentPath, kids) in childAccum {
            let sortedPaths = kids.sorted()
            childPaths[parentPath] = sortedPaths
            childURLs[parentPath] = sortedPaths.map { URL(fileURLWithPath: $0) }
        }

        return FolderTreeIndex(
            cachedSubfolders: subfoldersMap,
            cachedSubfolderCounts: subfolderPhotoCounts,
            childSubfoldersIndex: childPaths,
            recursivePhotoCountIndex: photoCountByPath,
            childFolderURLs: childURLs
        )
    }

    static func relativePath(of subfolderURL: URL, relativeTo sourceURL: URL) -> String {
        let sourcePath = sourceURL.standardizedFileURL.path
        let subfolderPath = subfolderURL.standardizedFileURL.path
        let sourcePrefix = sourcePath.hasSuffix("/") ? sourcePath : sourcePath + "/"
        if subfolderPath.hasPrefix(sourcePrefix) {
            return String(subfolderPath.dropFirst(sourcePrefix.count))
        }
        return subfolderURL.lastPathComponent
    }
}
