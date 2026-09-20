import Testing
import Foundation
@testable import DuckSort

// Finding 1: `..`, `.`, and `...` used to pass through `FilenameSanitizer.clean`
// unchanged, so an attacker-controlled value (EXIF camera/lens model, an
// imported tag name) reached `folder.appendingPathComponent(...)` and climbed
// one level per "..". These tests pin the dot-only rejection and confirm
// every other value is untouched.
struct FilenameSanitizerTests {

    @Test
    func dotOnlyValues_returnFallback() {
        #expect(FilenameSanitizer.clean("..") == "Unknown")
        #expect(FilenameSanitizer.clean(".") == "Unknown")
        #expect(FilenameSanitizer.clean("...") == "Unknown")
        #expect(FilenameSanitizer.clean(" .. ") == "Unknown")
    }

    @Test
    func dotOnlyValue_withCustomFallback_returnsThatFallback() {
        #expect(FilenameSanitizer.clean("..", fallback: "") == "")
    }

    @Test
    func ordinaryCameraNames_areUnchanged() {
        #expect(FilenameSanitizer.clean("X-T5") == "X-T5")
        #expect(FilenameSanitizer.clean("Canon EOS R5") == "Canon EOS R5")
    }

    @Test
    func slashesAreReplaced_dotDotSegmentsAreNotBareDots() {
        // "a/b" documents existing slash-replacement behavior.
        #expect(FilenameSanitizer.clean("a/b") == "a-b")
        // "../x" is not itself dot-only (it has a real segment after the
        // slash), so it is left as the slash-replaced string rather than
        // falling back — only bare dot-only components were the escape
        // vector, and "../x" alone can't reach appendingPathComponent as a
        // traversal because the "/" became "-".
        #expect(FilenameSanitizer.clean("../x") == "..-x")
    }
}
