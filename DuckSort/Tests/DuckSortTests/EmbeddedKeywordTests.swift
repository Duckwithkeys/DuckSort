import Testing
import Foundation
import ImageIO
@testable import DuckSort

struct EmbeddedKeywordTests {
    @Test
    func mergingKeywords_setsIptcKeywords() {
        let result = XMPTaggingService.mergingKeywords(["Family", "Ceremony"], into: [:])
        let iptc = result[kCGImagePropertyIPTCDictionary] as? [CFString: Any]
        let keywords = iptc?[kCGImagePropertyIPTCKeywords] as? [String]
        #expect(keywords == ["Ceremony", "Family"])
    }

    @Test
    func mergingKeywords_emptySetLeavesPropertiesUnchanged() {
        let original: [CFString: Any] = [kCGImagePropertyTIFFDictionary: ["k": "v"]]
        let result = XMPTaggingService.mergingKeywords([], into: original)
        #expect(result[kCGImagePropertyIPTCDictionary] == nil)
    }
}
