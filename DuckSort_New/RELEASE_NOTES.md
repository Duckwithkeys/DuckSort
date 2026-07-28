# DuckSort v1.3.5 Release Notes

Welcome to version **1.3.5** of **DuckSort**! This release unifies the window header with comprehensive routing & transfer controls, streamlines the main photo grid, introduces inline category editing, integrates direct Photomator editing handoffs, exposes comprehensive Speed Culling (Auto-Advance) customization options, adds a multi-pulse haptic physical click sequence, and adds a brand-new EXIF Analytics dashboard.

## ✨ What's New in v1.3.5

* **Camera & Lens Performance Insights (EXIF Analytics)**:
  * Added a dedicated "EXIF Analytics" dashboard button in the toolbar (`chart.bar.xaxis`).
  * Features a full-screen sheet with Canvas-based, fluidly-animated bar charts showing Focal Length, Aperture, ISO Distribution, and Shutter Speed breakdowns.
  * Displays "Top Gear Combinations" showing camera and lens pairings, occurrence count, average aperture, and pick ratios.
* **Photomator Integration & Custom Handoff**:
  * Added a configurable hotkey (defaults to `E`) and a glassmorphic floating **Edit** overlay button on the large viewer.
  * Instantly launches Photomator (`com.pixelmatorteam.pixelmator.touch.x.photo`) and opens the current RAW or image file directly.
* **Speed Culling (Auto-Advance) Customizations & Hotkey**:
  * Added a "Speed Culling (Auto-Advance)" settings card under the Mode Switching Settings tab.
  * Allows toggling Auto-Advance sound effects, haptic clicks, and recording a custom global hotkey to toggle the feature instantly.
* **Triple-Pulse Tactile Haptic click**:
  * Swapped the faint `.generic` haptic pattern with a triple-pulse mechanical click sequence (`.levelChange` and double `.alignment` bursts in a 30ms queue) for a strong physical feedback tick on supported trackpads.
* **Orphaned XMP Tags Settings Pane**:
  * Migrated the XMP Tag Inspector directly into the Settings window as a dedicated pane for importing orphaned XMP subjects into active packs.
* **Horizontal Mouse Scroll on Tag Packs**:
  * Added custom horizontal mouse scroll support to the tag pack templates list in Settings.
* **CryptoKit SHA-256 Migration**:
  * Migrated `FileNaming.swift` from deprecated CommonCrypto `CC_MD5` to Apple's modern CryptoKit `SHA256` hashing for file checksum comparisons.
* **Unified Window Header & Top Bar Navigation**:
  * Moved Destination Selection (`tray.and.arrow.down`), Export Routing Rule Menu (`folder.badge.gearshape`), and Copy (`doc.on.doc`) / Move (`folder`) action buttons directly into the top window header toolbar alongside Add Source and Filters.
  * Added a real-time photo count and active selection status item in the top toolbar with a vibrant green checkmark icon (`checkmark.circle.fill` in brand green) showing active selected photo counts.
* **Streamlined Edge-to-Edge Grid View**:
  * Completely removed the bottom `TransferFooter` panel for a clean, edge-to-edge photo grid experience.
  * Removed redundant internal text headers from inside the grid view, granting photo thumbnails maximum vertical space right below the top window bar.
* **Large Viewer & Window Edge Polishing**:
  * Configured full-window `.ignoresSafeArea()` on `LargeImageViewer` so the overlay extends seamlessly across the entire window container without exposing underlying layout steps or titlebar color misalignments.
  * Synchronized window background color (`window.backgroundColor = NSColor(Theme.Color.background)`), eliminating titlebar tab artifacts.
  * Applied 54pt top clearance on the large viewer photo container so images sit comfortably below native macOS titlebar pills.
* **Settings & Category Editing**:
  * Introduced inline editing for categories in Tag Packs settings — click and rename category section headers directly on the page.
  * Refined highlight sizing on Rules and Rebinds settings panes for clean alignment with the dark design system.

## ⚡ Graphics Acceleration & Neural Engine Performance Pass

* **Metal GPU Layer & Zero-Copy Memory Management**:
  * **Metal-Backed Zoom & Pan**: Added `.drawingGroup(opaque: false)` to the large viewer's zoom/pan image layer for smooth Metal-accelerated GPU rendering during pinch/pan gestures.
  * **Instant Memory Release**: Immediately nils out previous high-res image buffers on view task trigger, releasing ~36MB of RAM per photo swap.
* **Ultra-Sharp High-DPI Retina Rendering & Extended Preview Ceiling**:
  * **600px Retina Grid Thumbnails**: Doubled standard grid thumbnail decoding targets from 300px to 600px max pixels, delivering razor-sharp rendering on high-DPI Retina displays.
  * **3072px Ultra-HD Large Previews**: Expanded large image preview decoding ceiling from 2048px to 3072px, capturing full dynamic detail for 4K and 5K Retina displays.
  * **Immediate GPU Bitmap Caching & Float Precision**: Enabled `kCGImageSourceShouldCacheImmediately: true` for zero-hitch background decompression and `kCGImageSourceShouldAllowFloat: true` for Display P3 wide-gamut color accuracy.
* **On-Device AI Neural Engine Auto-Tagging Acceleration**:
  * **299px Model Tensor Match**: Aligned thumbnail extraction for Vision scene classification to 299px max pixels, matching exact Apple Neural Engine model input dimensions and reducing ImageIO decode overhead by >60%.
  * **Synchronous Execution & Result Caching**: Removed async continuations to run Vision requests directly and synchronously on `@VisionActor`, backed by an in-memory `NSCache` for 0ms instant classification lookups.
  * **Predictive Neighbor Preloading**: Integrated Vision ML classification directly into neighbor preloading. As you navigate or focus on a photo, neighboring photos pre-trigger background Neural Engine classifications so recommendations appear instantaneously when switching photos.
* **Data Pipeline & Layout Overhead Reduction**:
  * **Zero-Overhead Grid Layout**: Removed internal `GeometryReader` wrappers from every cell, eliminating hundreds of bottom-up layout recalculations during scroll.
  * **Gated Marquee Hit-Testing**: Gated cell `GeometryReader` background overlays so they only install when an active marquee drag (`marqueeStart != nil`) is occurring.
  * **Coalesced Filter Updates**: Added `batchUpdate()` to coalesce state mutations and eliminate redundant `updateDerivedState()` runs.
  * **Gated Metadata Task Group**: Limited parallel metadata decoding to 16 concurrent tasks to prevent file descriptor exhaustion and I/O thrashing.
  * **Pre-Computed Photo Date Map**: Cached photo dates in `photoDateCache` to eliminate blocking filesystem `stat()` calls during library sorting.
  * **Zero-Memory EXIF Reads**: Passed `kCGImageSourceShouldCache: false` for EXIF-only property reading, saving ~50MB RAM per RAW file scan.
  * **Downsampled Body Pose Frames**: Downsampled Vision body pose inputs to 1024px thumbnails, dropping memory footprint from 200MB to 4MB per inference.

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
