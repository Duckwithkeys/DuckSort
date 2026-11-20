# Changelog

All notable changes to DuckSort are documented here. This project follows [Semantic Versioning](https://semver.org/) and [Keep a Changelog](https://keepachangelog.com/) conventions.

---

## [v1.0.0] — 2026-07-29

Welcome to the first official release of DuckSort. This version introduces comprehensive performance optimizations across on-device AI Neural Engine inference and photo rendering pipelines, native Xcode project integration (`DuckSort.xcodeproj`), and robust file organization, tagging, and routing controls.

### 📥 Download & Installation

Download the `DuckSort.dmg` from the [GitHub Releases page](https://github.com/Duckwithkeys/DuckSort/releases). Double-click the `.dmg`, drag DuckSort into Applications, and launch.

### Key Features at v1.0

| Area | Highlights |
|---|---|
| **🛡️ Resilient Error Handling & Core Health** | Two-tier thumbnail cache (memory LRU + disk JPEG, 500 MB budget); structured `AppLogger` subsystem logging; SwiftUI `ErrorBoundaryView` for graceful failure; dismissable grid error banners; adaptive metadata batching; memory-pressure auto-eviction. |
| **🧠 On-Device AI Neural Engine** | Persistent `VNClassifyImageRequest` / `VNDetectHumanBodyPoseRequest` keeping ANE weights warm; background-thread inference routes; downsampled (1024 px) face detection — RAM down 150 MB → ~3 MB per image, 5× throughput boost. |
| **⚡ Photo Rendering & Metal** | Persistent `CVMetalTextureCache` eliminating per-frame texture allocation; high-DPI Retina pixel budgeting in `ThumbnailView`; fast ImageIO fallback for HEIF; dynamic RAM-adaptive large-image cache (up to 600 MB on 32 GB+ systems). |
| **📊 EXIF Analytics Dashboard** | Canvas-based animated chart sheets — focal length, aperture, ISO, shutter speed distributions. Top camera + lens combos with frequency and pick ratios. |
| **🎨 Photomator Integration** | One-click "Edit" button overlay + global hotkey `E` on the large photo viewer launching directly into Photomator. |
| **🎛️ Speed Culling & Haptics** | Configurable auto-advance sound / trackpad haptics; triple-pulse mechanical tactile vibration sequence. |
| **🧭 Unified Header Navigation** | Edge-to-edge grid (removed redundant `TransferFooter`); unified top toolbar with destination, routing rules, copy/move triggers; full-window overlay large viewer. |
| **🛠️ Native Xcode Build Tooling** | Standalone `DuckSort.xcodeproj` (via XcodeGen) alongside the Swift package build. |
| **🎨 Tag Packs Overhaul** | Single-column resizable tag editor (960×720); inline swatch color picker on every `TagChip`; 50+ SF Symbol icon catalog. |
| **📁 Files-in-Set Inspector** | Viewer sidebar showing RAW / JPEG / HEIF / sidecar role breakdown with colored chips; reveal-in-Finder and copy-filename actions. |
| **🔍 XMP Tag Inspector Overlay (⌘⇧X)** | Floating scan panel reading undocumented keywords from XMP sidecars; one-click optimistic tag import into active packs. |
| **🏷️ Smart Photo Grouping** | Dynamic sidecar pairing (RAW + HEIF + JPEG + .photo-edit); automatic XMP export on copy/move with full EXIF / IPTC preservation. |
| **⚙️ Performance & Engine Retuning** | O(1) dictionary subscripts replacing linear scans; precompiled regex in `XMPSchema`; collapsed filter loops; capped file concurrency at 16; zero-memory (should-not-cache) EXIF during scans. |

---

## [v1.1.0] — 2026-10-13

Small but meaningful polish release on top of v1.0 — focusing on **security**, **grid ergonomics**, and **visual polish**. No feature bloat; just the things that kept us up at night.

### 🔒 Security Hardening

| What | Why | Impact |
|---|---|---|
| Refuse symlinked or non-XMP sidecar files | Prevent symlink traversal attacks on untrusted photo folders | Sidecar writes are now safe against external links pointing to arbitrary paths |
| Resolve symlinks after directory creation + contain routed output | Prevent "escape the destination" attacks via symlinks in the target folder tree | Files can no longer be written outside the chosen export destination |
| Sanitize dot-only path components (`.` and `..`) | Mitigate ambiguity in path canonicalization | Cleaner, safer relative paths during routing |
| Re-check sidecar containment post-move (round 1) | Ensure sidecars land inside the destination even when nested folders have symlinks | Sidecar safety verified after the fact, not just before |
| Fix non-deterministic namespace collision in `mergeAttributes` | Set-based merging of XMP attributes could produce different output across runs | Deterministic metadata export — sidecars are identical on re-runs |
| Stop Move Originals from deleting uncopied sources | A copy-only transfer shouldn't also remove the source file | Move Originals mode now correctly only moves what it copied |

**Residual risks**: We still trust directory listings for photo scanning. If a folder contains thousands of symlinks, `readdir` performance may degrade. Mitigation: add an optional `.ducksortignore` to exclude large or suspicious trees (tracking issue open).

### 🧭 Grid & Sort UX

| What | Why |
|---|---|
| Unified single sort dropdown in the top window toolbar and macOS menu bar | Collapsed a scattered set of corner icons, header buttons, and popover menus into one coherent control. One click → choose Date / Name / Size / Custom Rules. |
| Grid view header with compact sort menu icon (`⚤`) | Replaced the redundant header bar entirely. The grid is now fully edge-to-edge with maximum vertical space for thumbnails. |
| Sort by date, name, and file size controls in grid view header + filter popover | Inline sorting and filtering without leaving your workflow. No more popping out a separate settings dialog to sort. |
| Hide the dropdown chevron arrow indicator on the sort toolbar button | Visual polish — macOS-native menus don't show nested chevron indicators. Looks cleaner, reads better. |

### 🎨 Appearance & Assets

| What | Why |
|---|---|
| Dynamic dark/light dock icon switching | The dock icon now automatically swaps between dark and light variants matching your macOS appearance setting. Settings selector in the Preferences pane. |
| New 3D duck artwork for `AppIcon.icns` | Fresh visual identity — updated gradient background, rendered with proper alpha channel support. |
| Configure DMG volume icon | The mounted disk image now shows a custom DuckSort icon instead of the generic computer graphic. |
| Standardize dock icon scaling, squircle radius, shadow | Adheres to macOS human-interface guidelines for icon rendering under the magnifying glass. |

### ⚙️ Fixes & Improvements

| Category | What | Why |
|---|---|---|
| **Concurrency** | Isolated dock icon notification handling to `@MainActor` Task | Race condition between background thread updates and main-thread UI could cause a crash on status change. |
| **Lifecycle** | Prevent `dispatch_once` deadlock in `appIconStyle` loading | A circular initialization dependency caused the app to freeze on launch if called from a background queue. |
| **Onboarding** | Cleaned up outdated EXIF references, polished navigation tour links | The first-run walkthrough mentioned deprecated features and dead links. |
| **Documentation** | Rewrote README for clarity and usability | Original README was a wall of text. Now structured with Quick Start, Core Features, Keyboard Shortcuts, and Build sections. |

---

## [v1.3.0] — 2026-11-20

Full-system stability, privacy, and performance release — fixing critical crash, data-loss, and UI-freeze bugs uncovered across the entire codebase, plus major scrolling, transfer, and metadata optimizations.

### 🛡️ Critical Fixes & Data Safety

| Area | What Changed |
|---|---|
| **XMP Sidecar Engine** | Fixed guaranteed `NSRangeException` crash in `XMPTaggingService.mergeDescription` when updating or clearing captions on existing sidecars; fixed malformed `<<rdf:Description` output on self-closing tags; escaped `$0`/`$1`/`\` regex backreferences in tag names and IPTC fields; replaced per-process `Set.hashValue` with deterministic SHA-256 hashing for `xattr` freshness checks. |
| **EXIF Privacy Sanitizer** | Fixed `EXIFSanitizer.sanitizeImage` to set `kCFNull` (instead of `removeValue`) so ImageIO actually strips GPS coordinates and camera/lens serial numbers when exporting. |
| **Safe File Transfers** | Deferred orphan `.xmp` deletion in `FileTransferService` until after all jobs finish (preventing RAW+JPEG sibling races and never deleting source sidecars on write failure); made `RoutedTransferService` `.overwrite` copy to a temp sibling and atomically replace; added pre-creation ancestor symlink containment checks before `createDirectory`. |
| **Concurrency & Crashes** | Eliminated potential double-resume crash in `FaceClusteringService.detectFaces`; fixed cross-string `String.Index` crash risk in subfolder filtering; moved synchronous XMP sidecar I/O and `PreFlightVisualizerView` simulation off `@MainActor`. |
| **Keyboard Focus Isolation** | Prevented the global keyboard monitor in `ContentView` from firing culling actions on the background grid while Settings, Activity Console, Onboarding, or modal sheets are active; required plain (unmodified) keys for `0–5`, `z`, `x`, `u`; fixed inverted `[` / `]` category cycling. |

### 🐛 Bug Fixes

- **Metadata & EXIF:** Properly apply GPS `S`/`W`/below-sea-level signs; fixed scrambled EXIF flash mode bitmask (`0x18`); fixed XMP fallback parsing for `exif:FocalLength`, APEX `ApertureValue` (`2^(Av/2)`), and `flashFired`.
- **Insights Dashboard:** Fixed focal length and aperture bucket boundaries so fractional zoom focal lengths (e.g., `24.5mm`, `50.2mm`) and `f/2.8` are categorized accurately; collapsed 7 passes into a single pass.
- **Folder Indexing & Scanning:** Added `"/"` path boundary checks in `FolderTreeIndex` so sibling folders with shared prefixes never false-match; caught per-file `resourceValues` errors in `FileScanner` so one unreadable file won't abort a scan; classified `.raw`, `.avif`, `.heics`, and `.heifs` accurately.
- **ViewModel & Undo/Redo:** Fixed `rejectAndAdvance` stale-index bug; cleared `CullingUndoManager` and caches on scan/clear; fixed task cancellation guards and weak `self` captures; fixed `PhotoIndexStore` stale rating/pick entries on re-index.
- **Settings & UI:** Fixed Contact vCard import prompting for the file twice; fixed `OnboardingFlow` marking source picked when cancelled; refreshed `FolderTreeNode` when library contents change; preserved Settings tab state on re-focus; fixed `UserPreferences` overwriting defaults on first launch and re-saving during `clear()`; allowed modifier combos in `TagHotkeyRules.reservedReason`; removed dangling `⇧⌘X` shortcut row; fixed `IOSurfaceMetalRenderer` ARGB histogram channel order.

### ⚡ Performance Optimizations

- **Faster Transfers:** `CollisionResolver.resolve` now stats and compares file sizes before streaming SHA-256 hashes (skipping hashing on size mismatch); IPTC preferences are read once per transfer plan instead of per file.
- **Parallel Metadata:** `MetadataReaderActor.batchMetadata` now runs in bounded parallel chunks off-actor instead of serializing onto a single actor; guarded UTF-8 XMP fallback against loading >1 MB corrupt binary files into RAM.
- **Smoother Scrolling & UI:** Eliminated `@Published` spam in `ScrollStateObserver`; stopped `PhotoSetCell` `.onHover` from triggering 3072px full-res decodes; gated `.trace`/`.debug` logs out of `@MainActor` `LogConsoleStore` hops; coalesced `tagStore.objectWillChange` refreshes; broke recursive `sortOption`/`sortOrder`/`sortDirection` `didSet` cascade; cached `DateFormatter` instances in `LargeImageViewerSidebar` and `LogConsoleView`.
- **Disk & Scanner I/O:** `DiskThumbnailCache` now encodes JPEG directly via ImageIO `CGImageDestination` (avoiding TIFF round-trips) and tracks overwrite sizes accurately; `FileScanner` reads prefetched `resourceValues` before standardizing URLs; `PhotoIndexStore` pre-normalizes feature prints for single-`vDSP_dotpr` cosine similarity; batched `TagStore.ensureTags(named:)`.

### 🧪 Testing & Build

- Added `AuditRegressionTests` (10 new tests) bringing the suite to **110 tests across 21 suites** — all passing.
- Excluded `Info.plist` in `Package.swift` for clean, zero-warning `swift test` builds.
- Extracted `CullingUndoManager`, `FolderTreeIndex`, and `InsightsCalculator` from `PhotoLibraryViewModel`.

---

### How to Upgrade

1. Open DuckSort → Preferences → check for updates (or download from GitHub Releases).
2. No migration needed — your existing tag packs, rules, and settings carry over seamlessly.
