import Testing
import Foundation
@testable import DuckSort

// Finding 3: `CollisionResolver.resolve` must never return `.overwrite` for
// the source file itself — that result drives a `removeItem(at: dest)` in
// `RoutedTransferService`, which would delete the source when `dest` and
// `source` are the same file.
struct CollisionResolverTests {

    @Test
    func resolve_destinationIsSourceFile_neverReturnsOverwrite() throws {
        let base = try TempDir.make()
        defer { try? FileManager.default.removeItem(at: base) }
        let file = base.appendingPathComponent("file.jpg")
        try Data("source bytes".utf8).write(to: file)

        // Same-directory form: destinationDir *is* the file's own directory.
        let sameDirResult = CollisionResolver.resolve(source: file, destinationDir: base)
        #expect(sameDirResult == .skip)

        // `dir/../file` form: destinationDir lexically resolves back onto
        // the source's own directory once standardized, without "Sub"
        // needing to exist on disk.
        let dotDotDir = base.appendingPathComponent("Sub").appendingPathComponent("..")
        let dotDotResult = CollisionResolver.resolve(source: file, destinationDir: dotDotDir)
        #expect(dotDotResult == .skip)
    }

    @Test
    func resolve_noFileAtDestination_returnsNormal() throws {
        let sourceDir = try TempDir.make(); let destDir = try TempDir.make()
        defer {
            try? FileManager.default.removeItem(at: sourceDir)
            try? FileManager.default.removeItem(at: destDir)
        }
        let file = sourceDir.appendingPathComponent("file.jpg")
        try Data("source bytes".utf8).write(to: file)

        let result = CollisionResolver.resolve(source: file, destinationDir: destDir)
        #expect(result == .normal(destDir.appendingPathComponent("file.jpg")))
    }

    @Test
    func resolve_identicalCopyElsewhere_returnsSkip() throws {
        let sourceDir = try TempDir.make(); let destDir = try TempDir.make()
        defer {
            try? FileManager.default.removeItem(at: sourceDir)
            try? FileManager.default.removeItem(at: destDir)
        }
        let source = sourceDir.appendingPathComponent("file.jpg")
        let dest = destDir.appendingPathComponent("file.jpg")
        try Data("identical bytes".utf8).write(to: source)
        try Data("identical bytes".utf8).write(to: dest)

        let result = CollisionResolver.resolve(source: source, destinationDir: destDir)
        #expect(result == .skip)
    }

    @Test
    func resolve_sameSizeAndCreationDateDifferentContent_returnsOverwrite() throws {
        let sourceDir = try TempDir.make(); let destDir = try TempDir.make()
        defer {
            try? FileManager.default.removeItem(at: sourceDir)
            try? FileManager.default.removeItem(at: destDir)
        }
        let source = sourceDir.appendingPathComponent("file.jpg")
        let dest = destDir.appendingPathComponent("file.jpg")
        try Data("AAAA bytes matching size".utf8).write(to: source)
        try Data("BBBB bytes matching size".utf8).write(to: dest)

        let fixedDate = Date(timeIntervalSince1970: 1_700_000_000)
        try FileManager.default.setAttributes([.creationDate: fixedDate], ofItemAtPath: source.path)
        try FileManager.default.setAttributes([.creationDate: fixedDate], ofItemAtPath: dest.path)

        let result = CollisionResolver.resolve(source: source, destinationDir: destDir)
        #expect(result == .overwrite)
    }

    @Test
    func resolve_differentSize_returnsRename() throws {
        let sourceDir = try TempDir.make(); let destDir = try TempDir.make()
        defer {
            try? FileManager.default.removeItem(at: sourceDir)
            try? FileManager.default.removeItem(at: destDir)
        }
        let source = sourceDir.appendingPathComponent("file.jpg")
        let dest = destDir.appendingPathComponent("file.jpg")
        try Data("short".utf8).write(to: source)
        try Data("a much longer set of different bytes entirely".utf8).write(to: dest)

        let result = CollisionResolver.resolve(source: source, destinationDir: destDir)
        #expect(result == .rename(destDir.appendingPathComponent("file-1.jpg")))
    }
}
