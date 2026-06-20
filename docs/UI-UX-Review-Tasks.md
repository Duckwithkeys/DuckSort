# UI/UX Review — Task List

Findings from a review of drag-and-drop, floating-window top bars, and menu bars
(plus closely-related navigation paths). Ordered by severity. Check items off as
they land.

## 🔴 Critical — onboarding promises features that don't exist

- [ ] **Empty state advertises non-existent capabilities.** `EmptyLibraryView.swift:34,46`
  tells users to "Drag files or folders directly into DuckSort" and "Choose Import
  from the File menu", but neither exists. Fix the copy **and/or** implement the
  features below.
- [ ] **No drag-and-drop anywhere in the app.** No `.onDrop` / `.dropDestination` /
  `DropDelegate` / `registerForDraggedTypes` in the source tree. The drop-target card
  in the empty state is decorative. Affects `ContentView`, `PhotoGridView`,
  `EmptyLibraryView`, `SidebarView`.
- [ ] **No File menu → Import.** `DuckSortApp.swift:21-49` adds only `SidebarCommands`,
  `TextEditingCommands`, and `CommandMenu("Tools")`. The default File menu has no
  Import item.
- [ ] **"Import..." button is mislabeled.** It calls `addSourceDirectory()` →
  `FolderPanel.chooseDirectory` (`PhotoLibraryViewModel.swift:194-195`) which sets
  `canChooseFiles = false` (`FolderPanel.swift:13`) — folders only, despite the
  "files or folders" promise. The action is also named three different things
  ("Import…", "Add Source", "Add Photoshoot Folder"). Unify naming.

## 🟠 High

- [ ] **Implement drag-and-drop entry point.** Add `.dropDestination(for: URL.self)` on
  the `ContentView` content area and `EmptyLibraryView`, funneling into the existing
  scan pipeline. Relax `FolderPanel` / scan path to accept individual files so
  "files or folders" becomes true.
- [ ] **Fragile floating-window close path.** `TagManagerView.swift:34-37` and
  `ExportRuleEditorView.swift:25-27` close via `dismiss(); NSApp.keyWindow?.close()`.
  - `dismiss()` is a dead no-op (panel hosted via `NSHostingView`, not a sheet).
  - `NSApp.keyWindow` may not be the panel → can close the wrong window or nothing.
  - Close the specific panel the manager already holds (`tagManagerPanel`, etc.),
    e.g. pass a close closure into each view.
- [ ] **Floating panels have no Esc / close button.** `FloatingPanel` hides all window
  buttons including close (`FloatingWindowManager.swift:38-40`); "Done" is the only
  exit. Wire `.keyboardShortcut(.cancelAction)` (Esc) on the Done buttons.
- [ ] **Global key monitor leaks into floating windows.** The app-wide
  `addLocalMonitorForEvents(.keyDown)` (`PhotoLibraryViewModel.swift:643`) only bails
  for editable text fields (`ContentView.swift:186-189`). With Tag Manager / Rule
  Editor / Shortcuts focused, `s`/`i`/`0`/arrows/tag-hotkeys still mutate the
  background grid. Short-circuit when a floating panel is the key window (or scope
  the monitor to the main window).

## 🟡 Medium — menu bar

- [ ] **Hardcoded shortcuts diverge from customizable ones.** Tools menu hardwires
  `⌘T`/`⌘R`/`⌘/` (`DuckSortApp.swift:31,38,47`) while the same actions are also driven
  by customizable `tagManagerHotkey`/`ruleEditorHotkey`/`openSourceHotkey`
  (`ContentView.swift:192-206`). Rebinding leaves the menu label stale and the two
  systems disagreeing. Pick one source of truth.
- [ ] **Menu items silently no-op without an active view model.** Each Tools item is
  guarded by `if let vm = ...activeViewModel` (`DuckSortApp.swift:27-46`). Use
  `.disabled(activeViewModel == nil)` for feedback.
- [ ] **No File menu**, despite the empty state pointing at it. Add at minimum
  "Add Source Folder… ⌘O / Import…".
- [ ] **Redundant titles.** Panels show a system title bar *and* an in-content header
  with the same text (e.g. "Tag Manager" at `FloatingWindowManager.swift:68` +
  `TagManagerView.swift:25`). Keep one.

## 🟡 Medium — navigation

- [ ] **Grid keyboard nav math doesn't match the layout.** Grid uses
  `.adaptive(minimum: 180), spacing: 14, .padding(.horizontal, 20)`
  (`PhotoGridView.swift:13,51`) but Up/Down row-stride uses `minWidth 208,
  spacing 18, padding 56` (`ContentView.swift:353-359`). Derive both from a shared
  source so arrows land correctly.

## ⚪ Minor / polish

- [ ] **Two close affordances in the large viewer top bar** — `chevron.left`
  (`LargeImageViewer.swift:73`) and `xmark` (`:154`) both call
  `closeLargeImageViewer()`. Keep one.
- [ ] **Pan offset doesn't accumulate.** `LargeImagePane.swift:73` sets
  `panOffset = value.translation` instead of adding to the prior offset → panning a
  zoomed image snaps back each gesture.
- [ ] **`EdgeBorder` computed-property closures.** `LargeImageViewerSidebar.swift:205-232`
  uses `var x/y/w/h` getter closures inside `path(in:)`; a `switch` or plain values
  read more clearly.
