# DuckSort v1.4 Release Notes

Welcome to version **1.4** of **DuckSort**! Since our last major release (v1.3), we have completely re-engineered the application's core health, UI layout, cache handling, error recovery, on-device AI Neural Engine inference, and Metal graphics acceleration pipelines. This version also ships with native Xcode project integration (`DuckSort.xcodeproj`).

Because v1.3.5 was a development tag, **v1.4** serves as the official release containing all updates, features, and optimizations developed since v1.3.

---

## 📥 How to Download & Run

You can download and run **DuckSort** in a few simple steps:

### 1. Clone via Git (For Developers)
If you have Git installed, run the following command in your terminal to download the codebase:
```bash
git clone https://github.com/Duckwithkeys/DuckSort.git
```

### 2. Download as a ZIP Archive
If you do not have Git:
1. Visit the [DuckSort GitHub Repository](https://github.com/Duckwithkeys/DuckSort).
2. Click the green **Code** button at the top right.
3. Choose **Download ZIP** and extract the downloaded file.

### 🚀 Getting Started
Once downloaded:
* **Xcode**: Double-click **`DuckSort.xcodeproj`** in the `DuckSort` directory to open the project in Xcode. Click the **Run** button (`Cmd + R`) to build and start.
* **Terminal**: Open the `DuckSort` folder in terminal and run `swift run`.

---

## ✨ What's New in v1.4 (Including All Updates Since v1.3)


### 1. 🛡️ Resilient Error Handling & Core Health
* **Two-Tier Cache System**: Introduced `DiskThumbnailCache` to provide a robust two-tier (memory LRU + disk) thumbnail cache. Thumbnails are cached to the disk (`~/Library/Caches/com.ducksort/thumbnails/`) as JPEG formats, managing a strict 500 MB budget to prevent high-res uncompressed image RAM bloat.
* **Structured Subsystem Logging**: Added `AppLogger` wrapping Apple's unified `os.Logger`, partitioning logs cleanly into subsystems (`thumbnails`, `metadata`, `transfer`, `ui`). Includes support for `PerformanceSignpost` using `OSSignposter` intervals for detailed profiling inside Instruments.
* **SwiftUI UI Error Boundaries**: Added `ErrorBoundaryView` to wrap child view hierarchies and gracefully handle runtime task throwing, providing a fallback retry interface rather than crashing the view.
* **Dismissable Grid Error Banners**: Built `GridErrorBannerView` to alert users of top-level folder parsing or loading issues dynamically, replacing intrusive raw alert popups.
* **ViewModel Memory & Layout Enhancements**:
  * Implemented adaptive metadata batching (`metadataBatchSize = 150`) to progressively populate the UI during library load.
  * Added system memory pressure monitoring to auto-evict caches on `.warning` or `.critical` levels.
  * Suspended neighbor preloading when scrolling via the `ScrollStateObserver` to reserve I/O bandwidth and thread queues for active cells.
  * Gated published changes in ViewModels to skip rendering if the filtered photo array elements remain unchanged.

### 2. 🧠 On-Device AI Neural Engine & Vision Optimization
* **Persistent Vision Model Requests**: Reusable, persistent `VNClassifyImageRequest` and `VNDetectHumanBodyPoseRequest` in `VisionEngineActor` keep Apple Neural Engine weights warm in VRAM, eliminating neural net graph compilation overhead on each frame.
* **ANE Processing Route**: Enforced background thread processing routes (`preferBackgroundProcessing = true`) to direct Vision inference tasks directly to dedicated Apple Silicon Neural Engine cores, avoiding CPU thrashing.
* **Downsampled Face Detection & Clustering**:
  * Throttled face detection scanning queues with a strict concurrent `AsyncSemaphore(limit: 8)` task coordinator.
  * Extracted downsampled 1024px thumbnails for face detection instead of full-size RAW files, dropping RAM footprint from 150MB+ down to ~3MB per image and boosting throughput by 5x.

### 3. ⚡ Photo Rendering & Metal Graphics Acceleration
* **Persistent Metal Texture Cache**: Converted `IOSurfaceMetalRenderer` to use a persistent `CVMetalTextureCache` initialized once at startup instead of creating and destroying texture caches on every frame, eliminating texture allocation latency. Added a thread-safe `flush()` capability.
* **High-DPI Retina Pixel Budgeting**: Adjusted ImageIO thumbnail pixel calculations in `ThumbnailView` to explicitly account for Retina display scale factors (`maxPixels = size * scale`), rendering ultra-sharp 1200px Retina thumbnails on 2x/3x displays.
* **Fast ImageIO Fallback for HEIF**: Enhanced `loadWithImageIOFallback` to attempt ImageIO thumbnail generation prior to full bitmap decodes, avoiding unnecessary uncompressed image allocations for HEIF files.
* **Dynamic RAM-Adaptive High-Res Caching**: Configured `LargeImageCacheWrapper` in `LargeImagePane` to scale count and cost limits dynamically based on physical RAM (up to 600MB on 32GB+ systems).

### 4. 📊 Camera & Lens Performance Insights (EXIF Analytics)
* **Interactive Chart Dashboard**: Added an EXIF analytics dashboard sheet (`chart.bar.xaxis`), complete with SwiftUI Canvas-based animated charts depicting Focal Length, Aperture, ISO, and Shutter Speed distributions.
* **Top Gear Combinations**: Automatically analyzes and displays camera and lens combinations, occurrence frequency, average aperture, and pick ratios.

### 5. 🎨 Photomator Integration & Custom Handoff
* **One-Click Launch**: Added an **Edit** button overlay and global hotkey `E` on the large photo viewer.
* **Handoff Action**: Directs the active RAW or high-res image directly into Photomator (`com.pixelmatorteam.pixelmator.touch.x.photo`) for seamless editing workflows.

### 6. 🎛️ Speed Culling (Auto-Advance) & Strong Haptics
* **Custom Speed Culling Settings**: Configurable Auto-Advance sound effects, trackpad haptic triggers, and custom hotkey bindings in the settings panel.
* **Mechanical Haptic Click Sequence**: Implemented a triple-pulse mechanical tactile vibration using a sequence of trackpad `.levelChange` and `.alignment` bursts in a 30ms queue.

### 7. 🧭 Unified Header Navigation & Interface Refinements
* **Edge-to-Edge Grid**: Removed the redundant bottom `TransferFooter` panel and subheadings to maximize grid thumbnail vertical space.
* **Unified Toolbar**: Integrated Destination Selection, Export Routing Rules, Copy/Move triggers, and active checkmarks for selected photo counts directly into the top window bar.
* **Full-Window Overlay Viewer**: Configured `LargeImageViewer` to support `.ignoresSafeArea()` extending across titlebars, with a 54pt top clearance.

### 8. 🛠️ Native Xcode Build Tooling
* **Standalone Project Configuration**: Added a standalone `DuckSort.xcodeproj` Xcode project (generated via XcodeGen `project.yml`) alongside an explicit `Info.plist` app bundle manifest.
* Supports building, testing, and debugging directly via Xcode or using standard command-line `xcodebuild` tools.


---

# DuckSort v1.3 (Tag Packs Redesign, Files-in-Set Inspector, HEIF Previews, Major Performance Pass)

Welcome to version 1.3 of **DuckSort**! This release overhauls the Tag Packs settings UI, introduces a "Files in Set" inspector in the large viewer, brings full HEIF/HEIC preview support, adds an XMP tag inspector overlay, and ships a sweeping performance pass that retunes 25 hot paths across the codebase for O(1) lookups, single-pass filters, and pre-compiled regexes.

## ✨ What's New in v1.3
* **Tag Packs Settings Overhaul**:
  - Removed the left "Categories" sidebar — the Tags pane is now a single full-width column so the pack strip sits cleanly above the inline editor.
  - Settings window is resizable and starts at 960×720 (was 720×480) so multi-monitor users can keep the pack library visible while editing.
  - **Per-tag inline color picker** on every `TagChip` — click the swatch and the native macOS color panel opens directly, no nested menu.
  - **SF Symbol picker for tag-pack logos** — choose from a curated catalog of 50+ symbols grouped by People, Moments, Activities, Objects, and Tech, or type any SF Symbol name to use one not in the catalog.
* **Large Viewer "Files in Set" Inspector**:
  - Replaces the old "N files + edit" summary with a real per-file list showing every file that belongs to the set.
  - Each row shows the actual filename (e.g. `DSCF0142.RAF`, `DSCF0142.JPG`, `DSCF0142.HEIC`, `DSCF0142.photo-edit`) with a colour-coded role chip — red for RAW, green for JPEG, indigo for HEIF, yellow for the edit sidecar.
  - Right-click any row to **Reveal in Finder** or **Copy Filename**.
  - **Format bug fix**: A RAW + HEIF set now correctly reports `formatLabel = "RAW + HEIF"` (it was silently classified as RAW-only before, because HEIF extensions also live in `rawLikeExtensions` and the `if/else if` chain checked RAW first).
* **HEIF/HEIC Preview Support**:
  - `CGImageSourceCreateThumbnailAtIndex` returns nil for some HEIC bursts and unusual orientation metadata — added a `NSImage(contentsOf:)` fallback path that uses the system codec, then down-samples to the requested pixel budget.
  - HEIF files now reliably decode on first try, and the thumbnail `previewRank` puts them ahead of RAW so a set without a JPEG sibling shows the HEIF as its preview.
* **XMP Tag Inspector Overlay**:
  - **View → "XMP Tags Not in Active Pack…"** opens a floating overlay window (`⌘⇧X`) that scans every loaded photo's sidecar and lists any `dc:subject` keywords not defined as a tag in the active pack.
  - Each row shows the orphan keyword, the count of photos using it, and example filenames.
  - One-click **Add to Pack** writes a new tag into the active pack (preferring the `Subject` category) and rescans. The row disappears immediately via optimistic local update — no waiting for the full rescan.
* **Sidebar Tag Filter Refinements**:
  - The "Active Filters" bar is now permanent at the top of the sidebar's filter stack (under the search field), so the layout doesn't shift when filters are toggled.
  - When zero filters are active, the bar renders a grayed-out "No active filters" state with a disabled Clear button.
* **Keyboard Improvements**:
  - **Press `I` in the grid** to open the large image viewer (was: toggled the Inspector panel).
  - All other shortcuts unchanged.
* **Tag Chip Visual Improvements**:
  - Per-tag color picker styled as a prominent pill so it reads as the primary action, not a hidden nested menu.
  - Format pills on grid cells use a consistent palette (`RAW` = red, `JPEG` = green, `HEIF` = indigo, `EDIT` = yellow) shared with the large viewer so both surfaces agree on what each colour means.
