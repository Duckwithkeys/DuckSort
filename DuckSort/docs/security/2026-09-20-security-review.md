# DuckSort Security Review — 2026-09-20

Scope: the whole repository at commit `b4ee58e` (not a diff). Method: two independent
code-reading passes over disjoint halves of the app, then one adversarial verification
pass per finding with throwaway Swift probes against real Foundation behaviour. Only
findings verified at confidence 9/10 are listed. No repo files were modified.

Threat model: the attacker controls the *contents* of a folder the user scans (memory
card, shared drive, extracted zip): filenames, EXIF/XMP fields, sidecar files, symlinks.
The attacker can also supply a `.tagpack` or vCard the user chooses to import. The app
is not App-Sandboxed (hardened runtime only, no `.entitlements`), so nothing at the OS
level limits where it reads or writes.

All paths below are relative to `DuckSort/DuckSort/` unless stated. Tests live in
`DuckSort/Tests/DuckSortTests/` and use Swift Testing (`@Test`, `#expect`) with
`TempDir.make()` and `ImageFixture.writeJPEG(to:cameraModel:...)` for real fixtures.

---

## Finding 1 (High): `..` survives `FilenameSanitizer`, routed exports escape the destination

**Status (2026-09-20):** Fixed on branch `wip/security-fixes`, commit `cacaffa`
(sanitizer + lexical containment guard), with a follow-up in `435909e`
(post-creation containment check with symlinks resolved, closing the gap a
lexical check can't see). Pinned by `FilenameSanitizerTests.swift`,
`ExportTokenTests.swift`, `RoutedSidecarTests.swift`, and
`RoutedContainmentTests.swift`.

**Root cause.** `FilenameSanitizer.clean` (`Utilities/Transfers/FilenameSanitizer.swift:9-26`)
replaces `/\:?%*|"<>` with `-` and falls back only on the empty string. A value of `..`
(or `.`, `...`) is returned unchanged.

**Data path.**
- Camera model: EXIF `TIFFModel` (`Utilities/Metadata/MetadataReader.swift:115`) or XMP
  `tiff:Model` (`MetadataReader.swift:417-427`).
- Lens model: EXIF `LensModel` (`MetadataReader.swift:116`).
- Tag names: imported `.tagpack` (`ViewModels/PhotoLibraryViewModel.swift:1538-1549` →
  `Models/TagPackLibrary.swift:233-263`), vCard `FN:` (`Utilities/Metadata/VCardImport.swift:22-24`),
  orphaned sidecar keywords (`Views/Settings/SettingsXMPTagsPane.swift:328-331`).
  `TagStore.addTag` (`Models/TagStore.swift:175`) validates only the hotkey.
- Router: `Models/ExportPathRule.swift` `.cameraModel` 135-139, `.camera` 207-211,
  `.lensModel` 142-146, `.lens` 214-218, `.tagCategory` 161-167, `.primaryTag` 271-275
  each do `folder.appendingPathComponent(FilenameSanitizer.clean(...))`.
- Sink: `Utilities/Transfers/RoutedTransferService.swift` `createDirectory` line 94,
  `copyItem` line 228, sidecar write via `Utilities/Metadata/XMPTaggingService.swift:311-329`
  which `write(to:atomically:)`s with **no** existence check, so any existing `.xmp` at
  the escaped path is overwritten.
- No containment check exists anywhere. The only base-prefix check is display-only in
  `Views/PreFlightVisualizerView.swift:399-405`, which silently draws escaped files as if
  they were in the destination root, hiding the escape from the user.
- The shipped default rule is `[.cameraModel, .captureDate]`
  (`Models/ExportRuleStore.swift:105-112`), so a fresh install is exposed.

**Exploit.** A card holds `IMG_0001.JPG` with EXIF Model `..`. User picks
`~/Pictures/Exports`, keeps the default rule, runs Copy Originals. Output lands in
`~/Pictures/2024-05-01/IMG_0001.JPG` and `~/Pictures/2024-05-01/IMG_0001.xmp` is
replaced. Each attacker-controlled component climbs one level. Probe-confirmed.

**Fix.**
1. `FilenameSanitizer.clean`: after the final trim, if the result consists only of `.`
   characters, return `fallback`. (`.customText` passes `fallback: ""`, which the router
   already treats as "skip this level", so this is safe for every caller.) Optionally
   also strip leading dots to avoid hidden folders.
2. Defense in depth in `RoutedTransferService.execute`, after `routingResults` are
   computed and before phase 3 `createDirectory`: for every routed folder require
   `folder.standardizedFileURL.path == base` or `hasPrefix(base + "/")` where
   `base = plan.baseDestination.standardizedFileURL.path`; throw a new
   `TransferError.destinationEscapesBase` otherwise. Apply the same check to the
   sidecar URL computed in `writeExportSidecar` callers.
3. Fix `PreFlightVisualizerView.swift:399-405` to flag escaped paths rather than fold
   them into the root.

**Tests.**
- New `FilenameSanitizerTests.swift`: `clean("..")`, `clean(".")`, `clean("...")`,
  `clean(" .. ")` return fallback; `clean("..", fallback: "")` returns `""`;
  `"X-T5"`, `"Canon EOS R5"` unchanged; `"a/b"` → `"a-b"`.
- Extend `ExportTokenTests.swift`: `MetadataSnapshot(cameraModel: "..")` and a tag named
  `..`; every returned folder's `standardizedFileURL.path` has base as a directory prefix.
- Extend `RoutedSidecarTests.swift`: fixture JPEG with `cameraModel: ".."`, pre-create
  `<parentOfBase>/<date>/IMG_0001.xmp` with sentinel content, run `.copyOriginals` with
  `[.cameraModel, .captureDate]`; assert output is under `base/Unknown Camera/...`,
  nothing was created in the parent, sentinel unchanged. Add a case where a folder
  would escape and assert the new `TransferError` is thrown before any directory exists.

---

## Finding 2 (Medium): unsanitized category name in the "No <category>" folder

**Status (2026-09-20):** Fixed on branch `wip/security-fixes`, commit `cacaffa`
(sanitize the fallback category name; the Finding 1 containment guard covers
this path too). Pinned by `ExportTokenTests.swift`
(`tagCategory_noMatch_sanitizesCategoryName`,
`tagCategory_noMatch_nilCategory_fallsBack`,
`tagCategory_match_dotDotTagName_isNeutralized`) and `RoutedSidecarTests.swift`.

**Root cause.** `Models/ExportPathRule.swift:158-164`: `.tagCategory` with no matching
tag appends `"No \(categoryName)"` where `categoryName` comes straight from
`categoryNameProvider` with no sanitizer. Slashes and `..` survive, so one component can
climb any number of levels and then descend to an arbitrary absolute location. This is
the only unsanitized attacker-influenced component builder in the file.

**Data path.** `.tagpack` JSON `CategoryEntry.name` (`Models/TagPack.swift:313-315`,
decoded at 442-445) → `TagPackLibrary.importPack` (233-263, copied verbatim) →
`TagStore.applyPackState` (`Models/TagStore.swift:252-278`) → rule editor picker
(`Views/ExportRuleEditorView.swift:200-215`) → `executeRoutedPlan` builds the provider
from `tagStore.categories` (`PhotoLibraryViewModel.swift:2031-2037`). Users can also
type `/` themselves via `Views/TagManagerView.swift:254-259` and
`Views/Settings/SettingsTagsPaneView.swift:511-517`.

**Exploit.** A shared tag pack has a category named
`../../../../../../../../../../Users/victim/Desktop/pwn` (the literal `No ` prefix
consumes the first `..`, so extra `../` are needed; surplus `..` at `/` is a no-op).
User imports it, adds a Tag Category level, runs Move Originals on untagged photos.
Every selected photo plus a generated `.xmp` land in `~/Desktop/pwn/`. Probe-confirmed.

**Fix.** At `ExportPathRule.swift:158`:
```swift
let categoryName = FilenameSanitizer.clean(categoryNameProvider(categoryID) ?? "",
                                           fallback: "Uncategorized")
```
The containment guard from Finding 1 covers this too. Sanitizing at the sink is the
right single point; rejecting on import alone would miss the user-typed path.

**Tests** (in `ExportTokenTests.swift`):
- `tagCategory_noMatch_sanitizesCategoryName`: provider returns `"../../../outside/pwn"`;
  expect last component `"No ..-..-..-outside-pwn"` and folder inside base.
- `tagCategory_noMatch_nilCategory_fallsBack`: provider nil → `"No Uncategorized"`.
- `tagCategory_match_dotDotTagName_isNeutralized`: tag named `..` stays inside base.
- In `RoutedSidecarTests.swift`: provider returns `"../../../escape"`, expect the
  containment `TransferError` and no `escape` directory beside the temp base.

---

## Finding 3 (High): Move Originals deletes sources that were never copied

**Status (2026-09-20):** Fixed on branch `wip/security-fixes`, commits
`24e88c7` and `ff7e527` (same-location guard, phase-6 deletes only copied
sources, `CollisionResolver` same-location early return). A view-model-level
guard added alongside this was later removed in `435909e` as redundant and
overly broad (it blocked sorting a tree into subfolders of itself, a case the
service layer already handles safely); `moveOriginals_alreadyRoutedFile_isNotDeleted`
was also tightened in `435909e` to actually assert the refusal. Pinned by
`RoutedMoveSafetyTests.swift` and `CollisionResolverTests.swift`.

**Root cause.** `Utilities/Transfers/RoutedTransferService.swift:170-186` (phase 6)
iterates `plan.photos` and `removeItem`s every source file and its `.xmp` without
consulting per-job results. Two non-throwing paths in `executeJob` (lines 211-230)
produce no copy yet return a success tuple: `CollisionResolver.resolve` returning
`.skip` (identical hash at destination) and `isSameLocation`. Phase 6 then deletes the
only copy. A second site, line 215-217, does `try? removeItem(at: dest)` on
`.overwrite`, which deletes the source when `dest` *is* the source and hashing failed.

`CollisionResolver.resolve` (`Utilities/Transfers/FileNaming.swift:29-45`) never
compares standardized paths or inodes; when `dest == source`, `fileExists` is true,
hashes trivially match, result is `.skip`. `FileNaming.uniqueDestinationURL` (line 100)
has the same-location check that `resolve` lacks. `TransferError.sameSourceAndDestination`
(`FileTransferService.swift:272`) is defined but never thrown anywhere.

**No guard upstream.** `chooseDestinationDirectory` (`PhotoLibraryViewModel.swift:710-716`)
accepts any folder; `canTransfer` (560) and `performRoutedOperation`/`executeRoutedPlan`
(1998-2078) never compare destination against `sourceDirectories`. Sources and
destination persist across launches (678, 712) and the scanner is recursive. The
pre-flight shows such files as a grey "Skip" badge with no warning that they will be
deleted. Removal is `removeItem`; `trashItem` is not used anywhere; the undo stack
covers only culling state. The non-routed `FileTransferService` move path is **not**
affected (it gates on `!isSameLocation` and uses atomic `moveItem`).

**Triggers.**
- Attacker: EXIF Model `..` with base `~/Pictures/Trip/Sorted` and a Camera-first rule
  routes onto `~/Pictures/Trip`, the source itself. Probe-confirmed: source deleted.
- No attacker: re-run Move Originals over an already-sorted library (source = old
  destination or its parent), or base = source with an empty rule / blank Custom Text
  (`ExportPathRule.swift:171-177`, 128, 281 all yield the base itself).

**Fix.**
1. In `RoutedTransferService.execute` phase 4 (job build, ~99-119), before any
   filesystem write: for every job compute
   `job.destinationFolder.appendingPathComponent(job.sourceURL.lastPathComponent).standardizedFileURL`
   and throw `TransferError.sameSourceAndDestination` if it equals
   `job.sourceURL.standardizedFileURL`. Standardize routed folder URLs at phase 0
   (64-71) so `Sorted/..` compares as `Trip`.
2. Make phase 6 delete only what was copied: extend the task-group result with
   `copied: Bool` (false for `.skip` and same-location), collect the set of source URLs
   with at least one successful copy, and delete only those.
3. `CollisionResolver.resolve`: early-return (new case or `.skip`) when
   `source.standardizedFileURL == originalDest.standardizedFileURL`, so `.overwrite`
   can never delete the source.
4. `performRoutedOperation` / `chooseDestinationDirectory`: for `.moveOriginals`, refuse
   a destination equal to or inside any source directory (prefix check with trailing
   `/`, as done at ~2560-2565) and surface `sameSourceAndDestination`.
5. Consider `trashItem` instead of `removeItem` for source removal.

**Tests** (new `RoutedMoveSafetyTests.swift` and `CollisionResolverTests.swift`):
- `moveOriginals_baseEqualsSourceWithEmptyRule_throwsAndKeepsSource`.
- `moveOriginals_cameraModelDotDot_doesNotDeleteSource` (fixture with `cameraModel: ".."`,
  base `src/Sorted`, rule `[.camera]`).
- `moveOriginals_alreadyRoutedFile_isNotDeleted` (JPEG already at `dst/X-T5/IMG.jpg`).
- `copyOriginals_sameLocation_doesNotDeleteOrCorrupt`.
- `resolve_destinationIsSourceFile_neverReturnsOverwrite` (same dir and `dir/../file`
  forms) plus pins for `.normal`, `.skip`, `.overwrite`, `.rename`.
- View model: `performRoutedOperation(.moveOriginals)` with destination inside a source
  sets `errorMessage` and leaves `pendingRoutedPlan` nil.

---

## Finding 4 (High): sidecar read/write follows symlinks, leaking arbitrary user files into the scanned folder

**Status (2026-09-20):** Fixed on branch `wip/security-fixes`, commits
`4ce3de2` and `1de46d4` (`requireRegularSidecar` lstat guard applied to every
sidecar read/write path, `looksLikeXMP` check before echoing content back).
A remaining gap — `writeSidecar`/`clear` still overwriting or deleting a
regular non-XMP `.xmp` instead of refusing, and `updateSidecarRatingPick`
duplicating `mergeAttributes` without declaring its namespaces — was closed
in `435909e`; that fix exposed a latent, non-deterministic namespace-
declaration collision in `mergeAttributes` itself (`xmlns:xmp` is a literal
substring of `xmlns:xmpDM`), fixed separately in `15995c8`. Pinned by
`SidecarWriteTests.swift`, `SidecarFailureTests.swift`,
`FileTransferSidecarTests.swift`, `RoutedSidecarTests.swift`, and
`FileScannerTests.swift`.

**Root cause.** Sidecar URLs are pure string derivations from media filenames
(`XMPTaggingService.xmpSidecarURLs` 111-131, `exportSidecarURL` 305-307). `.xmp` is
not in `FileScanner`'s `extensionLookup` (`Utilities/Scanner/FileScanner.swift:75-82`),
so sidecars never pass the scanner's `isRegularFile` filter at all. There is no
`isSymbolicLink`, `resolvingSymlinksInPath`, `O_NOFOLLOW`, or lstat-style check on any
sidecar path in the codebase.

`updateSidecarRatingPick` (`XMPTaggingService.swift:215-228`) and
`updateSidecarCaption` (231-236) do `fileExists` → `String(contentsOf:)` (follows the
link) → `write(to:atomically:)` (rename-over, which **replaces the symlink with a regular
file containing what was read**). `upsertAttribute` (571-590) and `mergeDescription`
(392-420) never check for `<x:xmpmeta>`/`<rdf:Description>`; on non-XMP content they
return it unchanged or with a block appended. `writeExportSidecar` (311-329) reads the
source sidecar through a symlink and merges its bytes into the export destination
`.xmp`. `writeSidecar` (139-146) and `readDataFromXMP` (241) also read through links.

**Trigger.** Unconditional. Keys 1-5/0 (`Views/ContentView.swift:430-438`) and pick keys
(452, 574; `Views/Components/LargeImageViewerSidebar.swift:488,512,531`) call
`setRating`/`setPick` (`PhotoLibraryViewModel.swift:1084-1153`), which always spawn
`xmpTagging.updatePermanentTags`; `setCaption` (584-605) → `updateCaption`. There is no
"write sidecars" preference. The read is `try?` (swallowed); the write succeeds, so no
error is shown.

**Exploit.** On a shared drive or in a zip extracted by Archive Utility (symlinks
preserved), attacker places a real `IMG_0001.jpg` beside a symlink
`IMG_0001.xmp -> /Users/<victim>/.ssh/id_ed25519` (or `~/.aws/credentials`,
`~/.config/gh/hosts.yml`, `~/.netrc`, relative `../../../../Users/...`; one link per
photo covers many guesses). User rates the photo; the key's full contents are written
into `IMG_0001.xmp` on the share. Victim's original is untouched. Probe-confirmed
(`NSFileTypeRegular`, bytes identical). Non-UTF-8 targets do not leak: the read throws,
is swallowed, and the sidecar becomes an empty file.

**Fix.** One helper in `XMPTaggingService.swift`, applied at every sidecar read/write:
```swift
/// Sidecar paths are derived from media filenames and never pass through
/// FileScanner, so an attacker-controlled folder can plant a symlink named
/// IMG_0001.xmp pointing anywhere. Refuse to read or write through it.
nonisolated private static func requireRegularSidecar(_ url: URL) throws {
    // attributesOfItem uses lstat and does not follow links.
    let type = try FileManager.default.attributesOfItem(atPath: url.path)[.type] as? FileAttributeType
    guard type == .typeRegular else { throw SidecarError.notRegularFile(url) }
}
```
Call it (after the `fileExists` guard, before any read) in `updateSidecarRatingPick`,
`updateSidecarCaption`, `writeSidecar` (before the read at 140 and the `removeItem` at
143), `readDataFromXMP` (return nil), and `writeExportSidecar` (on the source sidecar
before reading and on the destination before writing). Throw rather than skip so the
view model surfaces it. Additionally, only treat content as XMP if it contains
`<x:xmpmeta` or `<rdf:Description`; otherwise write a fresh packet instead of echoing
bytes back.

**Tests.**
- `SidecarWriteTests.swift`: `IMG.xmp -> outside/secret.txt`; `updatePermanentTags`,
  `updateCaption` (set and clear), `applyTagNames`, `clear` each throw, the path is still
  a symlink afterward (`attributesOfItem[.type] == .typeSymbolicLink`), `secret.txt`
  unchanged.
- `SidecarFailureTests.swift`: view model sets `errorMessage`; symlink-to-binary also
  throws instead of writing an empty file.
- `FileTransferSidecarTests.swift` and `RoutedSidecarTests.swift`: source `.xmp` is a
  symlink to an outside file; export sidecar does not contain its bytes and the transfer
  reports `sidecarFailed`.
- `FileScannerTests.swift`: `readSidecarData(from:)` returns empty for a symlinked sidecar.
- Positive: a real regular `.xmp` still round-trips.

---

## Suggested work split for fix agents

Findings 1, 2 and 3 all touch `RoutedTransferService.swift`; run those as one sequential
task or accept merge work. Finding 4 is independent.

| Task | Findings | Files | Approx. size |
|------|----------|-------|--------------|
| A. Sanitizer + containment guard | 1, 2 | `FilenameSanitizer.swift`, `ExportPathRule.swift`, `RoutedTransferService.swift`, `PreFlightVisualizerView.swift`, `FileTransferService.swift` (error case), tests | ~150 lines + ~120 lines tests |
| B. Move safety | 3 | `RoutedTransferService.swift`, `FileNaming.swift`, `PhotoLibraryViewModel.swift`, tests | ~120 lines + ~200 lines tests |
| C. Sidecar symlink guard | 4 | `XMPTaggingService.swift`, `FileScanner.swift` (read path), tests | ~60 lines + ~150 lines tests |

Each task: write failing tests first, then the fix, run `swift test` from `DuckSort/`,
and confirm output is clean. Do not weaken or delete existing tests.

## Sinks examined and found safe

- No `Process`, `NSTask`, `NSAppleScript`, `osascript`, or shell invocation in app code;
  `package_app.sh` and `create_dmg.sh` take no untrusted input.
- No `XMLParser`/`XMLDocument`; all XMP parsing is regex over strings, so no XXE.
- XMP writes escape `& < > "` via `XMPTaggingService.escape`; element and attribute
  names are constants. Regex replacement templates do expand `$0`/strip `\` in tag
  names, but the only re-injectable text is the sidecar's own matched block (Low, not
  reported; fix with `NSRegularExpression.escapedTemplate(for:)` if desired).
- Deserialization is `JSONDecoder` into plain `Codable` structs; no `NSKeyedUnarchiver`.
  Decoded `systemImage`, `accentColor`, `hotkey` are validated at use.
- `NSWorkspace.shared.open` is used only on scanned media URLs chosen by extension
  allowlist, with the target app resolved by fixed bundle id.
- `FileScanner` requires `isRegularFile` for media and does not descend into symlinked
  directories; `copyItem` copies links rather than targets.
- `DiskThumbnailCache` filenames are SHA-256 of the path under `~/Library/Caches`.
- Logs contain only counts, `lastPathComponent`s, directory paths and error text; no
  captions, keywords, contact fields or vCard names.
- Non-routed `FileTransferService` move path guards same-location and uses atomic
  `moveItem` with no separate delete pass.

## Residual risks

- **TOCTOU between the lstat guard and the open.** `requireRegularSidecar`
  (Finding 4) checks `attributesOfItem` (lstat, doesn't follow links) and then
  a later, separate call opens the path for read or write. An attacker who
  can race the filesystem on the user's own machine — swap a regular file for
  a symlink between the check and the open — can still redirect that open.
  Closing this needs `open(2)` with `O_NOFOLLOW` (or `NSFileHandle` built from
  such a descriptor) so the same syscall that opens the file also refuses to
  follow a link, instead of a separate stat beforehand. Not fixed on this
  branch: it requires an attacker already racing a process on the victim's
  machine, a much narrower threat than the drive-by folder/zip scenarios the
  other findings cover.
- **Containment checks resolve symlinks only after directory creation.** The
  Finding 1 fix (commit `435909e`) re-checks routed folders with
  `resolvingSymlinksInPath()` after `createDirectory` runs, because a
  pre-creation lexical check cannot see a symlink that doesn't yet resolve to
  anything walkable. An attacker who can already write inside the chosen
  destination can still cause an empty directory to be created at the
  symlink's target before the resolved check throws and aborts the
  operation — nothing is copied, moved, or overwritten there, but the empty
  directory itself is a side effect the pre-creation check alone can't
  prevent.
