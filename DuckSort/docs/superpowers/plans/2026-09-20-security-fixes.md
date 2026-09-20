# Security Fixes Implementation Plan — 2026-09-20

**Spec:** `DuckSort/docs/security/2026-09-20-security-review.md` (the security review). Every
finding number below refers to that document. Read the relevant finding before starting a task;
it holds the verified data paths, line numbers, and exploit scenarios.

**Package root:** `DuckSort/` (the directory containing `Package.swift`). All `swift test`
commands run from there.

## Global Constraints

- TDD: write the failing test first, watch it fail for the right reason, then implement. Report
  RED and GREEN evidence.
- Tests use the real filesystem via `TempDir.make()` and real JPEG fixtures via
  `ImageFixture.writeJPEG(to:cameraModel:...)` (see `Tests/DuckSortTests/Support/ImageFixture.swift`).
  No mocks, no fakes, no test doubles for FileManager.
- Tests are Swift Testing (`import Testing`, `@Test`, `#expect`, `#expect(throws:)`), matching the
  existing test files.
- Run the full suite once before committing: `swift test` from `DuckSort/`. Output must be clean:
  zero failures and no new warnings.
- Never delete, skip, or weaken an existing test. If an existing test contradicts a fix, stop and
  report it as DONE_WITH_CONCERNS with the test name.
- Security checks throw a typed error the caller can surface; never silently skip a file because
  a check failed. Existing `TransferError` cases live in
  `DuckSort/Utilities/Transfers/FileTransferService.swift`.
- Comments explain why the code is written the way it is (the attack it prevents). No comments
  about what used to be there.
- One commit per task (more is fine if logical). Commit message: conventional style
  (`fix(security): ...`), body explains the vulnerability, and ends with the line
  `Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>`. Never bypass a pre-commit hook.
- Do not touch `RoutedTransferService.swift` outside the lines the task names unless the change
  is required to make the task compile.

---

## Task 1: Move Originals must never delete a source that was not copied

Fixes **Finding 3 (High)** in the security review.

**Files:** `DuckSort/Utilities/Transfers/RoutedTransferService.swift`,
`DuckSort/Utilities/Transfers/FileNaming.swift`,
`DuckSort/ViewModels/PhotoLibraryViewModel.swift`,
new `Tests/DuckSortTests/RoutedMoveSafetyTests.swift`,
new `Tests/DuckSortTests/CollisionResolverTests.swift`.

**Problem.** In `RoutedTransferService.execute`, phase 6 (`// 6. Clean up original source files
for moveOriginals`, around lines 170-186) iterates `plan.photos` and calls `fm.removeItem` on
every source file and its `.xmp`, without consulting whether a copy was made. `executeJob`
(around lines 200-251) has two paths that make no copy but return a success tuple:
`CollisionResolver.resolve` returning `.skip`, and `isSameLocation == true`. When a routed folder
resolves to the source folder (for example base = source with an empty rule, or camera model
`..` with base `source/Sorted`), every file is `.skip` and phase 6 deletes the only copy.
A second site around line 215-217 does `try? fm.removeItem(at: dest)` for `.overwrite`, which
deletes the source when `dest` is the source. `CollisionResolver.resolve` in `FileNaming.swift`
(lines 29-45) never compares `source.standardizedFileURL` with the destination;
`FileNaming.uniqueDestinationURL` (line ~100) does, and `resolve` should mirror it.
`TransferError.sameSourceAndDestination` exists and is never thrown.

**Required changes.**

1. `RoutedTransferService.execute`, phase 0 (where `routingResults` is built from
   `ExportPathRouter.destinationFolders`, around lines 63-72): store each routed folder as
   `folder.standardizedFileURL` so `Sorted/..` compares equal to `Trip`.
2. `RoutedTransferService.execute`, phase 4 (job build, around lines 99-119), before any
   directory is created or file touched: for every job compute
   `job.destinationFolder.appendingPathComponent(job.sourceURL.lastPathComponent).standardizedFileURL`
   and if it equals `job.sourceURL.standardizedFileURL`, throw
   `TransferError.sameSourceAndDestination`. The whole operation must fail before phase 3
   `createDirectory` runs, so move the check ahead of directory creation (reorder phases if
   needed; keep the numbering comments accurate).
3. Make phase 6 delete only sources that were actually copied. Extend the task-group result
   tuple (currently `(Int64, Bool, URL, URL)` = size, sidecarFailed, source, dest) with a
   `copied: Bool` that is `false` for `.skip` and same-location. Collect the set of
   `sourceURL.standardizedFileURL` values with `copied == true`; phase 6 removes a source
   file (and its orphan sidecar) only if it is in that set.
4. `CollisionResolver.resolve` in `FileNaming.swift`: before the hash comparison, if
   `source.standardizedFileURL == originalDest.standardizedFileURL`, return `.skip`. This
   guarantees `.overwrite` can never be returned for the source file itself, so the
   `removeItem(at: dest)` at line ~215 can never delete a source.
5. `PhotoLibraryViewModel`: in the code path that builds a routed plan for `.moveOriginals`
   (`performRoutedOperation`, around lines 1998-2029), refuse a destination whose
   `standardizedFileURL.path` equals, or has as a prefix with trailing `/`, any entry of
   `sourceDirectories`. Set `errorMessage` to
   `TransferError.sameSourceAndDestination.localizedDescription` (or its `errorDescription`)
   and leave `pendingRoutedPlan` nil. Look at the existing prefix comparison near lines
   2560-2565 and reuse the same helper if one exists.

**Tests** (RED first, then GREEN).

`Tests/DuckSortTests/RoutedMoveSafetyTests.swift`, following the shape of
`RoutedSidecarTests.swift` (which already drives `RoutedTransferService.execute` end to end with
`TempDir.make()` and `ImageFixture.writeJPEG`):
- `moveOriginals_baseEqualsSourceWithEmptyRule_throwsAndKeepsSource`: base = source dir, rule
  `[]`, operation `.moveOriginals`; expect `TransferError.sameSourceAndDestination` thrown and
  the JPEG plus its `.xmp` still exist afterwards.
- `moveOriginals_cameraModelDotDot_doesNotDeleteSource`: JPEG fixture with
  `cameraModel: ".."`, base = `source/Sorted`, rule `[.camera]` (or `.cameraModel`); expect a
  throw and the source still exists and no copy was created in `source`'s parent.
  Note: Task 2 will later make `..` sanitize to a fallback name, which changes this test's
  path; write the assertion as "source still exists, and if the transfer did not throw, a copy
  exists at a path different from the source" so it stays valid after Task 2.
- `moveOriginals_alreadyRoutedFile_isNotDeleted`: put the fixture at `dst/X-T5/IMG.jpg` with
  `cameraModel: "X-T5"`, scan that as source, base = `dst`, rule `[.camera]`; expect the file
  survives with identical bytes.
- `copyOriginals_sameLocation_doesNotDeleteOrCorrupt`: same setup with `.copyOriginals`;
  expect a throw (same-location is an error for both operations) and the file unchanged.

`Tests/DuckSortTests/CollisionResolverTests.swift`:
- `resolve_destinationIsSourceFile_neverReturnsOverwrite`: same directory form and
  `dir/../file` form both return `.skip`.
- Pin existing behaviour: `.normal` when no file at destination; `.skip` for an identical copy
  in another directory; `.overwrite` and `.rename` per the existing rules in `resolve`.

A view-model test that `performRoutedOperation(.moveOriginals)` with destination inside a
source sets `errorMessage` and leaves `pendingRoutedPlan` nil, if `PhotoLibraryViewModel` can be
constructed in the test target without a UI (check how existing tests construct it; if none do
and it is not feasible, say so in the report instead of forcing it).

---

## Task 2: Sanitize every routed path component and contain routed output under the base destination

Fixes **Finding 1 (High)** and **Finding 2 (Medium)** in the security review.

**Files:** `DuckSort/Utilities/Transfers/FilenameSanitizer.swift`,
`DuckSort/Models/ExportPathRule.swift`,
`DuckSort/Utilities/Transfers/RoutedTransferService.swift`,
`DuckSort/Utilities/Transfers/FileTransferService.swift` (new `TransferError` case),
`DuckSort/Views/PreFlightVisualizerView.swift`,
new `Tests/DuckSortTests/FilenameSanitizerTests.swift`,
extend `Tests/DuckSortTests/ExportTokenTests.swift` and `Tests/DuckSortTests/RoutedSidecarTests.swift`.

**Problem.** `FilenameSanitizer.clean` replaces `/\:?%*|"<>` with `-` and falls back only on the
empty string, so `..`, `.`, and `...` pass through unchanged. Camera model, lens model, and tag
names (all attacker-controlled via EXIF, XMP, imported tag packs, vCards, and orphaned sidecar
keywords) reach `folder.appendingPathComponent(...)` in `ExportPathRouter.destinationFolders`
with only that sanitizer in between, so each `..` component climbs one level above the chosen
destination. `ExportPathRule.swift:158-164` builds `"No \(categoryName)"` for a `.tagCategory`
with no matching tag using the raw category name with no sanitizer at all, so a slash-bearing
category name from an imported tag pack can descend to an arbitrary absolute path.
`RoutedTransferService.execute` has no check that routed folders stay under
`plan.baseDestination`. `XMPTaggingService.writeExportSidecar` overwrites any existing `.xmp` at
the destination unconditionally. `PreFlightVisualizerView.swift:399-405` has a display-only
`hasPrefix(basePath)` guard that silently draws escaped files as if they were in the destination
root, hiding the problem from the user.

**Required changes.**

1. `FilenameSanitizer.clean`: after the final trim, if the result consists only of `.`
   characters (`.`, `..`, `...`), return `fallback`. Keep everything else unchanged.
   `.customText` passes `fallback: ""` and the router already treats an empty result as "skip
   this level", so this is safe for every caller. Add a comment stating this rejects
   parent-directory components that would escape the export destination.
2. `ExportPathRule.swift` line ~158: replace
   `let categoryName = categoryNameProvider(categoryID) ?? "Uncategorized"` with
   `let categoryName = FilenameSanitizer.clean(categoryNameProvider(categoryID) ?? "", fallback: "Uncategorized")`.
3. Add `case destinationEscapesBase(URL)` to `TransferError` in `FileTransferService.swift`
   with an `errorDescription` in the same style as the existing cases.
4. `RoutedTransferService.execute`: after `routingResults` are computed and before any
   `createDirectory` (Task 1 already standardizes routed folders), verify for every routed folder
   that `folder.standardizedFileURL.path == base || folder.standardizedFileURL.path.hasPrefix(base + "/")`
   where `base = plan.baseDestination.standardizedFileURL.path`. Throw
   `TransferError.destinationEscapesBase(folder)` otherwise. Also apply the same check to the
   sidecar URL computed before `writeExportSidecar` is called.
5. `PreFlightVisualizerView.swift` ~399-405: an escaped path must not be folded into the root.
   Mark it visibly (for example a red "Outside destination" badge or an error row) using the
   existing badge style in that view. Keep the change minimal.

**Tests** (RED first, then GREEN).

New `Tests/DuckSortTests/FilenameSanitizerTests.swift`:
- `clean("..")`, `clean(".")`, `clean("...")`, `clean(" .. ")` each return `"Unknown"` (the
  default fallback).
- `clean("..", fallback: "")` returns `""`.
- `clean("X-T5")` and `clean("Canon EOS R5")` are unchanged.
- `clean("a/b")` returns `"a-b"`; `clean("../x")` returns `"..-x"` (documents that only bare
  dot-only components were the vector).

Extend `Tests/DuckSortTests/ExportTokenTests.swift` (it already exercises
`ExportPathRouter.destinationFolders` for `.camera`, `.lens`, `.tagCategory`):
- `cameraModelDotDot_staysInsideBase`: `MetadataSnapshot(cameraModel: "..")`, rule
  `[.cameraModel, .captureDate]`; every returned folder's `standardizedFileURL.path` has the
  base path plus `/` as a prefix, and the first component is `Unknown Camera` (check the
  fallback string used at that call site and assert the actual value).
- `tagCategory_noMatch_sanitizesCategoryName`: provider returns `"../../../outside/pwn"`, no
  assigned tags; expect last path component `"No ..-..-..-outside-pwn"` and folder inside base.
- `tagCategory_noMatch_nilCategory_fallsBack`: provider returns nil; expect `"No Uncategorized"`.
- `tagCategory_match_dotDotTagName_isNeutralized`: assigned tag named `".."` in that category;
  resulting folder is inside base.

Extend `Tests/DuckSortTests/RoutedSidecarTests.swift`:
- `copyOriginals_cameraModelDotDot_writesUnderBaseAndLeavesParentAlone`: fixture JPEG with
  `cameraModel: ".."`, pre-create `<parentOfBase>/<date>/IMG_0001.xmp` with sentinel content,
  run `.copyOriginals` with `[.cameraModel, .captureDate]`; assert the copy and its sidecar are
  under `base/Unknown Camera/...`, nothing new exists in the parent, and the sentinel `.xmp` is
  byte-identical.
- `execute_routedFolderOutsideBase_throwsBeforeCreatingAnything`: construct a plan whose
  `categoryNameProvider` returns `"../../../escape"` with a `.tagCategory` rule and no matching
  tags. Because the sanitizer now neutralizes it, this will not escape; instead test the
  containment guard directly by building a `RoutedTransferPlan` (or whatever the plan type is
  called) whose routed folders you set manually to a URL outside base if the type allows it,
  and `#expect(throws: TransferError.self)` with no directory created. If the plan type does
  not allow injecting folders, add a small internal `static func verifyContained(_ folders:
  [URL], under base: URL) throws` on `RoutedTransferService`, call it from `execute`, and test
  that function directly. Say which approach you took in the report.

---

## Task 3: Sidecar reads and writes must refuse symlinks and non-regular files

Fixes **Finding 4 (High)** in the security review.

**Files:** `DuckSort/Utilities/Metadata/XMPTaggingService.swift`,
`DuckSort/Utilities/Scanner/FileScanner.swift` (only if its sidecar read path goes through
`XMPTaggingService.readDataFromXMP`; otherwise untouched),
extend `Tests/DuckSortTests/SidecarWriteTests.swift`, `Tests/DuckSortTests/SidecarFailureTests.swift`,
`Tests/DuckSortTests/FileTransferSidecarTests.swift`, `Tests/DuckSortTests/RoutedSidecarTests.swift`,
`Tests/DuckSortTests/FileScannerTests.swift`.

**Problem.** Sidecar URLs are pure string derivations from media filenames
(`XMPTaggingService.xmpSidecarURLs(for:)` lines 111-131 and `exportSidecarURL(for:)` lines
305-307). `.xmp` is not in `FileScanner`'s extension lookup, so sidecars never pass the scanner's
`isRegularFile` filter, and nothing anywhere checks `isSymbolicLink`. `updateSidecarRatingPick`
(lines 215-228) and `updateSidecarCaption` (231-236) do `fileExists` then `String(contentsOf:)`
(follows the link) then `write(to:atomically:)` (rename-over, which replaces the symlink with a
regular file holding what was read). `upsertAttribute` and `mergeDescription` return non-XMP
content unchanged or with a block appended. So a symlink `IMG_0001.xmp -> ~/.ssh/id_ed25519`
in a scanned folder causes one keypress (rating, pick, caption) to write the private key's
bytes into `IMG_0001.xmp`. `writeExportSidecar` (311-329) reads the source sidecar through a
symlink and merges its bytes into the export `.xmp`. `writeSidecar` (139-146) and
`readDataFromXMP` (241) also read through links. Sidecar writes are unconditional on every
rating/pick/caption change; there is no preference gate.

**Required changes.**

1. Add a `SidecarError` enum (or extend an existing error type in `XMPTaggingService.swift` if
   one exists) with `case notRegularFile(URL)` and a `LocalizedError` description that names the
   file and says it is a symlink or special file and was not touched.
2. Add one helper in `XMPTaggingService`:
   ```swift
   /// Sidecar paths are derived from media filenames and never pass through
   /// FileScanner, so an attacker-controlled folder can plant a symlink named
   /// IMG_0001.xmp pointing anywhere on disk. attributesOfItem uses lstat and
   /// does not follow links, so this rejects the link itself.
   nonisolated private static func requireRegularSidecar(_ url: URL) throws {
       let type = try FileManager.default.attributesOfItem(atPath: url.path)[.type] as? FileAttributeType
       guard type == .typeRegular else { throw SidecarError.notRegularFile(url) }
   }
   ```
3. Call it, after the `fileExists` guard and before any read, in: `updateSidecarRatingPick`,
   `updateSidecarCaption`, `writeSidecar` (before the read at ~140 and before the `removeItem`
   at ~143), and `writeExportSidecar` (on `sourceSidecarURL` before reading it, and on the
   destination `url` before writing if a file already exists there).
4. `readDataFromXMP` (~241): if the path exists and is not a regular file, return nil (or the
   empty result that function uses) without reading. Scan-time reads must not follow links.
5. In `updateSidecarRatingPick` and `updateSidecarCaption`, only treat the existing content as
   XMP when it contains `<x:xmpmeta` or `<rdf:Description`. If it does not, do not echo the
   bytes back: throw `SidecarError.notXMP(url)` (add that case) so the caller surfaces it. Do
   not silently overwrite with a fresh packet, because the file may be something the user
   cares about.
6. Confirm the view model surfaces these errors as `errorMessage` on the paths that call
   `updatePermanentTags` and `updateCaption` (it already catches and displays thrown errors;
   verify rather than assume, and quote the catch site in the report).

**Tests** (RED first, then GREEN). Create symlinks with
`FileManager.default.createSymbolicLink(at:withDestinationURL:)` in a `TempDir`.

`SidecarWriteTests.swift`: with `IMG.jpg` (real fixture) and `IMG.xmp -> outside/secret.txt`
(a UTF-8 text file outside the photo folder):
- `updatePermanentTags` throws `SidecarError.notRegularFile`; afterwards
  `attributesOfItem(atPath:)[.type]` is still `.typeSymbolicLink`; `secret.txt` is unchanged.
- Same for `updateCaption` (set a caption, and clear with nil), `applyTagNames` (or whatever
  the tag-write entry point is called), and `clear`.
- A regular `.xmp` still round-trips rating, pick, caption, and tags (positive control).
- A regular file that is not XMP (plain text) makes `updatePermanentTags` throw
  `SidecarError.notXMP` and leaves the bytes unchanged.

`SidecarFailureTests.swift`: the view model sets `errorMessage` when the sidecar is a symlink
(only if the view model is constructible in tests; otherwise note it).

`FileTransferSidecarTests.swift` and `RoutedSidecarTests.swift`: source `.xmp` is a symlink to
an outside UTF-8 file; the exported sidecar does not contain the outside file's bytes and the
transfer reports the sidecar failure the way those tests already assert sidecar failures.

`FileScannerTests.swift`: scanning a folder where the sidecar is a symlink yields empty sidecar
data for that set (no keywords, rating, or caption read through the link).
