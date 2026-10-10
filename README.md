# DuckSort

A macOS app for fast photo culling, tagging, and bulk file routing — built entirely in Swift with zero third-party dependencies.

Drag a folder of photos onto DuckSort, review them at full resolution, tag or rate what you keep, and export with one click using configurable routing rules that organize everything into folders by camera model, lens, date, tag category, EXIF data, or custom text.

---

## Quick Start

1. **Open** DuckSort from your Applications folder.
2. **Add a source folder** — use the toolbar "Add Source" button (`⇧⌘O`), or drag-and-drop a folder of photos directly onto the grid.
3. **Review & cull** — scan through your photos in the thumbnail grid, zoom into full resolution with `Space` / `Return`, and flag the ones you want to keep.
4. **Organize** — apply tag packs (think "Wedding", "Portraits", "Cars") using keyboard shortcuts or the tag manager, rate photos, and set pick/reject status.
5. **Choose a destination** — click "Destination…" in the toolbar and pick where your organized files should go.
6. **Export** — select "Copy" or "Move" to apply your routing rule and transfer all selected photo sets to the destination folder.

---

## Core Features

### Fast, Native UI
- Edge-to-edge grid with smooth scrolling and haptic feedback (trackpad)
- Dark / Light mode that follows your macOS system preference
- Full-screen image viewer with zoom and pan support, filmstrip navigation, and metadata inspector (`I`)
- Drag-and-drop source folders directly onto the grid

### Smart Photo Grouping
Automatically groups RAW + HEIF + JPEG variants and sidecar files (`.photo-edit`, XMP) into unified sets so you're always reviewing a complete family — not individual files.

### Tag Packs & Routing Rules
- **Tag Packs**: Pre-built category/tag presets (Wedding, Portraits, Cars, Apparel, etc.) plus full support for custom packs with colored chips, icons, and per-tag keyboard shortcuts. Switch packs on the fly with a global hotkey.
- **Routing Rules**: Build export rules that route photos into nested folder hierarchies based on camera model, lens, date, tag category, EXIF data (ISO, aperture, shutter speed), star rating, pick status, or custom text. Apply "Copy" or "Move" to bulk-organize hundreds of files at once.

### AI Auto-Tagging
On-device image classification and face detection run directly on the Apple Neural Engine — no network calls, no API keys. Clustering suggestions appear inline for one-click import into your active tag pack.

### Insights Dashboard
Camera & lens pairing stats, focal-length / aperture / ISO distributions, and shutter-speed histograms — all drawn with SwiftUI Canvas (no Charts framework). See which gear combinations produce the most picks.

### Photomator Integration
Open the active photo directly into Photomator from the viewer with `E` or a click — seamless handoff for fine editing.

---

## Keyboard Shortcuts

| Action | Shortcut |
|---|---|
| Add source folder | `⇧⌘O` |
| Choose destination | `⇧⌘D` |
| Open viewer (grid) | `Space`, `Return` |
| Zoom in / out | Click zoom buttons in toolbar |
| Toggle sidebar | `⌥⌘S` |
| Select all visible | `⌘A` |
| Rate a photo (0–5) | Keys `1`–`5` |
| Flag pick | `Z` |
| Reject | `X` |
| Clear pick/rating | `U` |
| Close viewer / Escape | `Esc` |

*Tag pack and tag-specific shortcuts are configurable per-pack in the settings.*

---

## Build & Development

**Requirements**: macOS 14.0+ (Sonoma), Xcode 16+, Swift 6

### Using Xcode
Open `DuckSort.xcodeproj` and press Cmd+R.

### Using the command line
```bash
cd DuckSort
swift build    # Build the package
swift run      # Run the app
swift test     # Run the test suite
```

### Packaging for distribution
```bash
./package_app.sh        # Builds a DuckSort.app bundle
./create_dmg.sh         # Packages it into DuckSort.dmg
```

---

## Architecture at a Glance

| Layer | What it does |
|---|---|
| **Models** | `PhotoSet`, `TagPack`, `ExportPathRule`, `UserPreferences` — core data types |
| **ViewModels** | `PhotoLibraryViewModel` — the app's central state hub (source dirs, tags, routing) |
| **Views** | SwiftUI: grid, sidebar, viewer, insights, export rule editor, tag manager, settings panes |
| **Utilities / AI** | Vision-based auto-tagging, face clustering, Neural Engine optimization |
| **Utilities / Cache** | Two-tier thumbnail cache (memory LRU + disk JPEG, 500 MB budget) |
| **Utilities / Transfers** | Routed copy/move with EXIF-aware path templating and sidecar writing |
| **Utilities / Metadata** | EXIF reading, XMP sidecar import/export, VCard IPTC profiles |
| **Tests** | Unit tests for file scanning, caching, routing, tag packs, and transfer logic |

---

## License

Private project. All rights reserved.
