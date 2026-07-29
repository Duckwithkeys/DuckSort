# 🦆 DuckSort

A native macOS application designed to automate the workflow of scanning, organizing, tagging, and routing photo sets. It groups RAW files, JPEGs, HEIFs, and sidecar files (such as Photomator edits) into unified sets, allowing you to manage and export them efficiently using customizable routing rules.

DuckSort matches the flat, dark professional aesthetic of modern photo editors like **Photomator**, adapting natively to macOS system-wide Light and Dark mode preferences.

---

## ✨ Features (v1.4)

- **🛡️ Core Health & Resilient UI**:
  - **Two-Tier Disk Caching**: Stores decoded thumbnails as JPEGs inside a persistent `DiskThumbnailCache` (`~/Library/Caches/com.ducksort/thumbnails/`), enforcing a strict 500 MB limit to prevent RAM bloat.
  - **Structured Subsystem Logging**: Scoped loggers (`AppLogger.thumbnails`, `.metadata`, `.transfer`, `.ui`) built on Apple's unified `os.Logger` framework with `OSSignposter` intervals for profiling.
  - **Resilient UI Error Boundaries**: Gracefully catches child task failures and renders interactive retry banners via `ErrorBoundaryView` and `GridErrorBannerView` rather than crashing the interface.
  - **Memory & Scroll Tuning**: Monitors OS memory pressure warning levels to auto-evict caches, and skips neighbor preloading during active scroll states to eliminate rendering hitching.
- **🧠 On-Device AI Neural Engine (ANE) Auto-Tagging**:
  - **Persistent Request Warmups**: Reuses `VNClassifyImageRequest` and `VNDetectHumanBodyPoseRequest` in `VisionEngineActor` to eliminate graph compile overhead and keep model weights warm in VRAM.
  - **Direct ANE Execution**: Enforces background execution priorities (`preferBackgroundProcessing = true`) to dispatch Vision inference directly to Neural Engine cores.
  - **Optimized Face Clustering**: Throttles clustering queues with an `AsyncSemaphore(limit: 8)` and processes downsampled 1024px face crops instead of full 80MP RAW files, saving over 140MB RAM per image and boosting throughput by 5x.
- **⚡ Metal GPU Graphics & Photo Rendering**:
  - **Persistent Metal Cache**: Initializes `CVMetalTextureCache` once at startup in `IOSurfaceMetalRenderer`, eliminating allocations during frame updates.
  - **High-DPI Retina Scaling**: Computes thumbnail sizes based on screen scale (`maxPixels = size * scale`) to yield sharp 1200px thumbnails on 2x/3x Retina displays.
  - **Adaptive RAM Cache**: Adjusts high-resolution canvas memory budgets dynamically based on physical system RAM (up to 600MB on 32GB+ configurations).
- **📊 Camera & Lens Insights (EXIF Analytics)**: Canvas-based fluidly animated charts depicting Focal Length, Aperture, ISO, and Shutter Speed distributions, plus "Top Gear" lens pairing efficiency metrics.
- **🎨 Photomator Integration**: Instantly launch Photomator (`com.pixelmatorteam.pixelmator.touch.x.photo`) and load the active RAW/image directly via global hotkey `E` or the viewer's glassmorphic edit button.
- **🎛️ Speed Culling & Strong Haptics**: Auto-advance culling speed preferences, custom global hotkeys, and triple-pulse trackpad haptic triggers (`.levelChange` + two `.alignment` pulses).
- **🧭 Unified Toolbar Navigation & Edge-to-Edge Grid**: Toolbar-integrated routing rules, destinations, and selections with green status checkmarks. Complete removal of bottom footer spacing to yield an edge-to-edge layout.
- **🛠️ Native Xcode Tooling**: Standalone `DuckSort.xcodeproj` Xcode project (generated via XcodeGen) alongside `Info.plist` bundle manifests for direct native debugging, testing, and profiling.
- **Smart Photo Grouping**: Automatically pairs RAW files with their JPEG/HEIF derivatives and sidecar files (e.g., `.photo-edit`) into unified photo sets.
- **Vast RAW & Image Format Support**: All major raw formats (Fuji `.raf`, Sony `.arw`, Canon `.cr2`/`.cr3`, Nikon `.nef`, Adobe `.dng`, etc.) and standard HEIF/HEIC/JPEG files.
- **HEIF Preview Decoding**: Falls back to native codecs when `CGImageSourceCreateThumbnailAtIndex` fails (bursts/orientations), ensuring HEIF files render correctly on the first attempt.
- **Large Viewer "Files in Set" Inspector**: Detailed sidebar listing of RAW, JPEG, HEIF, and edit sidecars with color-coded role chips, Reveal in Finder, and Copy Filename actions.
- **XMP Tag Inspector Overlay (`⌘⇧X`)**: Floating overlay window that detects undocumented XMP subject keywords in sidecars and imports them directly into active packs with one click.
- **Tag Packs Overhaul**: Resizable single-column settings layout with custom color pickers and a catalog of 50+ SF Symbols for tag logos.
- **Pre-Read Metadata Flow**: EXIF metadata read once at scan time flows through to the transfer pipeline via `TransferPlan.metadata` — no redundant per-transfer `CGImageSource` reads.
- **Robust Metadata Preservation**: Writes an `.xmp` sidecar beside copied/moved files recording custom tags, rating, flag status, capture metadata (camera, lens, ISO, shutter, aperture), and IPTC creator/copyright/contact info when enabled.
- **High-Resolution Viewer & Inspector**:
  - Press `Space`, `Return`, or `I` to open images on a full-canvas pane.
  - Slide-out metadata inspector displaying camera parameters, aperture, shutter speed, and lens details.
- **Clean Application Lifecycle**: Automatically terminates the background process when the last window is closed, freeing system memory.

---

## 🛠 Requirements

- **Operating System**: macOS 14.0 (Sonoma) or newer.
- **Developer Tools**: Xcode 16+ / Swift 6 (Swift Package Manager).

---

## 📂 Project Structure

- `Package.swift` — Swift Package Manager configuration file.
- `DuckSort/` — Main source code directory containing:
  - `Models/` — Data models for `PhotoSet`, `Tags`, `Routing Rules`, and `UserPreferences`.
  - `ViewModels/` — View-models implementing business logic and UI state caching.
  - `Views/` — SwiftUI components, sidebar view, photo grid, and metadata inspector.
  - `Utilities/` — Helper extensions, theme structures, window managers, and shortcut handlers.
  - `Resources/` — Bundle assets including the custom duck logo and app icons.
- `package_app.sh` — Bash script to compile the application in release mode and package it into `DuckSort.app`.
- `create_dmg.sh` — Bash script to package the compiled app bundle into a user-friendly installer disk image (`DuckSort.dmg`).

---

## 🚀 Getting Started

### Open and Run in Xcode

- Double-click **`DuckSort.xcodeproj`** to open the project directly in Xcode.
- Alternatively, open Xcode and select the root folder or `Package.swift`.
- Click **Run** or press `Cmd + R` to build and launch the application.

### Command Line / Swift Package Manager

You can also run or build the project directly from the terminal:

```bash
# Run the application
swift run

# Build the project
swift build
```

---

## 📦 Packaging & Distribution

This repository includes helper scripts to compile and package the app for distribution:

1. **Build the Standalone App Bundle**:
   Compile in release configuration and generate a standalone `.app` bundle:
   ```bash
   ./package_app.sh
   ```
2. **Create the DMG Installer Disk Image**:
   After creating the `.app` bundle, package it into a compressed `.dmg` file:
   ```bash
   ./create_dmg.sh
   ```
