//
//  ErrorFormatter.swift
//  DuckSort
//
//  Formats system and app-level error messages to remove technical error numbers
//  or raw codes, and appends user-friendly recovery instructions based on context.
//

import Foundation

struct ErrorFormatter {
    struct FormattedError: Sendable {
        let cleanMessage: String
        let suggestion: String
    }

    /// Strips error codes and attaches actionable suggestions.
    static func format(_ rawMessage: String) -> FormattedError {
        var clean = rawMessage

        // Patterns to match technical error codes:
        // (error code -34), (OSStatus error -50), (Cocoa error 260), etc.
        let patterns = [
            "\\s*\\([^)]*\\b(error|code|status|osstatus|cocoa)\\b[^)]*\\)",
            "\\s*\\b(error|code|status|osstatus|cocoa)\\s+-?\\d+\\b"
        ]

        for pattern in patterns {
            if let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) {
                clean = regex.stringByReplacingMatches(
                    in: clean,
                    options: [],
                    range: NSRange(location: 0, length: clean.utf16.count),
                    withTemplate: ""
                )
            }
        }

        // Clean double brackets or stray symbols left by replacement
        clean = clean
            .replacingOccurrences(of: "()", with: "")
            .replacingOccurrences(of: "[]", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        if clean.isEmpty {
            clean = "An unexpected operation failure occurred."
        }

        // Guess the corrective action based on error keywords
        let msgLower = clean.lowercased()
        let suggestion: String

        if msgLower.contains("permission") || msgLower.contains("denied") || msgLower.contains("privilege") || msgLower.contains("access") {
            suggestion = "Verify folder read/write privileges in macOS System Settings → Privacy & Security → Files and Folders."
        } else if msgLower.contains("decode") || msgLower.contains("corrupt") || msgLower.contains("unsupported") || msgLower.contains("load") || msgLower.contains("format") {
            suggestion = "Ensure the image file is not corrupt, is in a supported format (.jpg, .heic, or RAW), and is readable."
        } else if msgLower.contains("destination") || msgLower.contains("write") || msgLower.contains("export") || msgLower.contains("transfer") {
            suggestion = "Make sure the destination volume is connected, has sufficient free space, and is not write-protected."
        } else if msgLower.contains("scan") || msgLower.contains("folder") || msgLower.contains("directory") || msgLower.contains("source") {
            suggestion = "Verify that the source directory is connected, has not been moved, and remains accessible."
        } else {
            suggestion = "Check folder permissions, ensure your external drives are connected, or try restarting the application."
        }

        return FormattedError(cleanMessage: clean, suggestion: suggestion)
    }
}
