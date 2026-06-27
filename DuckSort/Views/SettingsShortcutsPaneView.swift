//
//  SettingsShortcutsPaneView.swift
//  DuckSort
//
//  The "Shortcuts" tab of the unified Settings window.
//  Overhauled to match the premium dark macOS design system.
//

import SwiftUI

private enum ShortcutsSection: String, CaseIterable, Identifiable {
    case appActions    = "App & Windows"
    case culling       = "Culling & Navigation"
    case tagHotkeys    = "Tag Hotkeys"

    var id: String { rawValue }

    var systemImage: String {
        switch self {
        case .appActions: return "gearshape.fill"
        case .culling:    return "arrow.left.arrow.right"
        case .tagHotkeys: return "tag.fill"
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
        VStack(spacing: Theme.Space.s4) {
            HStack {
                Text("SHORTCUT CATEGORIES")
                    .font(Theme.Font.caption2)
                    .tracking(0.5)
                    .foregroundStyle(Theme.Color.textTertiary)
                Spacer()
            }
            .padding(.horizontal, Theme.Space.s12)
            .padding(.top, Theme.Space.s12)
            .padding(.bottom, Theme.Space.s6)

            ForEach(ShortcutsSection.allCases) { section in
                let isDisabled = section == .tagHotkeys && !tagHotkeysAvailable
                shortcutIndexRow(
                    icon: section.systemImage,
                    label: section.rawValue,
                    isSelected: selectedSection == section,
                    isDisabled: isDisabled
                ) {
                    guard !isDisabled else { return }
                    withAnimation(.smooth(duration: 0.15)) {
                        selectedSection = section
                    }
                }
            }

            Spacer()
        }
    }

    private func shortcutIndexRow(
        icon: String,
        label: String,
        isSelected: Bool,
        isDisabled: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: Theme.Space.s10) {
                Image(systemName: icon)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(isSelected ? .white : Theme.Color.textSecondary)
                    .frame(width: 18)

                Text(label)
                    .font(isSelected ? Theme.Font.bodyBold : Theme.Font.body)
                    .foregroundStyle(isSelected ? Theme.Color.textInverse : Theme.Color.textPrimary)
                Spacer()
            }
            .padding(.horizontal, Theme.Space.s10)
            .padding(.vertical, Theme.Space.s8)
            .background(
                RoundedRectangle(cornerRadius: Theme.Radius.m)
                    .fill(isSelected ? Theme.Color.accent : Color.clear)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.horizontal, Theme.Space.s8)
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
            VStack(alignment: .leading, spacing: Theme.Space.s16) {
                switch section {
                case .appActions:
                    headerView(
                        title: "App & Window Shortcuts",
                        subtitle: "Review system window commands and application shortcuts."
                    )

                    cardSection(title: "System Commands") {
                        VStack(spacing: 0) {
                            ShortcutStaticRow(label: "Open Settings Window", shortcut: "⌘ ,")
                            ShortcutDividerRow()
                            ShortcutStaticRow(label: "Import Media Files", shortcut: "⇧ ⌘ I")
                            ShortcutDividerRow()
                            ShortcutStaticRow(label: "Toggle Advanced EXIF Inspector", shortcut: "⇧ ⌘ E")
                            ShortcutDividerRow()
                            ShortcutStaticRow(label: "Unmapped XMP Tags Inspector", shortcut: "⇧ ⌘ X")
                            ShortcutDividerRow()
                            ShortcutStaticRow(label: "Show Welcome Guide", shortcut: "⌘ /")
                        }
                    }

                case .culling:
                    headerView(
                        title: "Culling & Navigation",
                        subtitle: "Keyboard controls for browsing, selecting, flagging, and rating photos."
                    )

                    cardSection(title: "Navigation & Viewer") {
                        VStack(spacing: 0) {
                            ShortcutStaticRow(label: "Navigate Grid / Viewer", shortcut: "←  →  ↑  ↓")
                            ShortcutDividerRow()
                            ShortcutStaticRow(label: "Open Large Image Viewer", shortcut: "Space / Return / I")
                            ShortcutDividerRow()
                            ShortcutStaticRow(label: "Close Large Image Viewer", shortcut: "Esc / Space / Return")
                            ShortcutDividerRow()
                            ShortcutStaticRow(label: "Cycle Active Tag Category", shortcut: "[ / ]")
                        }
                    }

                    cardSection(title: "Selection Controls") {
                        VStack(spacing: 0) {
                            ShortcutStaticRow(label: "Toggle Selection (Focused Photo)", shortcut: "S")
                            ShortcutDividerRow()
                            ShortcutStaticRow(label: "Select All Visible Photos", shortcut: "⌘ A")
                            ShortcutDividerRow()
                            ShortcutStaticRow(label: "Clear Active Selection", shortcut: "Esc / Backspace / Delete")
                        }
                    }

                    cardSection(title: "Flagging & Star Ratings") {
                        VStack(spacing: 0) {
                            ShortcutStaticRow(label: "Flag Pick (Favorite)", shortcut: "Z")
                            ShortcutDividerRow()
                            ShortcutStaticRow(label: "Flag Reject & Advance", shortcut: "X")
                            ShortcutDividerRow()
                            ShortcutStaticRow(label: "Unflag Photo", shortcut: "U")
                            ShortcutDividerRow()
                            ShortcutStaticRow(label: "Set Star Rating (1 to 5 Stars)", shortcut: "1 – 5")
                            ShortcutDividerRow()
                            ShortcutStaticRow(label: "Clear Rating, Pick & Tags", shortcut: "0")
                        }
                    }

                case .tagHotkeys:
                    headerView(
                        title: "Tag Hotkeys",
                        subtitle: "Assign custom single-key or modifier hotkeys for one-touch tag application."
                    )

                    let allTags = viewModel.tagStore.tags
                    if allTags.isEmpty {
                        VStack(spacing: Theme.Space.s12) {
                            Image(systemName: "tag.slash")
                                .font(.system(size: 32))
                                .foregroundStyle(Theme.Color.textTertiary)
                            Text("No Tags Created Yet")
                                .font(Theme.Font.headline)
                                .foregroundStyle(Theme.Color.textSecondary)
                            Text("Create tags in the Tags tab to assign custom application hotkeys.")
                                .font(Theme.Font.caption)
                                .foregroundStyle(Theme.Color.textTertiary)
                                .multilineTextAlignment(.center)
                        }
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.vertical, Theme.Space.s32)
                    } else {
                        let groups = ShortcutsDetailContent.groupedByCategory(
                            allTags,
                            categoryName: { viewModel.tagStore.categoryName(id: $0) ?? "Uncategorized" }
                        )
                        ForEach(groups, id: \.categoryName) { group in
                            cardSection(title: group.categoryName.uppercased()) {
                                VStack(spacing: 0) {
                                    ForEach(Array(group.tags.enumerated()), id: \.element.id) { index, tag in
                                        if index > 0 { ShortcutDividerRow() }
                                        TagHotkeyRow(tag: tag, tagStore: viewModel.tagStore)
                                    }
                                }
                            }
                        }
                    }
                }
            }
            .padding(Theme.Space.s20)
        }
        .background(Theme.Color.surfaceBase)
    }

    private func headerView(title: String, subtitle: String) -> some View {
        VStack(alignment: .leading, spacing: Theme.Space.s4) {
            Text(title)
                .font(Theme.Font.title)
                .foregroundStyle(Theme.Color.textPrimary)
            Text(subtitle)
                .font(Theme.Font.body)
                .foregroundStyle(Theme.Color.textSecondary)
        }
        .padding(.bottom, Theme.Space.s4)
    }

    private func cardSection<Content: View>(title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: Theme.Space.s6) {
            Text(title)
                .font(Theme.Font.caption2)
                .tracking(0.5)
                .foregroundStyle(Theme.Color.textTertiary)
                .padding(.leading, Theme.Space.s4)

            VStack(spacing: 0) {
                content()
            }
            .background(
                RoundedRectangle(cornerRadius: Theme.Radius.l)
                    .fill(Theme.Color.cellBackground)
            )
            .overlay(
                RoundedRectangle(cornerRadius: Theme.Radius.l)
                    .stroke(Theme.Color.separator, lineWidth: Theme.Stroke.hairline)
            )
        }
    }
}

// MARK: - Reusable row components

private struct ShortcutStaticRow: View {
    let label: String
    let shortcut: String

    var body: some View {
        HStack {
            Text(label)
                .font(Theme.Font.body)
                .foregroundStyle(Theme.Color.textPrimary)
                .padding(.leading, Theme.Space.s16)
            Spacer()
            Text(shortcut)
                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                .foregroundStyle(Theme.Color.textSecondary)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Theme.Color.surfaceRaised, in: RoundedRectangle(cornerRadius: Theme.Radius.s))
                .overlay(
                    RoundedRectangle(cornerRadius: Theme.Radius.s)
                        .stroke(Theme.Color.surfaceDivider, lineWidth: Theme.Stroke.hairline)
                )
                .padding(.trailing, Theme.Space.s16)
        }
        .frame(height: 44)
    }
}

private struct ShortcutDividerRow: View {
    var body: some View {
        Rectangle()
            .fill(Theme.Color.separator)
            .frame(height: Theme.Stroke.hairline)
            .padding(.horizontal, Theme.Space.s16)
    }
}

// MARK: - Tag hotkey row (bindable)

private struct TagHotkeyRow: View {
    let tag: CustomTag
    @ObservedObject var tagStore: TagStore

    var body: some View {
        HStack {
            HStack(spacing: Theme.Space.s8) {
                Circle()
                    .fill(tag.color)
                    .frame(width: 8, height: 8)
                Text(tag.name)
                    .font(Theme.Font.body)
                    .foregroundStyle(Theme.Color.textPrimary)
            }
            .padding(.leading, Theme.Space.s16)
            Spacer()
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
            .padding(.trailing, Theme.Space.s16)
        }
        .frame(height: 44)
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
