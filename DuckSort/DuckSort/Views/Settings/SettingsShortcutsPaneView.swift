//
//  SettingsShortcutsPaneView.swift
//  DuckSort
//
//  Native macOS Shortcuts settings pane with sidebar List and grouped Form.
//

import SwiftUI

private enum ShortcutsSection: String, CaseIterable, Identifiable, Hashable {
    case appActions = "App & Windows"
    case culling    = "Culling & Navigation"
    case tagHotkeys = "Tag Hotkeys"

    var id: String { rawValue }

    var systemImage: String {
        switch self {
        case .appActions: return "macwindow"
        case .culling:    return "arrow.left.arrow.right.square"
        case .tagHotkeys: return "tag"
        }
    }
}

struct SettingsShortcutsPaneView: View {
    @ObservedObject var viewModel: PhotoLibraryViewModel
    @State private var selectedSection: ShortcutsSection = .appActions

    var body: some View {
        SettingsSplitLayout {
            ShortcutsSidebarIndex(
                selectedSection: $selectedSection,
                tagHotkeysAvailable: !viewModel.tagStore.tags.isEmpty
            )
        } detail: {
            ShortcutsDetailContent(
                viewModel: viewModel,
                section: selectedSection
            )
        }
    }
}

// MARK: - Left sidebar: section index

private struct ShortcutsSidebarIndex: View {
    @Binding var selectedSection: ShortcutsSection
    let tagHotkeysAvailable: Bool

    var body: some View {
        List(selection: $selectedSection) {
            Section("Shortcut Categories") {
                ForEach(ShortcutsSection.allCases) { section in
                    Label(section.rawValue, systemImage: section.systemImage)
                        .tag(section)
                }
            }
        }
        .listStyle(.sidebar)
    }
}

// MARK: - Right detail panel

private struct ShortcutsDetailContent: View {
    @ObservedObject var viewModel: PhotoLibraryViewModel
    let section: ShortcutsSection

    var body: some View {
        Form {
            switch section {
            case .appActions:
                Section {
                    ShortcutStaticRow(label: "Open Settings Window", shortcut: "⌘ ,")
                    ShortcutStaticRow(label: "Import Media Files", shortcut: "⇧ ⌘ I")
                    ShortcutStaticRow(label: "Toggle Advanced EXIF Inspector", shortcut: "⇧ ⌘ E")
                    ShortcutStaticRow(label: "Show Welcome Guide", shortcut: "⌘ /")
                } header: {
                    Text("System Commands")
                }

                Section {
                    LabeledContent("Add Source Folder") {
                        ShortcutRecorderView(hotkey: $viewModel.openSourceHotkey)
                    }
                    LabeledContent("Edit in Photomator") {
                        ShortcutRecorderView(hotkey: $viewModel.photomatorHotkey)
                    }
                } header: {
                    Text("Customizable App & Editor Shortcuts")
                }

            case .culling:
                Section {
                    ShortcutStaticRow(label: "Navigate Grid / Viewer", shortcut: "←  →  ↑  ↓")
                    ShortcutStaticRow(label: "Open Large Image Viewer", shortcut: "Space / Return / I")
                    ShortcutStaticRow(label: "Compare Selected Photos (2-Up / 4-Up)", shortcut: "Space / Return / I")
                    ShortcutStaticRow(label: "Close Large Image Viewer", shortcut: "Esc / Space / Return")
                    ShortcutStaticRow(label: "Cycle Active Tag Category", shortcut: "[ / ]")
                } header: {
                    Text("Navigation & Viewer")
                }

                Section {
                    ShortcutStaticRow(label: "Toggle Selection (Focused Photo)", shortcut: "S")
                    ShortcutStaticRow(label: "Select All Visible Photos", shortcut: "⌘ A")
                    ShortcutStaticRow(label: "Clear Active Selection", shortcut: "Esc / Delete")
                } header: {
                    Text("Selection Controls")
                }

                Section {
                    ShortcutStaticRow(label: "Flag Pick (Favorite)", shortcut: "Z")
                    ShortcutStaticRow(label: "Flag Reject & Advance", shortcut: "X")
                    ShortcutStaticRow(label: "Unflag Photo", shortcut: "U")
                    ShortcutStaticRow(label: "Set Star Rating (1 to 5 Stars)", shortcut: "1 – 5")
                    ShortcutStaticRow(label: "Clear Rating, Pick & Tags", shortcut: "0")
                } header: {
                    Text("Flagging & Star Ratings")
                }

            case .tagHotkeys:
                let allTags = viewModel.tagStore.tags
                if allTags.isEmpty {
                    Section {
                        ContentUnavailableView(
                            "No Tags Created Yet",
                            systemImage: "tag.slash",
                            description: Text("Create tags in the Tags tab to assign custom single-key or modifier hotkeys.")
                        )
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 24)
                    }
                } else {
                    let groups = ShortcutsDetailContent.groupedByCategory(
                        allTags,
                        categoryName: { viewModel.tagStore.categoryName(id: $0) ?? "Uncategorized" }
                    )
                    ForEach(groups, id: \.categoryName) { group in
                        Section(group.categoryName) {
                            ForEach(group.tags) { tag in
                                TagHotkeyRow(tag: tag, tagStore: viewModel.tagStore)
                            }
                        }
                    }
                }
            }
        }
        .formStyle(.grouped)
    }
}

// MARK: - Reusable row components

private struct ShortcutStaticRow: View {
    let label: String
    let shortcut: String

    var body: some View {
        LabeledContent(label) {
            Text(shortcut)
                .font(.system(size: 11, weight: .medium, design: .monospaced))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(
                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                        .fill(Color(nsColor: .controlBackgroundColor))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                        .strokeBorder(Color(nsColor: .separatorColor), lineWidth: 1)
                )
        }
    }
}

// MARK: - Tag hotkey row (bindable)

private struct TagHotkeyRow: View {
    let tag: CustomTag
    @ObservedObject var tagStore: TagStore

    var body: some View {
        LabeledContent {
            ShortcutRecorderView(
                hotkey: Binding(
                    get: { tag.hotkey },
                    set: { newValue in
                        var updated = tag
                        updated.hotkey = newValue
                        tagStore.updateTag(updated)
                    }
                ),
                validationMessage: { proposed in
                    if let reason = TagHotkeyRules.reservedReason(for: proposed) {
                        return "Used by \(reason)"
                    }
                    if let other = tagStore.tags.first(where: { $0.id != tag.id && $0.hotkey == proposed }) {
                        return "Used by \(other.name)"
                    }
                    return nil
                }
            )
        } label: {
            HStack(spacing: 8) {
                Circle()
                    .fill(tag.color)
                    .frame(width: 9, height: 9)
                Text(tag.name)
            }
        }
    }
}

// MARK: - Grouping helper

extension ShortcutsDetailContent {
    struct CategoryGroup {
        let categoryID: UUID?
        let categoryName: String
        let tags: [CustomTag]
    }

    static func groupedByCategory(
        _ tags: [CustomTag],
        categoryName: (UUID) -> String
    ) -> [CategoryGroup] {
        let buckets = Dictionary(grouping: tags, by: \.categoryID)
        return buckets
            .map { (id, tags) in
                CategoryGroup(
                    categoryID: id,
                    categoryName: categoryName(id),
                    tags: tags.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
                )
            }
            .sorted { lhs, rhs in
                if lhs.categoryName == "Uncategorized" { return false }
                if rhs.categoryName == "Uncategorized" { return true }
                return lhs.categoryName.localizedCaseInsensitiveCompare(rhs.categoryName) == .orderedAscending
            }
    }
}
