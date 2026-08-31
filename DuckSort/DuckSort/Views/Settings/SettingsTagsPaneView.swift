//
//  SettingsTagsPaneView.swift
//  DuckSort
//
//  The "Tags" tab of the unified Settings window. Native macOS split layout:
//  a left-hand sidebar listing every tag pack, and an edge-to-edge detail
//  panel on the right where categories and their tag chips are edited.
//  No card chrome — categories sit directly on the window background and
//  are separated by hairlines and vertical whitespace, with category
//  headers, icons, and tag chips aligned to a strict 24pt spine.
//

import SwiftUI
import UniformTypeIdentifiers

struct SettingsTagsPaneView: View {
    @ObservedObject var viewModel: PhotoLibraryViewModel
    @ObservedObject var tagStore: TagStore

    var body: some View {
        SettingsSplitLayout {
            TagPacksSidebar(viewModel: viewModel)
        } detail: {
            TagsDetailPanel(
                tagStore: tagStore,
                viewModel: viewModel
            )
        }
    }
}

// MARK: - Tag Packs Sidebar

private struct TagPacksSidebar: View {
    @ObservedObject var viewModel: PhotoLibraryViewModel

    @State private var showingNewPack = false
    @State private var showingSwitchConfirm = false
    @State private var pendingSwitchID: String? = nil
    @State private var pendingDeleteID: String? = nil
    @State private var showingDeleteConfirm = false
    @State private var pendingResetID: String? = nil
    @State private var showingResetConfirm = false
    @State private var renameTarget: TagPackState? = nil
    @State private var renameText: String = ""
    @State private var styleTarget: TagPackState? = nil
    @State private var hotkeyTarget: TagPackState? = nil

    @State private var showContactConfirm = false
    @State private var pendingContactCount = 0

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("TAG PACKS")
                    .font(Theme.Font.caption2)
                    .tracking(0.5)
                    .foregroundStyle(Theme.Color.textTertiary)
                Spacer()
            }
            .padding(.horizontal, Theme.Space.s12)
            .padding(.top, Theme.Space.s12)
            .padding(.bottom, Theme.Space.s6)

            ScrollView {
                GlassEffectContainer(spacing: Theme.Space.s2) {
                    LazyVStack(alignment: .leading, spacing: Theme.Space.s2) {
                        ForEach(viewModel.packLibrary.packs) { state in
                            TagPackSidebarRow(
                                state: state,
                                isActive: state.id == UserPreferences.shared.activeTagPackID,
                                onActivate: {
                                    pendingSwitchID = state.id
                                    showingSwitchConfirm = true
                                },
                                onRename: {
                                    renameText = state.name
                                    renameTarget = state
                                },
                                onReset: {
                                    pendingResetID = state.id
                                    showingResetConfirm = true
                                },
                                onDuplicate: {
                                    if let copy = viewModel.duplicatePack(id: state.id,
                                                                             newName: "\(state.name) Copy") {
                                        viewModel.switchTagPack(id: copy.id)
                                    }
                                },
                                onDelete: {
                                    pendingDeleteID = state.id
                                    showingDeleteConfirm = true
                                },
                                onExport: {
                                    viewModel.exportPack(id: state.id)
                                },
                                onRestyle: {
                                    styleTarget = state
                                },
                                onSetHotkey: {
                                    hotkeyTarget = state
                                },
                                onClearHotkey: {
                                    viewModel.packLibrary.clearHotkey(forPackID: state.id)
                                }
                            )
                        }
                    }
                    .padding(.horizontal, Theme.Space.s8)
                    .padding(.bottom, Theme.Space.s8)
                }
            }

            Rectangle()
                .fill(Theme.Color.surfaceDivider)
                .frame(height: Theme.Stroke.hairline)

            sidebarActions
                .padding(.horizontal, Theme.Space.s8)
                .padding(.vertical, Theme.Space.s8)
        }
        .sheet(isPresented: $showingNewPack) {
            NewPackSheet(viewModel: viewModel, isPresented: $showingNewPack)
        }
        .sheet(item: $renameTarget) { target in
            RenamePackSheet(
                currentName: target.name,
                isPresented: Binding(
                    get: { renameTarget != nil },
                    set: { if !$0 { renameTarget = nil } }
                ),
                onCommit: { newName in
                    viewModel.renamePack(id: target.id, to: newName)
                    renameTarget = nil
                }
            )
        }
        .sheet(item: $styleTarget) { target in
            PackStyleSheet(
                state: target,
                isPresented: Binding(
                    get: { styleTarget != nil },
                    set: { if !$0 { styleTarget = nil } }
                ),
                onCommit: { systemImage, accentColor in
                    viewModel.restylePack(id: target.id,
                                          systemImage: systemImage,
                                          accentColor: accentColor)
                    styleTarget = nil
                }
            )
        }
        .sheet(item: $hotkeyTarget) { target in
            PackHotkeySheet(
                state: target,
                currentHotkey: viewModel.packLibrary.hotkey(forPackID: target.id),
                isPresented: Binding(
                    get: { hotkeyTarget != nil },
                    set: { if !$0 { hotkeyTarget = nil } }
                ),
                onCommit: { raw in
                    viewModel.packLibrary.setHotkey(raw ?? "", forPackID: target.id)
                    hotkeyTarget = nil
                }
            )
        }
        .confirmationDialog(
            pendingSwitchLabel,
            isPresented: $showingSwitchConfirm,
            titleVisibility: .visible
        ) {
            Button("Switch") {
                if let id = pendingSwitchID {
                    viewModel.switchTagPack(id: id)
                }
                pendingSwitchID = nil
            }
            Button("Cancel", role: .cancel) { pendingSwitchID = nil }
        } message: {
            Text("Saves your edits to the current pack, then loads the chosen pack.")
        }
        .confirmationDialog(
            "Delete \(pendingDeleteName)?",
            isPresented: $showingDeleteConfirm,
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) {
                if let id = pendingDeleteID {
                    viewModel.deletePack(id: id)
                }
                pendingDeleteID = nil
            }
            Button("Cancel", role: .cancel) { pendingDeleteID = nil }
        } message: {
            Text("This removes the pack and its saved state. The active pack switches to the default if needed.")
        }
        .confirmationDialog(
            "Reset \(pendingResetName) to factory defaults?",
            isPresented: $showingResetConfirm,
            titleVisibility: .visible
        ) {
            Button("Reset", role: .destructive) {
                if let id = pendingResetID {
                    viewModel.resetPack(id: id)
                }
                pendingResetID = nil
            }
            Button("Cancel", role: .cancel) { pendingResetID = nil }
        } message: {
            Text("Replaces the pack's categories and tags with its built-in defaults. Any custom edits are lost.")
        }
        .confirmationDialog(
            "Import \(pendingContactCount) contacts as tags?",
            isPresented: $showContactConfirm,
            titleVisibility: .visible
        ) {
            Button("Import") { performContactImport() }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("New tags will be added under the People category. Existing tags with the same name are kept.")
        }
    }

    private var sidebarActions: some View {
        VStack(alignment: .leading, spacing: Theme.Space.s4) {
            sidebarActionButton(title: "New Pack", systemImage: "plus", action: { showingNewPack = true })
            sidebarActionButton(title: "Import Pack", systemImage: "square.and.arrow.down", action: { viewModel.importPack() })
            sidebarActionButton(title: "Import Contacts", systemImage: "person.crop.circle.badge.plus", action: { showContactPicker() })
        }
    }

    private func sidebarActionButton(title: String, systemImage: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: Theme.Space.s8) {
                Image(systemName: systemImage)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Theme.Color.textSecondary)
                    .frame(width: 18)
                Text(title)
                    .font(Theme.Font.body)
                    .foregroundStyle(Theme.Color.textPrimary)
                Spacer()
            }
            .padding(.horizontal, Theme.Space.s10)
            .padding(.vertical, Theme.Space.s6)
            .flatSidebarButton()
        }
        .buttonStyle(.plain)
    }

    private func showContactPicker() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.vCard]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.title = "Import Contacts as Tags"
        panel.prompt = "Import"

        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            let content = try String(contentsOf: url, encoding: .utf8)
            pendingContactCount = parseVCardNames(content).count
            guard pendingContactCount > 0 else { return }
            showContactConfirm = true
        } catch {
            print("Failed to read vCard: \(error)")
        }
    }

    private func performContactImport() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.vCard]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.title = "Import Contacts as Tags"
        panel.prompt = "Import"

        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            let content = try String(contentsOf: url, encoding: .utf8)
            let names = parseVCardNames(content)
            guard !names.isEmpty else { return }

            let categoryName = "People"
            let category: TagCategory
            if let existing = viewModel.tagStore.categories.first(where: {
                $0.name.lowercased() == categoryName.lowercased()
            }) {
                category = existing
            } else {
                category = viewModel.tagStore.addCategory(name: categoryName)
            }

            for name in names {
                let existingTags = viewModel.tagStore.tags(in: category.id)
                if !existingTags.contains(where: { $0.name.lowercased() == name.lowercased() }) {
                    _ = viewModel.tagStore.addTag(name: name, categoryID: category.id)
                }
            }
        } catch {
            print("Failed to import contacts: \(error)")
        }
    }

    private func parseVCardNames(_ content: String) -> [String] {
        var names: [String] = []
        let lines = content.components(separatedBy: .newlines)
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.uppercased().hasPrefix("FN:") {
                let name = String(trimmed.dropFirst(3)).trimmingCharacters(in: .whitespacesAndNewlines)
                if !name.isEmpty { names.append(name) }
            } else if trimmed.uppercased().hasPrefix("FN;") {
                let parts = trimmed.split(separator: ":", maxSplits: 1)
                if parts.count == 2 {
                    let name = String(parts[1]).trimmingCharacters(in: .whitespacesAndNewlines)
                    if !name.isEmpty { names.append(name) }
                }
            }
        }
        return Array(Set(names)).sorted()
    }

    private var pendingSwitchLabel: String {
        guard let id = pendingSwitchID,
              let pack = viewModel.packLibrary.state(for: id)
        else { return "" }
        return "Switch to \(pack.name)?"
    }

    private var pendingDeleteName: String {
        guard let id = pendingDeleteID,
              let pack = viewModel.packLibrary.state(for: id)
        else { return "pack" }
        return pack.name
    }

    private var pendingResetName: String {
        guard let id = pendingResetID,
              let pack = viewModel.packLibrary.state(for: id)
        else { return "pack" }
        return pack.name
    }
}

private struct TagPackSidebarRow: View {
    let state: TagPackState
    let isActive: Bool
    let onActivate: () -> Void
    let onRename: () -> Void
    let onReset: () -> Void
    let onDuplicate: () -> Void
    let onDelete: () -> Void
    let onExport: () -> Void
    let onRestyle: () -> Void
    let onSetHotkey: () -> Void
    let onClearHotkey: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: onActivate) {
            HStack(spacing: Theme.Space.s10) {
                Image(systemName: state.systemImage)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Color(hex: state.accentColor) ?? Theme.Color.accent)
                    .frame(width: 18)

                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: Theme.Space.s6) {
                        Text(state.name)
                            .font(isActive ? Theme.Font.bodyBold : Theme.Font.body)
                            .foregroundStyle(isActive ? Theme.Color.textInverse : Theme.Color.textPrimary)
                            .lineLimit(1)
                            .truncationMode(.tail)
                        if !state.isBuiltIn {
                            Text("CUSTOM")
                                .font(.system(size: 9, weight: .heavy, design: .rounded))
                                .tracking(0.5)
                                .foregroundStyle(Theme.Color.textInverse)
                                .padding(.horizontal, 5)
                                .padding(.vertical, 1)
                                .background(Capsule().fill(Theme.Color.accent))
                                .fixedSize()
                        }
                    }
                    Text("\(state.tags.count) tags · \(state.categories.count) cats")
                        .font(Theme.Font.caption2)
                        .foregroundStyle(Theme.Color.textSecondary)
                        .lineLimit(1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                if isHovered {
                    Menu {
                        Button("Activate", action: onActivate)
                        Button("Export…", action: onExport)
                        Divider()
                        if let raw = state.hotkey, !raw.isEmpty {
                            Button("Hotkey: \(displayableShortcut(raw))") { onSetHotkey() }
                                .disabled(true)
                            Button("Change Hotkey…", action: onSetHotkey)
                            Button("Clear Hotkey", role: .destructive, action: onClearHotkey)
                        } else {
                            Button("Set Hotkey…", action: onSetHotkey)
                        }
                        Divider()
                        Button("Reset to Factory", action: onReset)
                        Button("Duplicate", action: onDuplicate)
                        if !state.isBuiltIn {
                            Divider()
                            Button("Logo & Color…", action: onRestyle)
                            Button("Rename…", action: onRename)
                            Button("Delete Pack", role: .destructive, action: onDelete)
                        } else {
                            Divider()
                            Button("Duplicate to Edit Logo", action: onDuplicate)
                        }
                    } label: {
                        Image(systemName: "ellipsis")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(Theme.Color.textSecondary)
                            .frame(width: 18, height: 18)
                            .contentShape(Rectangle())
                    }
                    .menuStyle(.borderlessButton)
                    .menuIndicator(.hidden)
                    .fixedSize()
                }
            }
            .padding(.horizontal, Theme.Space.s10)
            .padding(.vertical, Theme.Space.s8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .flatSidebarButton(
                isHovered: isHovered,
                isSelected: isActive,
                accentColor: Color(hex: state.accentColor) ?? Theme.Color.accent
            )
            .contentShape(RoundedRectangle(cornerRadius: Theme.Radius.m))
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            isHovered = hovering
        }
    }
}

/// Render a hotkey string like "shift+cmd+k" as something the user can
/// read in a menu ("⇧⌘K"). Falls back to the raw string if parsing fails.
private func displayableShortcut(_ raw: String) -> String {
    guard let info = KeyboardShortcutInfo.parse(raw) as KeyboardShortcutInfo?,
          !info.key.isEmpty else { return raw }
    var parts: [String] = []
    if info.control { parts.append("⌃") }
    if info.option  { parts.append("⌥") }
    if info.shift   { parts.append("⇧") }
    if info.command { parts.append("⌘") }
    parts.append(info.key.count == 1 ? info.key.uppercased() : info.key.capitalized)
    return parts.joined()
}

// MARK: - Tags detail panel (edge-to-edge)

private struct TagsDetailPanel: View {
    @ObservedObject var tagStore: TagStore
    @ObservedObject var viewModel: PhotoLibraryViewModel

    private let spine: CGFloat = Theme.Space.s24

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: Theme.Space.s20) {
                ForEach(tagStore.categories) { category in
                    CategorySection(
                        category: category,
                        tags: tagStore.tags(in: category.id),
                        tagStore: tagStore,
                        spine: spine
                    )
                    Divider()
                        .overlay(Theme.Color.surfaceDivider)
                }

                Button {
                    viewModel.tagStore.addCategory(name: "New Category")
                } label: {
                    Label("Add Category", systemImage: "plus.circle")
                        .font(Theme.Font.caption)
                }
                .buttonStyle(.borderless)
                .padding(.horizontal, spine)
            }
            .padding(.vertical, Theme.Space.s20)
        }
    }
}

private struct CategorySection: View {
    let category: TagCategory
    let tags: [CustomTag]
    @ObservedObject var tagStore: TagStore
    let spine: CGFloat

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.s12) {
            HStack(spacing: Theme.Space.s8) {
                Image(systemName: "folder.fill")
                    .foregroundStyle(Theme.Color.textSecondary)
                TextField("Category name", text: Binding(
                    get: { category.name },
                    set: { newName in
                        let trimmed = newName.trimmingCharacters(in: .whitespaces)
                        guard !trimmed.isEmpty else { return }
                        tagStore.renameCategory(id: category.id, to: trimmed)
                    }
                ))
                .textFieldStyle(.plain)
                .font(Theme.Font.bodyBold)
                .foregroundStyle(Theme.Color.textInverse)
                .frame(maxWidth: 220)

                Text("\(tags.count)")
                    .font(Theme.Font.caption)
                    .foregroundStyle(Theme.Color.textTertiary)

                if tags.isEmpty {
                    Button(role: .destructive) {
                        tagStore.deleteCategory(id: category.id)
                    } label: {
                        Image(systemName: "minus.circle.fill")
                            .font(.system(size: 13))
                            .foregroundStyle(Theme.Color.danger.opacity(0.8))
                    }
                    .buttonStyle(.borderless)
                    .help("Remove empty category")
                }

                Spacer()
            }
            .padding(.horizontal, spine)

            if tags.isEmpty {
                Text("No tags yet in this category.")
                    .font(Theme.Font.caption)
                    .foregroundStyle(Theme.Color.textTertiary)
                    .padding(.horizontal, spine)
            } else {
                LazyVGrid(columns: [
                    GridItem(.adaptive(minimum: 260), spacing: Theme.Space.s8)
                ], alignment: .leading, spacing: Theme.Space.s8) {
                    ForEach(tags) { tag in
                        TagChip(tag: tag, tagStore: tagStore)
                    }
                }
                .padding(.horizontal, spine)
            }

            HStack(spacing: Theme.Space.s8) {
                Button {
                    tagStore.addTag(name: "New Tag", categoryID: category.id)
                } label: {
                    Label("Add Tag to \(category.name)", systemImage: "plus")
                        .font(Theme.Font.caption)
                }
                .buttonStyle(.borderless)
                .controlSize(.small)
            }
            .padding(.horizontal, spine)
        }
    }
}

private struct TagChip: View {
    let tag: CustomTag
    @ObservedObject var tagStore: TagStore
    @State private var isHovered = false

    var body: some View {
        HStack(spacing: Theme.Space.s6) {
            TagColorPicker(tag: tag, tagStore: tagStore)
                .padding(.leading, Theme.Space.s4)
                .padding(.trailing, Theme.Space.s2)
                .padding(.vertical, Theme.Space.s4)

            TextField("", text: Binding(
                get: { tag.name },
                set: { newName in
                    var updated = tag
                    updated.name = newName
                    tagStore.updateTag(updated)
                }
            ))
            .textFieldStyle(.plain)
            .font(Theme.Font.caption)
            .foregroundStyle(Theme.Color.textInverse)
            .truncationMode(.middle)
            .frame(maxWidth: .infinity, alignment: .leading)

            Spacer()

            HStack(spacing: Theme.Space.s4) {
                ShortcutRecorderView(
                    hotkey: Binding(
                        get: { tag.hotkey },
                        set: { newValue in
                            var updated = tag
                            updated.hotkey = newValue
                            tagStore.updateTag(updated)
                        }
                    ),
                    validationMessage: { proposed in tagHotkeyConflict(proposed, for: tag, in: tagStore) },
                    isBorderless: true
                )
                .controlSize(.mini)
             
            }

            if isHovered {
                Button {
                    tagStore.deleteTag(id: tag.id)
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(Theme.Color.danger)
                        .font(.system(size: 15))
                }
                .buttonStyle(.borderless)
                .padding(.trailing, Theme.Space.s4)
            }
        }
        .padding(.horizontal, Theme.Space.s8)
        .padding(.vertical, Theme.Space.s8)
        .frame(minHeight: 36)
        .fixedSize(horizontal: false, vertical: true)
        .background(
            RoundedRectangle(cornerRadius: Theme.Radius.m)
                .fill(.ultraThinMaterial)
        )
        .overlay(
            RoundedRectangle(cornerRadius: Theme.Radius.m)
                .stroke(Color.white.opacity(0.04), lineWidth: Theme.Stroke.hairline)
        )
        .onHover { hovering in
            withAnimation(.spring(response: 0.25, dampingFraction: 1.0)) { isHovered = hovering }
        }
    }

    private func tagHotkeyConflict(_ hotkey: String, for tag: CustomTag, in tagStore: TagStore) -> String? {
        if let reason = TagHotkeyRules.reservedReason(for: hotkey) {
            return "Used by \(reason)"
        }
        if let other = tagStore.tags.first(where: { $0.id != tag.id && $0.hotkey == hotkey }) {
            return "Used by \(other.name)"
        }
        return nil
    }
}

private struct TagColorPicker: View {
    let tag: CustomTag
    @ObservedObject var tagStore: TagStore

    /// Inline color picker. The `ColorPicker` IS the swatch — tapping it
    /// opens the system color panel directly with no popover or button
    /// layer in between. Opacity is disabled so hex strings stay
    /// portable across the sidecar/JSON persistence path.
    var body: some View {
        ColorPicker("", selection: Binding(
            get: { tag.color },
            set: { newColor in
                var updated = tag
                updated.colorHex = newColor.toHex() ?? tag.colorHex
                tagStore.updateTag(updated)
            }
        ), supportsOpacity: false)
        .labelsHidden()
        .frame(width: 15, height: 15)
        .clipShape(Circle())
        .help("Change color")
    }
}

// MARK: - Sheets

private struct NewPackSheet: View {
    @ObservedObject var viewModel: PhotoLibraryViewModel
    @Binding var isPresented: Bool

    @State private var name: String = ""
    @State private var basedOnTemplateID: String = TagPackTemplate.defaultTemplateID
    @State private var draftSymbol: String = TagPackTemplate.general.systemImage
    @State private var draftAccent: Color = Color(hex: TagPackTemplate.general.accentColor) ?? Theme.Color.accent
    @State private var searchQuery: String = ""

    private let templates = TagPackTemplate.allTemplates

    private var filteredGroups: [PackSymbolCatalog.Group] {
        let q = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !q.isEmpty else { return PackSymbolCatalog.groups }
        return PackSymbolCatalog.groups.compactMap { group in
            let matches = group.symbols.filter { $0.lowercased().contains(q) }
            return matches.isEmpty ? nil : PackSymbolCatalog.Group(title: group.title, symbols: matches)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.s14) {
            Text("New Tag Pack")
                .font(Theme.Font.title)
                .foregroundStyle(Theme.Color.textInverse)

            Text("Pick a starting point. The pack will be added to your library and activated immediately.")
                .font(Theme.Font.subheadline)
                .foregroundStyle(Theme.Color.textSecondary)

            HStack(spacing: Theme.Space.s16) {
                VStack(alignment: .leading, spacing: Theme.Space.s6) {
                    Text("Name")
                        .font(Theme.Font.caption)
                        .foregroundStyle(Theme.Color.textSecondary)
                    TextField("e.g. Studio Portraits", text: $name)
                        .textFieldStyle(.plain)
                        .font(Theme.Font.body)
                        .padding(.horizontal, Theme.Space.s10)
                        .padding(.vertical, Theme.Space.s8)
                        .background(
                            RoundedRectangle(cornerRadius: Theme.Radius.m)
                                .fill(Theme.Color.surfaceRaised)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: Theme.Radius.m)
                                .stroke(Theme.Color.surfaceDivider, lineWidth: Theme.Stroke.hairline)
                        )
                }

                VStack(alignment: .leading, spacing: Theme.Space.s6) {
                    Text("Start from Template")
                        .font(Theme.Font.caption)
                        .foregroundStyle(Theme.Color.textSecondary)
                    Picker("Template", selection: $basedOnTemplateID) {
                        ForEach(templates) { template in
                            Text(template.name).tag(template.id)
                        }
                        Text("Empty").tag("__empty__")
                    }
                    .pickerStyle(.menu)
                    .frame(maxWidth: .infinity)
                }
            }
            .onChange(of: basedOnTemplateID) { _, newValue in
                guard let template = TagPackTemplate.template(id: newValue) else {
                    draftSymbol = "tag"
                    draftAccent = Theme.Color.accent
                    return
                }
                draftSymbol = template.systemImage
                draftAccent = Color(hex: template.accentColor) ?? Theme.Color.accent
            }

            VStack(alignment: .leading, spacing: Theme.Space.s8) {
                Text("Logo & Color")
                    .font(Theme.Font.caption)
                    .foregroundStyle(Theme.Color.textSecondary)

                HStack(spacing: Theme.Space.s8) {
                    Image(systemName: draftSymbol.isEmpty ? "questionmark.circle" : draftSymbol)
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(draftAccent)
                        .frame(width: 36, height: 36)
                        .background(
                            RoundedRectangle(cornerRadius: Theme.Radius.s)
                                .fill(draftAccent.opacity(0.18))
                        )
                    TextField("Custom SF Symbol name, e.g. leaf.fill", text: $draftSymbol)
                        .textFieldStyle(.roundedBorder)
                        .controlSize(.regular)
                        .font(Theme.Font.caption)

                    ColorPicker(selection: $draftAccent, supportsOpacity: false) {
                        HStack(spacing: Theme.Space.s6) {
                            Capsule()
                                .fill(draftAccent)
                                .frame(width: 20, height: 20)
                            Text(draftAccent.toHex() ?? "—")
                                .font(Theme.Font.caption)
                                .foregroundStyle(Theme.Color.textInverse)
                        }
                        .padding(.horizontal, Theme.Space.s8)
                        .padding(.vertical, Theme.Space.s4)
                        .background(Capsule().fill(Theme.Color.surfaceRaised))
                    }
                    .labelsHidden()
                }

                HStack(spacing: Theme.Space.s8) {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(Theme.Color.textTertiary)
                        .font(Theme.Font.caption2)
                    TextField("Search built-in logo choices", text: $searchQuery)
                        .textFieldStyle(.plain)
                        .font(Theme.Font.caption)
                    if !searchQuery.isEmpty {
                        Button {
                            searchQuery = ""
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundStyle(Theme.Color.textTertiary)
                                .font(Theme.Font.caption2)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, Theme.Space.s8)
                .padding(.vertical, 5)
                .background(
                    RoundedRectangle(cornerRadius: Theme.Radius.s)
                        .fill(Theme.Color.surfaceRaised)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: Theme.Radius.s)
                        .stroke(Theme.Color.surfaceDivider, lineWidth: Theme.Stroke.hairline)
                )
            }

            ScrollView {
                LazyVStack(alignment: .leading, spacing: Theme.Space.s12) {
                    ForEach(filteredGroups) { group in
                        VStack(alignment: .leading, spacing: Theme.Space.s6) {
                            Text(group.title)
                                .font(Theme.Font.caption2)
                                .tracking(0.3)
                                .foregroundStyle(Theme.Color.textTertiary)
                            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 8),
                                      alignment: .leading,
                                      spacing: 6) {
                                ForEach(group.symbols, id: \.self) { symbol in
                                    symbolButton(symbol)
                                }
                            }
                        }
                    }
                    if filteredGroups.isEmpty {
                        Text("No curated matches. Type any SF Symbol name above.")
                            .font(Theme.Font.caption2)
                            .foregroundStyle(Theme.Color.textTertiary)
                            .padding(.top, Theme.Space.s8)
                    }
                }
                .padding(.vertical, 4)
            }
            .frame(maxHeight: 180)
            .scrollIndicators(.visible)

            HStack {
                Button("Cancel") { isPresented = false }
                    .buttonStyle(.bordered)
                    .controlSize(.large)
                Spacer()
                Button("Create & Activate") { commit() }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .tint(draftAccent)
                    .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(Theme.Space.s24)
        .frame(width: 520, height: 600)
        .background(Theme.Color.surfaceBase)
    }

    private func symbolButton(_ symbol: String) -> some View {
        let isSelected = draftSymbol == symbol
        return Button {
            draftSymbol = symbol
        } label: {
            Image(systemName: symbol)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(isSelected ? .white : Theme.Color.textPrimary)
                .frame(width: 32, height: 32)
                .background(
                    RoundedRectangle(cornerRadius: Theme.Radius.s)
                        .fill(isSelected ? draftAccent : Theme.Color.surfaceRaised)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: Theme.Radius.s)
                        .stroke(isSelected ? draftAccent : Theme.Color.surfaceDivider,
                                lineWidth: isSelected ? 1.5 : Theme.Stroke.hairline)
                )
        }
        .buttonStyle(.plain)
    }

    private func commit() {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let symbol = draftSymbol.trimmingCharacters(in: .whitespacesAndNewlines)
        let icon = symbol.isEmpty ? "tag" : symbol
        let accent = draftAccent.toHex() ?? "#4A90E2"
        if basedOnTemplateID == "__empty__" {
            _ = viewModel.createPack(named: trimmed, systemImage: icon, accentColor: accent)
        } else {
            _ = viewModel.createPack(named: trimmed, basedOnTemplateID: basedOnTemplateID, systemImage: icon, accentColor: accent)
        }
        // Activate whatever pack was just created (last in the list).
        if let last = viewModel.packLibrary.packs.last {
            viewModel.switchTagPack(id: last.id)
        }
        isPresented = false
    }
}

private struct RenamePackSheet: View {
    let currentName: String
    @Binding var isPresented: Bool
    let onCommit: (String) -> Void

    @State private var draft: String = ""

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.s14) {
            Text("Rename Pack")
                .font(Theme.Font.title)
                .foregroundStyle(Theme.Color.textInverse)

            TextField("Pack name", text: $draft)
                .textFieldStyle(.plain)
                .font(Theme.Font.body)
                .padding(.horizontal, Theme.Space.s10)
                .padding(.vertical, Theme.Space.s8)
                .background(
                    RoundedRectangle(cornerRadius: Theme.Radius.m)
                        .fill(Theme.Color.surfaceRaised)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: Theme.Radius.m)
                        .stroke(Theme.Color.surfaceDivider, lineWidth: Theme.Stroke.hairline)
                )
                .onAppear { draft = currentName }

            HStack {
                Spacer()
                Button("Cancel") { isPresented = false }
                    .buttonStyle(.bordered)
                    .controlSize(.large)
                Button("Save") {
                    onCommit(draft.trimmingCharacters(in: .whitespacesAndNewlines))
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .tint(Theme.Color.accent)
                .disabled(draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(Theme.Space.s24)
        .frame(width: 420)
        .background(Theme.Color.surfaceBase)
    }
}

// MARK: - Pack style (logo + accent color)

/// Curated catalog of SF Symbols that read well as a tag-pack logo. Grouped
/// by intent so the picker stays scannable. Users can also type or paste any SF
/// Symbol name in the search field to use one not in the catalog.
private enum PackSymbolCatalog {
    struct Group: Identifiable {
        let id = UUID()
        let title: String
        let symbols: [String]
    }

    static let groups: [Group] = [
        Group(title: "People & Places", symbols: [
            "person.crop.circle", "person.2", "person.crop.square",
            "house", "building.2", "globe", "map", "mountain.2"
        ]),
        Group(title: "Moments & Mood", symbols: [
            "heart", "heart.fill", "star", "star.fill", "sparkles",
            "sun.max", "moon.stars", "cloud.rain", "leaf", "flame"
        ]),
        Group(title: "Activities", symbols: [
            "camera", "camera.fill", "video", "mic", "music.note",
            "sportscourt", "figure.run", "bicycle", "sailboat",
            "airplane", "car", "tram"
        ]),
        Group(title: "Objects & Work", symbols: [
            "tag", "tag.fill", "folder", "tray.full", "shippingbox",
            "briefcase", "hammer", "wrench.adjustable", "paintpalette",
            "pencil.and.list.clipboard", "doc.text", "calendar"
        ]),
        Group(title: "Tech & Media", symbols: [
            "iphone", "macbook", "desktopcomputer", "tv", "gamecontroller",
            "headphones", "antenna.radiowaves.left.and.right",
            "wifi", "bolt", "bubble.left.and.bubble.right"
        ])
    ]

    /// Flat list of every curated symbol — used for instant search.
    static var allSymbols: [String] {
        groups.flatMap { $0.symbols }
    }
}

private struct PackStyleSheet: View {
    let state: TagPackState
    @Binding var isPresented: Bool
    let onCommit: (_ systemImage: String, _ accentColor: String) -> Void

    @State private var draftSymbol: String = ""
    @State private var draftAccent: Color
    @State private var searchQuery: String = ""

    init(state: TagPackState,
         isPresented: Binding<Bool>,
         onCommit: @escaping (String, String) -> Void) {
        self.state = state
        self._isPresented = isPresented
        self.onCommit = onCommit
        _draftSymbol = State(initialValue: state.systemImage)
        _draftAccent = State(initialValue: Color(hex: state.accentColor) ?? Theme.Color.accent)
    }

    private var filteredGroups: [PackSymbolCatalog.Group] {
        let q = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !q.isEmpty else { return PackSymbolCatalog.groups }
        return PackSymbolCatalog.groups.compactMap { group in
            let matches = group.symbols.filter { $0.lowercased().contains(q) }
            return matches.isEmpty ? nil : PackSymbolCatalog.Group(title: group.title, symbols: matches)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.s16) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Logo & Color")
                        .font(Theme.Font.headline)
                        .foregroundStyle(Theme.Color.textPrimary)
                    Text("Choose from the grid, or type any SF Symbol name for “\(state.name)”.")
                        .font(Theme.Font.caption)
                        .foregroundStyle(Theme.Color.textSecondary)
                }
                Spacer()
                preview
            }

            Divider().overlay(Theme.Color.surfaceDivider)

            HStack(spacing: Theme.Space.s12) {
                Text("Accent")
                    .font(Theme.Font.caption)
                    .foregroundStyle(Theme.Color.textSecondary)
                    .frame(width: 64, alignment: .leading)
                ColorPicker(selection: $draftAccent, supportsOpacity: false) {
                    HStack(spacing: Theme.Space.s8) {
                        Capsule()
                            .fill(draftAccent)
                            .frame(width: 22, height: 22)
                            .overlay(
                                Capsule()
                                    .stroke(Color.white.opacity(0.25), lineWidth: 1)
                            )
                        Text(draftAccent.toHex() ?? "—")
                            .font(Theme.Font.caption)
                            .foregroundStyle(Theme.Color.textInverse)
                        Image(systemName: "chevron.down")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(Theme.Color.textTertiary)
                    }
                    .padding(.horizontal, Theme.Space.s10)
                    .padding(.vertical, Theme.Space.s6)
                    .background(
                        Capsule().fill(Theme.Color.surfaceRaised)
                    )
                    .overlay(
                        Capsule()
                            .stroke(Theme.Color.surfaceDivider, lineWidth: Theme.Stroke.hairline)
                    )
                }
                .labelsHidden()
                .help("Click to choose a color from the system picker")

                Spacer()
            }

            VStack(alignment: .leading, spacing: Theme.Space.s8) {
                Text("Logo")
                    .font(Theme.Font.caption)
                    .foregroundStyle(Theme.Color.textSecondary)

                HStack(spacing: Theme.Space.s8) {
                    Image(systemName: draftSymbol.isEmpty ? "questionmark.circle" : draftSymbol)
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(draftAccent)
                        .frame(width: 36, height: 36)
                        .background(
                            RoundedRectangle(cornerRadius: Theme.Radius.s)
                                .fill(draftAccent.opacity(0.18))
                        )
                    TextField("Custom SF Symbol name, e.g. leaf.fill", text: $draftSymbol)
                        .textFieldStyle(.roundedBorder)
                        .controlSize(.regular)
                        .font(Theme.Font.caption)
                        .onSubmit { commit() }
                }

                HStack(spacing: Theme.Space.s8) {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(Theme.Color.textTertiary)
                        .font(Theme.Font.caption2)
                    TextField("Search built-in logo choices", text: $searchQuery)
                        .textFieldStyle(.plain)
                        .font(Theme.Font.caption)
                    if !searchQuery.isEmpty {
                        Button {
                            searchQuery = ""
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundStyle(Theme.Color.textTertiary)
                                .font(Theme.Font.caption2)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, Theme.Space.s8)
                .padding(.vertical, 5)
                .background(
                    RoundedRectangle(cornerRadius: Theme.Radius.s)
                        .fill(Theme.Color.surfaceRaised)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: Theme.Radius.s)
                        .stroke(Theme.Color.surfaceDivider, lineWidth: Theme.Stroke.hairline)
                )
            }

            ScrollView {
                LazyVStack(alignment: .leading, spacing: Theme.Space.s12) {
                    ForEach(filteredGroups) { group in
                        VStack(alignment: .leading, spacing: Theme.Space.s6) {
                            Text(group.title)
                                .font(Theme.Font.caption2)
                                .tracking(0.3)
                                .foregroundStyle(Theme.Color.textTertiary)
                            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 8),
                                      alignment: .leading,
                                      spacing: 6) {
                                ForEach(group.symbols, id: \.self) { symbol in
                                    symbolButton(symbol)
                                }
                            }
                        }
                    }
                    if filteredGroups.isEmpty {
                        Text("No curated matches. Type any SF Symbol name above (e.g. “leaf.fill”, “camera.macro”).")
                            .font(Theme.Font.caption2)
                            .foregroundStyle(Theme.Color.textTertiary)
                            .padding(.top, Theme.Space.s8)
                    }
                }
                .padding(.vertical, 4)
            }
            .frame(maxHeight: 280)
            .scrollIndicators(.visible)

            HStack {
                Button("Cancel") { isPresented = false }
                    .keyboardShortcut(.cancelAction)
                Spacer()
                Button("Save") { commit() }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .tint(draftAccent)
                    .keyboardShortcut(.defaultAction)
                    .disabled(draftSymbol.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(Theme.Space.s20)
        .frame(width: 520, height: 560)
        .background(Theme.Color.surfaceBase)
    }

    private var preview: some View {
        ZStack {
            RoundedRectangle(cornerRadius: Theme.Radius.m)
                .fill(draftAccent.opacity(0.18))
                .frame(width: 48, height: 48)
            Image(systemName: draftSymbol.isEmpty ? "questionmark.circle" : draftSymbol)
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(draftAccent)
        }
    }

    private func symbolButton(_ symbol: String) -> some View {
        let isSelected = draftSymbol == symbol
        return Button {
            draftSymbol = symbol
        } label: {
            Image(systemName: symbol)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(isSelected ? .white : Theme.Color.textPrimary)
                .frame(width: 32, height: 32)
                .background(
                    RoundedRectangle(cornerRadius: Theme.Radius.s)
                        .fill(isSelected ? draftAccent : Theme.Color.surfaceRaised)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: Theme.Radius.s)
                        .stroke(isSelected ? draftAccent : Theme.Color.surfaceDivider,
                                lineWidth: isSelected ? 1.5 : Theme.Stroke.hairline)
                )
        }
        .buttonStyle(.plain)
        .help(symbol)
    }

    private func commit() {
        let trimmed = draftSymbol.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let hex = draftAccent.toHex() ?? state.accentColor
        onCommit(trimmed, hex)
    }
}

// MARK: - Pack hotkey sheet
//
// Lets the user assign (or clear) the activation hotkey for a tag pack.
// Reuses `ShortcutRecorderView` so the keyboard-capture + collision-
// detection logic is shared with the per-tag shortcut recorders. The
// `onCommit` closure receives `nil` if the user wants to clear the
// binding, or the raw hotkey string otherwise.

private struct PackHotkeySheet: View {
    let state: TagPackState
    let currentHotkey: String?
    @Binding var isPresented: Bool
    /// Called with the new hotkey string (or nil to clear). Empty
    /// string is treated as nil.
    let onCommit: (String?) -> Void

    @State private var draft: String?
    @State private var collisionMessage: String?

    init(state: TagPackState,
         currentHotkey: String?,
         isPresented: Binding<Bool>,
         onCommit: @escaping (String?) -> Void) {
        self.state = state
        self.currentHotkey = currentHotkey
        self._isPresented = isPresented
        self.onCommit = onCommit
        _draft = State(initialValue: currentHotkey)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.s16) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Pack Hotkey")
                        .font(Theme.Font.headline)
                        .foregroundStyle(Theme.Color.textPrimary)
                    Text("Press any key combo to assign it to “\(state.name)”. Leave blank for no hotkey.")
                        .font(Theme.Font.caption)
                        .foregroundStyle(Theme.Color.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer()
            }

            Divider().overlay(Theme.Color.surfaceDivider)

            HStack(spacing: Theme.Space.s12) {
                Text("Hotkey")
                    .font(Theme.Font.caption)
                    .foregroundStyle(Theme.Color.textSecondary)
                    .frame(width: 64, alignment: .leading)
                ShortcutRecorderView(
                    hotkey: $draft,
                    validationMessage: { raw in
                        // Reject empty bindings as the recorder can leave
                        // the field blank after a backspace. Collision
                        // detection against other packs is the library's
                        // job (it re-assigns cleanly when we commit).
                        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
                        guard !trimmed.isEmpty else { return nil }
                        return nil
                    }
                )
                Spacer()
            }

            if let collisionMessage {
                Text(collisionMessage)
                    .font(Theme.Font.caption2)
                    .foregroundStyle(Theme.Color.warning)
            }

            HStack {
                Button("Cancel") { isPresented = false }
                    .keyboardShortcut(.cancelAction)
                Spacer()
                if currentHotkey != nil {
                    Button("Clear Hotkey", role: .destructive) {
                        onCommit(nil)
                        isPresented = false
                    }
                }
                Button(currentHotkey == nil ? "Set Hotkey" : "Save") {
                    let raw = draft?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                    onCommit(raw.isEmpty ? nil : raw)
                    isPresented = false
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .tint(Theme.Color.accent)
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(Theme.Space.s20)
        .frame(width: 460)
        .background(Theme.Color.surfaceBase)
    }
}

fileprivate extension View {
    func flatSidebarButton(
        isHovered: Bool = false,
        isSelected: Bool = false,
        accentColor: Color = Theme.Color.accent
    ) -> some View {
        self
            .ifTrue(isSelected) { view in
                view.glassEffect(.regular.interactive(), in: .rect(cornerRadius: Theme.Radius.m))
            }
            .ifTrue(!isSelected && isHovered) { view in
                view.glassEffect(.regular, in: .rect(cornerRadius: Theme.Radius.m))
            }
            .animation(.spring(response: 0.18, dampingFraction: 1.0), value: isSelected)
            .animation(.spring(response: 0.15, dampingFraction: 1.0), value: isHovered)
            .padding(.vertical, 1)
            .contentShape(RoundedRectangle(cornerRadius: Theme.Radius.m))
    }
}

