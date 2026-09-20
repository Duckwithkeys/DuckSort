//
//  FileScannerTests.swift
//  DuckSortTests
//
//  Covers FileScanner.scanFiles — the loose-file grouping used by drag-and-drop
//  and the Import command.
//

import Testing
import Foundation
@testable import DuckSort

class FileScannerTests {

    private var tempDir: URL!

    init() throws {
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("DuckSortTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    }

    deinit {
        if let tempDir { try? FileManager.default.removeItem(at: tempDir) }
    }

    @discardableResult
    private func makeFile(_ name: String) throws -> URL {
        let url = tempDir.appendingPathComponent(name)
        try Data().write(to: url)
        return url
    }

    private func set(named base: String, in result: FileScanner.ScanResult) -> PhotoSet? {
        result.photoSets.first { $0.baseName == base }
    }

    @Test
    func GroupsByBaseNameAndMergesSidecar() async throws {
        let urls = [
            try makeFile("IMG_001.jpg"),
            try makeFile("IMG_001.raf"),
            try makeFile("IMG_001.photo-edit"),
            try makeFile("IMG_002.jpg")
        ]

        let result = await FileScanner().scanFiles(urls)

        #expect(result.photoSets.count == 2)

        let first = try #require(set(named: "IMG_001", in: result))
        #expect(first.mediaCount == 2)
        #expect(first.hasEdit)

        let second = try #require(set(named: "IMG_002", in: result))
        #expect(second.mediaCount == 1)
        #expect(!(second.hasEdit))

        // 2 media + 1 edit for IMG_001, 1 media for IMG_002.
        #expect(result.scannedFileCount == 4)
    }

    @Test
    func UnknownExtensionsAreIgnored() async throws {
        let urls = [
            try makeFile("IMG_001.jpg"),
            try makeFile("notes.txt")
        ]

        let result = await FileScanner().scanFiles(urls)

        #expect(result.photoSets.count == 1)
        #expect(result.ignoredFileCount == 1)
    }

    // Finding 4: `.xmp` isn't in FileScanner's extension lookup, so a
    // symlinked sidecar is invisible to the scanner itself, but reading its
    // metadata afterward (XMPTaggingService.readSidecarData) must still
    // refuse to follow the link rather than pulling in the outside file's
    // keywords/rating/caption.
    @Test
    func SymlinkedSidecar_readSidecarDataReturnsEmpty() async throws {
        let outside = FileManager.default.temporaryDirectory
            .appendingPathComponent("DuckSortTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: outside, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: outside) }

        let secret = outside.appendingPathComponent("secret.xmp")
        let secretXMP = """
        <x:xmpmeta xmlns:x="adobe:ns:meta/">
          <rdf:RDF xmlns:rdf="http://www.w3.org/1999/02/22-rdf-syntax-ns#">
            <rdf:Description xmp:Rating="5" xmlns:xmp="http://ns.adobe.com/xap/1.0/">
              <dc:subject xmlns:dc="http://purl.org/dc/elements/1.1/">
                <rdf:Bag><rdf:li>Leaked</rdf:li></rdf:Bag>
              </dc:subject>
            </rdf:Description>
          </rdf:RDF>
        </x:xmpmeta>
        """
        try secretXMP.write(to: secret, atomically: true, encoding: .utf8)

        let media = try makeFile("IMG_002.jpg")
        let sidecar = tempDir.appendingPathComponent("IMG_002.xmp")
        try FileManager.default.createSymbolicLink(at: sidecar, withDestinationURL: secret)

        let result = await FileScanner().scanFiles([media])
        let set = try #require(self.set(named: "IMG_002", in: result))

        let data = XMPTaggingService().readSidecarData(from: set)
        #expect(data.tags.isEmpty)
        #expect(data.rating == nil)
        #expect(data.pick == nil)
        #expect(data.description == nil)

        // Reading through the link never touched it.
        let type = try FileManager.default.attributesOfItem(atPath: sidecar.path)[.type] as? FileAttributeType
        #expect(type == .typeSymbolicLink)
    }
}
