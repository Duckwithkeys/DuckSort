//
//  FilenameSanitizer.swift
//  PhotomatorSort
//

import Foundation

enum FilenameSanitizer {
    static func clean(_ value: String, fallback: String = "Unknown") -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return fallback }

        let illegal = CharacterSet(charactersIn: "/\\:?%*|\"<>")
        var result = ""
        result.reserveCapacity(trimmed.count)
        for scalar in trimmed.unicodeScalars {
            result.unicodeScalars.append(illegal.contains(scalar) ? "-" : scalar)
        }
        // Collapse runs of spaces. Two passes max because each replacement
        // can only reduce a 3+ space run by one; in practice filenames
        // rarely have more than two consecutive spaces.
        while result.contains("  ") {
            result = result.replacingOccurrences(of: "  ", with: " ")
        }
        let final = result.trimmingCharacters(in: .whitespacesAndNewlines)

        // A value of exactly "." or ".." (or any run of only dots) is a
        // parent/self-directory reference, not a filename. None of the
        // illegal-character replacement above touches ".", so this would
        // otherwise reach `folder.appendingPathComponent(...)` unchanged and
        // climb one level above the intended export destination per "..".
        if final.allSatisfy({ $0 == "." }) {
            return fallback
        }
        return final
    }
}

