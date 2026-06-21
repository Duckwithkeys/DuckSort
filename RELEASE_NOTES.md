# DuckSort v1.2.0 (Branded UI, Extended Scroll & Streamlined Operations)

Welcome to version 1.2.0 of **DuckSort**! This release introduces custom branded visual assets, layout refinements that maximize vertical screen real estate, enhanced sidebar features, and streamlined culling controls.

## ✨ What's New in v1.2.0
* **Branded Custom Logo**: Replaced the generic app/folder icon next to the "DuckSort" header with the custom logo (a duck floating on filmstrips) dynamically loaded from the bundle resources.
* **Accent Separator Line**: Added a solid, 1px horizontal accent line (colored with signature brand blue) in the sidebar to define a clear visual break between the branded app header and library list.
* **Extended Grid Scroll Layout**: Removed the top-level container padding to allow the photos grid `ScrollView` to stretch to the absolute top of the window frame (`0pt`), preventing scrollable images from getting early boundary clipped.
* **Window Controls Clearance**: Offset the top margin of grid items (`44pt`) and the subfolder scanning indicator (`48pt`) to sit cleanly below the window traffic lights when scrolled to the top.
* **Sidebar Sources Management**:
  - Integrated "+ Add Source..." directly under the sources list.
  - Added hover action icons to reveal any source folder in Finder (magnifying glass) or remove it (x).
  - Added context menus with right-click reveal and remove commands.
* **Flags & Ratings Filters**: Added a "Flags & Ratings" collapsible section in the sidebar with live matching counts for Flagged, Rejected, Unrated, and Star ratings.
* **Keyboard Navigation & Selection**:
  - Escape/Delete keys now instantly clear/deselect currently selected photos.
  - Command + A selects all visible photo sets in the active grid.
* **Cleaned Up Redundant JPEG Export**: Removed the redundant "Export JPEGs" action and settings sheet from both the bottom Transfer Footer UI and backend transfer engine to simplify the application's core culling and sorting focus.
* **Cell identity Caching Fixes**: Bound photoshoot grid cells to stable UUID keys to resolve caching issues on filter switches.

---

# DuckSort v1.1.0 (UI Redesign & Viewer Navigation)

Welcome to version 1.1.0 of **DuckSort**! This release introduces a comprehensive UI overhaul to match Photomator's flat, dark professional theme, along with a newly designed sidebar, collapsible tag categories, and navigation enhancements in the large image viewer.

## ✨ What's New in v1.1.0
* **Photomator Dark UI Overhaul**: Replaced the glossy "liquid glass" elements with a flat, dark professional style using a premium charcoal and dark grey palette.
* **Collapsible Tags Sidebar**: A brand new left navigation sidebar that spans the full height of the window, featuring collapsible sections for library items, folders, and custom tags.
* **Interactive Tag Filtering**: Click tags in the sidebar to filter the grid instantly. Supports multi-selection filters for fine-tuned organization.
* **Large Image Viewer Enhancements**:
  * **Unified Grey Background**: Replaced the pitch-black canvas background with the same dark grey background as the grid view for visual consistency.
  * **Back Chevron Button**: Added an intuitive `<` back button next to the window control traffic lights to quickly exit/close the large image viewer.
  * **Clean Top Bar Spacing**: Aligned viewer top-bar elements to guarantee that text never clips under native macOS traffic lights.
* **Refined Photo Cells**: Compacted grid cells with a 2px selection border (using the signature Photomator blue) and subtle hover highlights.

---

# DuckSort v1.0.0 (Initial Release)

Welcome to the first official release of **DuckSort**! This native macOS application is designed to automate the workflow of scanning, organizing, tagging, and routing your photo sets—specifically built for high-end photography workflows (like Fujifilm RAW + JPEG shooters).

## ✨ Key Features
* **Smart Photo Grouping**: Automatically pairs RAW files with their corresponding JPEG representations and sidecar files (e.g., `.photo` files, edit metadata) as unified photo sets.
* **Photo Metadata Inspector**: Instantly view Aperture, Shutter Speed, ISO, Camera Model, and Lens for any selected photo in the large image viewer.
* **Custom Tagging**: A fully-featured Tag Manager to create, edit, and assign color-coded tags to your photo groups.
* **Export Routing Rules**: Define complex rule-based conditions (e.g., based on tags or file types) to automatically route your files to specific target directories.
* **High-Resolution Preview**: Double-click or press Space to view full-canvas previews of your images.
* **Visual Transfer Progress Bar**: High-precision byte-level tracking displaying real-time data transfer rate (MB/s) and megabytes completed during batch operations.
* **JPEG-Only Mode**: A dedicated toggle in the toolbar to exclusively scan and route JPEG files while ignoring missing edit warnings.
* **Keyboard-Driven Workflow**: High-efficiency keyboard shortcuts (`Cmd + A`, `S`, `I`, `0`, and custom tag hotkeys) for rapid selection, navigation, and culling.

## 🛠️ Requirements
* **macOS 14.0 (Sonoma)** or newer.

## 📥 Installation
1. Download the **`DuckSort.dmg`** file from the assets below.
2. Double-click the downloaded `.dmg` file to mount it.
3. Drag the **DuckSort** app into your `Applications` folder.
4. Launch the app from Launchpad or your Applications folder!
