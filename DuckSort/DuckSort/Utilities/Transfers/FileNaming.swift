//
//  FileNaming.swift
//  DuckSort
//
//  Shared naming helpers for transfer destinations. Extracted so any future
//  optimization applies to every transfer path (plain + routed) at once.
//

import Foundation
import CryptoKit

enum CollisionResolution: Sendable, Equatable {
    case skip             // MD5 match
    case overwrite        // Size & Date match
    case rename(URL)      // Rename to a unique URL (e.g. suffix -1)
    case normal(URL)      // File does not exist yet, normal copy

    var label: String {
        switch self {
        case .skip:      return "Skip (Identical Hash)"
        case .overwrite: return "Overwrite (Same Size/Date)"
        case .rename:    return "Rename (Sequential Suffix)"
        case .normal:    return "New File"
        }
    }
}

enum CollisionResolver {
    static func resolve(
        source: URL,
        destinationDir: URL,
        fileManager: FileManager = .default
    ) -> CollisionResolution {
        let originalDest = destinationDir.appendingPathComponent(source.lastPathComponent)

        // A routed destination folder can resolve back onto the source file's
        // own directory (e.g. an export-rule value of ".." or an empty rule
        // whose base is the source itself — Finding 3). When that happens
        // `originalDest` and `source` are the same file: `fileExists` is
        // trivially true and the hash trivially matches, so without this
        // check `.overwrite` could be returned and the caller would delete
        // the only copy of the file. Short-circuit to `.skip` so the source
        // is never treated as a collision target.
        if source.standardizedFileURL == originalDest.standardizedFileURL {
            return .skip
        }

        // If file doesn't exist, it's a normal transfer
        guard fileManager.fileExists(atPath: originalDest.path) else {
            return .normal(originalDest)
        }
        
        // 1. SHA-256 Checksum Skip
        if let sourceHash = fileHash(url: source),
           let destHash = fileHash(url: originalDest),
           sourceHash == destHash {
            return .skip
        }
        
        // 2. Overwrite if identical file size & creation date
        if let sourceAttrs = try? fileManager.attributesOfItem(atPath: source.path),
           let destAttrs = try? fileManager.attributesOfItem(atPath: originalDest.path) {
            let sourceSize = sourceAttrs[.size] as? Int64
            let destSize = destAttrs[.size] as? Int64
            let sourceDate = sourceAttrs[.creationDate] as? Date
            let destDate = destAttrs[.creationDate] as? Date
            
            if sourceSize != nil && sourceSize == destSize && sourceDate != nil && sourceDate == destDate {
                return .overwrite
            }
        }
        
        // 3. Sequential Suffix Rename
        let base = source.deletingPathExtension().lastPathComponent
        let ext = source.pathExtension
        for index in 1...Int.max {
            let candidateName = ext.isEmpty ? "\(base)-\(index)" : "\(base)-\(index).\(ext)"
            let candidate = destinationDir.appendingPathComponent(candidateName)
            if !fileManager.fileExists(atPath: candidate.path) {
                return .rename(candidate)
            }
        }
        
        return .rename(originalDest)
    }
    
    private static func fileHash(url: URL) -> String? {
        guard let file = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? file.close() }
        var hasher = SHA256()
        let bufferSize = 1024 * 1024
        while true {
            guard let chunk = try? file.read(upToCount: bufferSize), !chunk.isEmpty else { break }
            hasher.update(data: chunk)
        }
        return hasher.finalize().compactMap { String(format: "%02hhx", $0) }.joined()
    }
}

enum FileNaming {
    /// Build a unique destination URL inside `directory` for `sourceURL`.
    /// If `sourceURL` already lives directly in `directory` (i.e. copying
    /// or moving onto itself), returns the original. If the candidate path
    /// is free, returns it. Otherwise, appends `-1`, `-2`, … until an
    /// unused name is found.
    nonisolated static func uniqueDestinationURL(
        for sourceURL: URL,
        in directory: URL,
        fileManager: FileManager = .default
    ) -> URL {
        let original = directory.appendingPathComponent(sourceURL.lastPathComponent)
        if sourceURL.standardizedFileURL == original.standardizedFileURL {
            return original
        }
        guard fileManager.fileExists(atPath: original.path) else { return original }

        let base = sourceURL.deletingPathExtension().lastPathComponent
        let ext = sourceURL.pathExtension

        for index in 1...Int.max {
            let candidateName: String
            if ext.isEmpty {
                candidateName = "\(base)-\(index)"
            } else {
                candidateName = "\(base)-\(index).\(ext)"
            }

            let candidate = directory.appendingPathComponent(candidateName)
            if !fileManager.fileExists(atPath: candidate.path) {
                return candidate
            }
        }

        return original
    }
}
