# 🦆 DuckSort

A native macOS application designed to automate the workflow of scanning, organizing, tagging, and routing photo sets. It groups RAW files, JPEGs, and sidecar files (such as Photomator edits) into unified sets, allowing you to manage and export them efficiently using customizable routing rules.

DuckSort matches the flat, dark professional aesthetic of modern photo editors like **Photomator**, adapting natively to macOS system-wide Light and Dark mode preferences.

---

## ✨ Features

- **Smart Photo Grouping**: Automatically pairs RAW files with their corresponding JPEG representations and sidecar files (e.g., `.photo` files, edit metadata) as unified photo sets.
- **Vast RAW & Image Format Support**: Supports all major raw formats including Sony (`.arw`), Canon (`.cr2`/`.cr3`), Nikon (`.nef`), Adobe (`.dng`), Olympus (`.orf`), Panasonic (`.rw2`), and Pentax (`.pef`), as well as standard JPEG, HEIF, HEIC, and HIF (`.hif`) images.
- **Native System Appearance**: Transitions fluidly between professional charcoal-dark and clean-light modes, matching your macOS system theme.
- **Instant Startup Loading (Concurrently Optimized)**: 
  - Parallelized XMP sidecar reads using a concurrent `TaskGroup` fetching up to 16 files simultaneously.
  - Memoized global counts for tags, flags, and star ratings to eliminate redundant UI redraws.
  - Batched tag assignments to database files with zero UI freezing.
- **Dynamic Photo Grid & Filmstrip**:
  - Borderless, rounded thumbnail cells that align perfectly.
  - Overlay badges (flags, star ratings, edit sidecars, and format pills) locked directly to the thumbnail frame.
  - Instant, smooth scrolling with safe layout loop prevention during resizing or filtering.
- **Interactive Sidebar & Filtering**:
  - Live folder sources management with Finder reveal, remove context actions, and scan status warnings.
  - Live filters for custom Tags, Flag status (Flagged, Rejected, Unrated), and Star Ratings (0–5 stars) with real-time match counters.
- **Live Local Search**: Instantly find photo sets by base name using the fast, dismissible search bar. Focus auto-releases when clicking outside the input.
- **Export Routing Rules**: Define rule-based conditions (based on tags, ratings, flags, or file extensions) to automatically route files to specific destination directories.
- **Robust Metadata Preservation**: Writes an `.xmp` sidecar beside copied/moved files recording custom tags, rating, flag status, and capture metadata (camera, lens, ISO, shutter, aperture).
- **High-Resolution Viewer & Inspector**:
  - Press Space or double-click to view images on a full-canvas pane.
  - Slide-out metadata inspector displaying camera parameters, aperture, shutter speed, and lens details.
- **Clean Application Lifecycle**: Automatically terminates the background process when the last window is closed, freeing system memory.

---

## 🛠️ Requirements

- **Operating System**: macOS 14.0 (Sonoma) or newer.
- **Developer Tools**: Xcode 15+ / Swift 5.9+ (Swift Package Manager).

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

1. Open Xcode.
2. Select **Open Existing Project** (or **File > Open...**).
3. Select the root folder containing `Package.swift`.
4. Click **Run** or press `Cmd + R` to build and launch the application.

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
