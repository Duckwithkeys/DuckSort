//
//  SettingsShortcutsPaneView.swift
//  DuckSort
//
//  The "Shortcuts" tab of the unified Settings window.
//  Three sections: App Actions (editable), Culling Control (static reference),
//  and Tag Hotkeys (static reference, hidden when no tags exist).
//

import SwiftUI

private enum ShortcutsSection: String, CaseIterable, Identifiable {
    case appActions    = "App Actions"
    case culling       = "Culling Control"
    case tagHotkeys    = "Tag Hotkeys"

    var id: String { rawValue }

    var systemImage: String {
        switch self {
        case .appActions: return "gearshape"
        case .culling:    return "arrow.left.arrow.right"
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
        VStack(spacing: 0) {
            HStack {
                Text("SECTIONS")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(dsColor("#8A8A8E"))
                    .tracking(0.3)
                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.top, 10)
            .padding(.bottom, 6)

            ForEach(ShortcutsSection.allCases) { section in
                let isDisabled = section == .tagHotkeys && !tagHotkeysAvailable
                shortcutIndexRow(
                    icon: section.systemImage,
                    label: section.rawValue,
                    isSelected: selectedSection == section,
                    isDisabled: isDisabled
                ) {
                    guard !isDisabled else { return }
                    withAnimation(.easeInOut(duration: 0.18)) {
                        selectedSection = section
                    }
                }
            }

            Spacer()
        }
    }

    @ViewBuilder
    private func shortcutIndexRow(
        icon: String,
        label: String,
        isSelected: Bool,
        isDisabled: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.system(size: 11))
                    .foregroundStyle(isSelected ? .white : dsColor("#8A8A8E"))
                    .frame(width: 14)
                Text(label)
                    .font(.system(size: 13, weight: isSelected ? .bold : .regular))
                    .foregroundStyle(isSelected ? .white : dsColor("#AEAEB2"))
                Spacer()
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(
                isSelected ? dsColor("#0A84FF") : Color.clear
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(isDisabled)
        .opacity(isDisabled ? 0.4 : 1.0)
    }
}

// MARK: - Right detail panel

private struct ShortcutsDetailContent: View {
    @ObservedObject var viewModel: PhotoLibraryViewModel
    let section: ShortcutsSection

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                switch section {
                case .appActions:
                    ShortcutsSectionHeader(title: "APP ACTIONS")

                    ShortcutEditableRow(label: "Toggle JPEG Only Mode", hotkey: $viewModel.jpegOnlyHotkey)

                case .culling:
                    ShortcutsSectionHeader(title: "CULLING CONTROL")

                    ShortcutStaticRow(label: "Toggle Selection",       shortcut: "S")
                    ShortcutDividerRow()
                    ShortcutStaticRow(label: "Clear All Tags",         shortcut: "0")
                    ShortcutDividerRow()
                    ShortcutStaticRow(label: "Open / Close Viewer",    shortcut: "Space / Return")
                    ShortcutDividerRow()
                    ShortcutStaticRow(label: "Close Viewer",           shortcut: "Esc")
                    ShortcutDividerRow()
                    ShortcutStaticRow(label: "Navigate Photos",        shortcut: "← → ↑ ↓")
                    ShortcutDividerRow()
                    ShortcutStaticRow(label: "Next / Prev Category",   shortcut: "Tab / ⇧Tab")
                    ShortcutDividerRow()
                    ShortcutStaticRow(label: "Select Visible (Grid)",  shortcut: "⌘A")
                    ShortcutDividerRow()
                    ShortcutStaticRow(label: "Flag / Reject / Unflag", shortcut: "Z / X / U")
                    ShortcutDividerRow()
                    ShortcutStaticRow(label: "Set Rating",             shortcut: "1 – 5")

                case .tagHotkeys:
                    ShortcutsSectionHeader(title: "TAG HOTKEYS")
                    let allTags = viewModel.tagStore.tags
                    if allTags.isEmpty {
                        Text("No tags yet. Create tags in the Tags tab to assign hotkeys.")
                            .font(.system(size: 13))
                            .foregroundStyle(dsColor("#636366"))
                            .padding(.horizontal, 16)
                            .padding(.vertical, 12)
                    } else {
                        let groups = ShortcutsDetailContent.groupedByCategory(
                            allTags,
                            categoryName: { viewModel.tagStore.categoryName(id: $0) ?? "Uncategorized" }
                        )
                        ForEach(Array(groups.enumerated()), id: \.offset) { groupIndex, group in
                            if groupIndex > 0 { ShortcutDividerRow() }
                            ShortcutsSectionHeader(title: group.categoryName.uppercased())

                            ForEach(Array(group.tags.enumerated()), id: \.element.id) { tagIndex, tag in
                                if tagIndex > 0 { ShortcutDividerRow() }
                                TagHotkeyRow(tag: tag, tagStore: viewModel.tagStore)
                            }
                        }
                    }
                }

                Spacer().frame(height: 20)
            }
        }
        .background(dsColor("#1E1E1E"))
    }
}

// MARK: - Reusable row components

private struct ShortcutsSectionHeader: View {
    let title: String
    var body: some View {
        HStack {
            Text(title)
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(dsColor( "#636366"))
                .tracking(0.3)
                .padding(.leading, 16)
            Spacer()
        }
        .padding(.vertical, 8)
        .background(dsColor( "#232323"))
    }
}

private struct ShortcutEditableRow: View {
    let label: String
    @Binding var hotkey: String?

    var body: some View {
        HStack {
            Text(label)
                .font(.system(size: 13))
                .foregroundStyle(.white)
                .padding(.leading, 16)
            Spacer()
            ShortcutRecorderView(hotkey: $hotkey)
                .padding(.trailing, 16)
        }
        .frame(height: 40)
    }
}

private struct ShortcutStaticRow: View {
    let label: String
    let shortcut: String

    var body: some View {
        HStack {
            Text(label)
                .font(.system(size: 13))
                .foregroundStyle(.white)
                .padding(.leading, 16)
            Spacer()
            Text(shortcut)
                .font(.system(size: 12, design: .monospaced))
                .foregroundStyle(dsColor( "#636366"))
                .padding(.trailing, 16)
        }
        .frame(height: 36)
    }
}

private struct ShortcutDividerRow: View {
    var body: some View {
        Rectangle()
            .fill(dsColor("#2C2C2E"))
            .frame(height: 1)
            .padding(.horizontal, 16)
    }
}

// MARK: - Tag hotkey row (bindable)

private struct TagHotkeyRow: View {
    let tag: CustomTag
    @ObservedObject var tagStore: TagStore

    var body: some View {
        HStack {
            HStack(spacing: 8) {
                Circle()
                    .fill(tag.color)
                    .frame(width: 8, height: 8)
                Text(tag.name)
                    .font(.system(size: 13))
                    .foregroundStyle(.white)
            }
            .padding(.leading, 16)
            Spacer()
            ShortcutRecorderView(hotkey: Binding(
                get: { tag.hotkey },
                set: { newValue in
                    var updated = tag
                    updated.hotkey = newValue
                    tagStore.updateTag(updated)
                }
            ))
            .padding(.trailing, 16)
        }
        .frame(height: 40)
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
