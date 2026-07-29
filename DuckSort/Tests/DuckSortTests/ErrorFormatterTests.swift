import XCTest
@testable import DuckSort

final class ErrorFormatterTests: XCTestCase {

    func test_errorFormatter_stripsTechnicalCodes() {
        let rawMessage = "Failed to scan folder /Volumes/SD_Card/DCIM (error code -34)."
        let formatted = ErrorFormatter.format(rawMessage)

        XCTAssertEqual(formatted.cleanMessage, "Failed to scan folder /Volumes/SD_Card/DCIM.")
        XCTAssertTrue(formatted.suggestion.contains("Verify that the source directory is connected"))
    }

    func test_errorFormatter_handlesVariousPatterns() {
        let cases = [
            ("An error occurred (error -1)", "An error occurred"),
            ("Unable to write changes code 256.", "Unable to write changes."),
            ("Import failed (OSStatus error -50)", "Import failed"),
            ("Could not open file (Cocoa error 260)", "Could not open file")
        ]

        for (raw, expectedClean) in cases {
            let formatted = ErrorFormatter.format(raw)
            XCTAssertEqual(formatted.cleanMessage, expectedClean)
        }
    }

    func test_errorFormatter_emptyFallback() {
        let formatted = ErrorFormatter.format(" (error -1)")
        XCTAssertEqual(formatted.cleanMessage, "An unexpected operation failure occurred.")
    }

    func test_errorFormatter_contextualSuggestions() {
        // Permission context
        let perm = ErrorFormatter.format("Access was denied by the OS")
        XCTAssertTrue(perm.suggestion.contains("System Settings"))

        // Decode context
        let dec = ErrorFormatter.format("Failed to decode HEIC pixels")
        XCTAssertTrue(dec.suggestion.contains("supported format"))

        // Write context
        let wr = ErrorFormatter.format("Destination disk full")
        XCTAssertTrue(wr.suggestion.contains("destination volume"))
    }
}
