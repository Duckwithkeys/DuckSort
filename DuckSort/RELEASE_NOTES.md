# DuckSort v1.0.0 Release Notes

Welcome to version **1.0.0** of **DuckSort**! This is the first official release of the application, introducing comprehensive performance optimizations across on-device AI Neural Engine inference and photo rendering pipelines, native Xcode project integration (`DuckSort.xcodeproj`), and robust file organization, tagging, and routing controls.

---

## 📥 Download & Installation

1. Download the **`DuckSort.dmg`** file from the assets on our [GitHub Releases page](https://github.com/Duckwithkeys/DuckSort/releases).
2. Double-click the downloaded `.dmg` file to mount it.
3. Drag the **DuckSort** app into your `Applications` folder.
4. Launch the app from Launchpad or your Applications folder!

### 🛠️ Developer Setup & Builds
If you'd like to build the project from source:
* **Clone via Git**:
  ```bash
  git clone https://github.com/Duckwithkeys/DuckSort.git
  ```
* **Xcode**: Open **`DuckSort.xcodeproj`** and press `Cmd + R` to build and run.
* **Terminal**: Run `swift run` in the root project directory.

## 🛠️ Requirements
* **macOS 14.0 (Sonoma)** or newer.

---

## ✨ Features & What's New in v1.0.0



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

