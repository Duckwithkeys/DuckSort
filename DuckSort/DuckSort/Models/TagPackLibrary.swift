//
//  TagPackLibrary.swift
//  DuckSort
//
//  Owns the on-disk `tag-packs.json` file. Holds the live mutable state
//  for every pack — built-in and user-created — and is the single
//  source of truth for "which pack has which categories/tags".
//
//  Switching packs is implemented here so that the active pack's
//  edits aren't lost when the user swaps to another pack:
//    1. Snapshot the current TagStore contents into the outgoing pack's
//       saved state.
//    2. Load the incoming pack's saved state into the TagStore.
//
//  `TagPackLibrary` is `@MainActor` and lives in the same process as
//  the view model so the settings UI can read/write it directly.
//

import Foundation
import Combine

@MainActor
final class TagPackLibrary: ObservableObject {
    @Published private(set) var packs: [TagPackState] = []

    /// ID of the currently active pack. Owned by `UserPreferences` so
    /// it survives across launches.
    var activePackID: String {
        get { UserPreferences.shared.activeTagPackID }
        set {
            UserPreferences.shared.activeTagPackID = newValue
            UserPreferences.shared.save()
        }
    }

    /// Resolved active pack (falls back to the default template if the
    /// saved id is unknown).
    var activePack: TagPackState {
        if let state = packs.first(where: { $0.id == activePackID }) {
            return state
        }
        if let template = TagPackTemplate.template(id: activePackID) {
            return TagPackState.from(template: template)
        }
        // Last resort — return a default template's state.
        return TagPackState.from(template: .general)
    }

    private let storeURL: URL

    init() {
        let appSupport = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)
            .first ?? FileManager.default.temporaryDirectory
        let folder = appSupport.appendingPathComponent("DuckSort", isDirectory: true)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        self.storeURL = folder.appendingPathComponent("tag-packs.json")
        load()
        rebuildIndexes()
        if packs.isEmpty {
            // First launch — seed every built-in template with its factory
            // state so the user has something to switch into immediately.
            packs = TagPackTemplate.allTemplates.map(TagPackState.from(template:))
            rebuildIndexes()
            save()
        }
    }

    // MARK: - Lookup

    func state(for id: String) -> TagPackState? {
        packs.first(where: { $0.id == id })
    }

    /// Whether the given pack id refers to a built-in catalog entry.
    /// Used by the UI to gate delete/edit affordances.
    func isBuiltIn(_ id: String) -> Bool {
        TagPackTemplate.template(id: id) != nil
    }

    /// O(1) lookup of a pack id by its parsed keyboard shortcut. Rebuilt
    /// inside `rebuildIndexes()` so the global key monitor in ContentView
    /// doesn't have to iterate every pack + re-parse its hotkey string on
    /// every key event. Packs with no hotkey are simply omitted from the
    /// index, so the default state is "no binding claimed".
    private var packHotkeyIndex: [KeyboardShortcutInfo: String] = [:]

    private func rebuildIndexes() {
        packHotkeyIndex = [:]
        for pack in packs {
            guard let raw = pack.hotkey, !raw.isEmpty,
                  let info = KeyboardShortcutInfo.parse(raw) as KeyboardShortcutInfo?,
                  !info.key.isEmpty
            else { continue }
            packHotkeyIndex[info] = pack.id
        }
    }

    /// Resolve a key event to a pack id (or nil if no pack claims it).
    /// Used by ContentView's global key monitor.
    func packID(for shortcut: KeyboardShortcutInfo) -> String? {
        packHotkeyIndex[shortcut]
    }

    /// Returns the human-readable hotkey string for a pack, or nil if
    /// none is set. Used by the Settings UI to display the current
    /// binding in the ellipsis menu.
    func hotkey(forPackID id: String) -> String? {
        packs.first(where: { $0.id == id })?.hotkey
    }

    // MARK: - Mutation

    /// Persist the supplied pack state under its id.
    func upsert(_ state: TagPackState) {
        if let index = packs.firstIndex(where: { $0.id == state.id }) {
            packs[index] = state
        } else {
            packs.append(state)
        }
        rebuildIndexes()
        save()
    }

    /// Reset a pack's categories + tags to its built-in template defaults.
    /// For user-created packs this resets to empty.
    func resetPack(id: String) {
        guard let index = packs.firstIndex(where: { $0.id == id }) else { return }
        if let template = TagPackTemplate.template(id: id) {
            packs[index] = TagPackState.from(template: template)
        } else {
            // User pack — clear categories and tags but keep the name/icon.
            packs[index].categories = []
            packs[index].tags = []
        }
        rebuildIndexes()
        save()
    }

    /// Duplicate a pack under a new id. The copy starts as user-created.
    func duplicatePack(id: String, newName: String) -> TagPackState? {
        guard let original = state(for: id) else { return nil }
        let newID = makeUniqueID(basedOn: id)
        let copy = TagPackState(
            id: newID,
            name: newName,
            tagline: original.tagline,
            systemImage: original.systemImage,
            accentColor: original.accentColor,
            isBuiltIn: false,
            categories: original.categories,
            tags: original.tags,
            hotkey: nil // Duplicate starts with no binding — the user assigns one if they want.
        )
        packs.append(copy)
        rebuildIndexes()
        save()
        return copy
    }

    /// Delete a user-created pack. Built-in packs cannot be deleted.
    func deletePack(id: String) {
        guard !isBuiltIn(id) else { return }
        guard let index = packs.firstIndex(where: { $0.id == id }) else { return }
        packs.remove(at: index)
        rebuildIndexes()
        save()
    }

    /// Update editable metadata (name, tagline, icon, accent) for a pack.
    /// Built-in packs cannot be renamed or restyled, but the user can
    /// override name/accent by duplicating first.
    func renamePack(id: String, to newName: String) {
        guard let index = packs.firstIndex(where: { $0.id == id }) else { return }
        guard !isBuiltIn(id) else { return }
        let trimmed = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        packs[index].name = trimmed
        rebuildIndexes()
        save()
    }

    func restylePack(id: String, systemImage: String, accentColor: String) {
        guard let index = packs.firstIndex(where: { $0.id == id }) else { return }
        guard !isBuiltIn(id) else { return }
        packs[index].systemImage = systemImage
        packs[index].accentColor = accentColor
        rebuildIndexes()
        save()
    }

    /// Assign or change the activation hotkey for a pack. Pass an empty
    /// string or call `clearHotkey(id:)` to remove the binding. The hotkey
    /// is freed from any other pack that previously held it so two packs
    /// can never share the same binding.
    ///
    /// Note: built-in packs CAN have a hotkey set — the model just
    /// doesn't let the user rename, restyle, or delete them. Hotkey is a
    /// pure binding, not pack content, so it's fine to assign one.
    func setHotkey(_ raw: String, forPackID id: String) {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            clearHotkey(forPackID: id)
            return
        }
        guard let index = packs.firstIndex(where: { $0.id == id }) else { return }

        // Clear the binding from any other pack that previously held it so
        // two packs never claim the same key.
        for i in packs.indices where packs[i].hotkey == trimmed && packs[i].id != id {
            packs[i].hotkey = nil
        }
        packs[index].hotkey = trimmed
        rebuildIndexes()
        save()
    }

    /// Remove the activation hotkey from a pack (sets `hotkey` to nil).
    /// Safe to call on packs that have no hotkey set.
    func clearHotkey(forPackID id: String) {
        guard let index = packs.firstIndex(where: { $0.id == id }) else { return }
        guard packs[index].hotkey != nil else { return }
        packs[index].hotkey = nil
        rebuildIndexes()
        save()
    }

    /// Import a pack from an exported payload. If a pack with the same id
    /// already exists, the existing entry is overwritten with the imported
    /// one — but the imported pack is marked user-created so the user can
    /// edit it freely.
    @discardableResult
    func importPack(_ state: TagPackState) -> TagPackState {
        var incoming = state
        // Ensure imported packs are editable, even if their id collides
        // with a built-in. Built-in catalog entries cannot be replaced.
        if isBuiltIn(incoming.id), incoming.id != TagPackTemplate.defaultTemplateID {
            // Collision with a built-in — give it a new id so the
            // imported copy is treated as a separate user pack.
            incoming = TagPackState(
                id: makeUniqueID(basedOn: incoming.id + "-imported"),
                name: incoming.name + " (Imported)",
                tagline: incoming.tagline,
                systemImage: incoming.systemImage,
                accentColor: incoming.accentColor,
                isBuiltIn: false,
                categories: incoming.categories,
                tags: incoming.tags
            )
        } else {
            incoming = TagPackState(
                id: incoming.id,
                name: incoming.name,
                tagline: incoming.tagline,
                systemImage: incoming.systemImage,
                accentColor: incoming.accentColor,
                isBuiltIn: false,
                categories: incoming.categories,
                tags: incoming.tags
            )
        }
        upsert(incoming)
        return incoming
    }

    /// Snapshot the live categories/tags/assignments from `tagStore` into
    /// the library entry for `packID`. Used when the user switches away
    /// from a pack to preserve their edits.
    func snapshotActivePack(from tagStore: TagStore, packID: String) {
        guard let index = packs.firstIndex(where: { $0.id == packID }) else { return }
        let categoriesByID: [UUID: String] = Dictionary(
            uniqueKeysWithValues: tagStore.categories.map { ($0.id, $0.name) }
        )
        var seenCategoryNames = Set<String>()
        var newCats: [TagPackState.CategoryEntry] = []
        for cat in tagStore.categories {
            guard !seenCategoryNames.contains(cat.name) else { continue }
            seenCategoryNames.insert(cat.name)
            newCats.append(.init(name: cat.name))
        }

        var newTags: [TagPackState.TagEntry] = []
        for tag in tagStore.tags {
            let catName = categoriesByID[tag.categoryID] ?? "Uncategorized"
            newTags.append(.init(
                category: catName,
                name: tag.name,
                hotkey: tag.hotkey,
                colorHex: tag.colorHex
            ))
        }

        // Preserve the pack's identity (name/icon/accent) and just
        // refresh the categories + tags.
        packs[index].categories = newCats
        packs[index].tags = newTags
        save()
    }

    /// Replace the contents of `tagStore` with the saved state for
    /// `packID`. Falls back to factory content from the matching
    /// template if the pack state is empty.
    func applyPack(_ packID: String, to tagStore: TagStore) {
        let resolved: TagPackState
        if let saved = self.state(for: packID) {
            resolved = saved
        } else if let template = TagPackTemplate.template(id: packID) {
            resolved = TagPackState.from(template: template)
        } else {
            return
        }
        tagStore.applyPackState(resolved)
    }

    // MARK: - Persistence

    private func load() {
        guard FileManager.default.fileExists(atPath: storeURL.path) else {
            return
        }
        do {
            let data = try Data(contentsOf: storeURL)
            let file = try JSONDecoder().decode(TagPackLibraryFile.self, from: data)
            // Merge in any new built-in templates that the user hasn't
            // touched yet, so updates to the catalog show up on launch.
            var byID = Dictionary(uniqueKeysWithValues: file.packs.map { ($0.id, $0) })
            for template in TagPackTemplate.allTemplates {
                if byID[template.id] == nil {
                    byID[template.id] = TagPackState.from(template: template)
                }
            }
            packs = byID.values.sorted { lhs, rhs in
                // Built-ins first in template order, then user packs by name.
                if lhs.isBuiltIn != rhs.isBuiltIn {
                    return lhs.isBuiltIn
                }
                if lhs.isBuiltIn && rhs.isBuiltIn {
                    let li = TagPackTemplate.allTemplates.firstIndex { $0.id == lhs.id } ?? Int.max
                    let ri = TagPackTemplate.allTemplates.firstIndex { $0.id == rhs.id } ?? Int.max
                    return li < ri
                }
                return lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
            }
        } catch {
            print("Failed to load tag-packs.json: \(error)")
        }
    }

    func save() {
        do {
            let file = TagPackLibraryFile(packs: packs)
            let data = try JSONEncoder().encode(file)
            try data.write(to: storeURL, options: .atomic)
        } catch {
            print("Failed to save tag-packs.json: \(error)")
        }
    }

    // MARK: - Helpers

    /// Build a new unique pack id based on an existing one.
    private func makeUniqueID(basedOn base: String) -> String {
        var candidate = "\(base)-copy"
        var counter = 2
        while packs.contains(where: { $0.id == candidate }) {
            candidate = "\(base)-copy-\(counter)"
            counter += 1
        }
        return candidate
    }
}