import Testing
import Foundation
@testable import DuckSort

struct ErrorFormatterTests {

    @Test
    func errorFormatter_stripsTechnicalCodes() {
        let rawMessage = "Failed to scan folder /Volumes/SD_Card/DCIM (error code -34)."
        let formatted = ErrorFormatter.format(rawMessage)

        #expect(formatted.cleanMessage == "Failed to scan folder /Volumes/SD_Card/DCIM.")
        #expect(formatted.suggestion.contains("Verify that the source directory is connected"))
    }

    @Test
    func errorFormatter_handlesVariousPatterns() {
        let cases = [
            ("An error occurred (error -1)", "An error occurred"),
            ("Unable to write changes code 256.", "Unable to write changes."),
            ("Import failed (OSStatus error -50)", "Import failed"),
            ("Could not open file (Cocoa error 260)", "Could not open file")
        ]

        for (raw, expectedClean) in cases {
            let formatted = ErrorFormatter.format(raw)
            #expect(formatted.cleanMessage == expectedClean)
        }
    }

    @Test
    func errorFormatter_emptyFallback() {
        let formatted = ErrorFormatter.format(" (error -1)")
        #expect(formatted.cleanMessage == "An unexpected operation failure occurred.")
    }

    @Test
    func errorFormatter_contextualSuggestions() {
        // Permission context
        let perm = ErrorFormatter.format("Access was denied by the OS")
        #expect(perm.suggestion.contains("System Settings"))

        // Decode context
        let dec = ErrorFormatter.format("Failed to decode HEIC pixels")
        #expect(dec.suggestion.contains("supported format"))

        // Write context
        let wr = ErrorFormatter.format("Destination disk full")
        #expect(wr.suggestion.contains("destination volume"))
    }
}
