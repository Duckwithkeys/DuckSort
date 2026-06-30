//
//  FileNaming.swift
//  DuckSort
//
//  Shared naming helpers for transfer destinations. Extracted so any future
//  optimization applies to every transfer path (plain + routed) at once.
//

import Foundation
import CommonCrypto

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
        
        // If file doesn't exist, it's a normal transfer
        guard fileManager.fileExists(atPath: originalDest.path) else {
            return .normal(originalDest)
        }
        
        // 1. MD5 Checksum Skip
        if let sourceMD5 = fileMD5(url: source),
           let destMD5 = fileMD5(url: originalDest),
           sourceMD5 == destMD5 {
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
    
    private static func fileMD5(url: URL) -> String? {
        guard let file = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? file.close() }
        var context = CC_MD5_CTX()
        CC_MD5_Init(&context)
        let bufferSize = 1024 * 1024
        while true {
            if #available(macOS 10.15.4, *) {
                guard let chunk = try? file.read(upToCount: bufferSize), !chunk.isEmpty else { break }
                chunk.withUnsafeBytes {
                    _ = CC_MD5_Update(&context, $0.baseAddress, CC_LONG($0.count))
                }
            } else {
                let chunk = file.readData(ofLength: bufferSize)
                if chunk.isEmpty { break }
                chunk.withUnsafeBytes {
                    _ = CC_MD5_Update(&context, $0.baseAddress, CC_LONG($0.count))
                }
            }
        }
        var digest = [UInt8](repeating: 0, count: Int(CC_MD5_DIGEST_LENGTH))
        CC_MD5_Final(&digest, &context)
        return digest.map { String(format: "%02hhx", $0) }.joined()
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
