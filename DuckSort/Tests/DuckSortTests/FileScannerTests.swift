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
}
