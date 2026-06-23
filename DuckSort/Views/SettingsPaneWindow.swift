//
//  SettingsPaneWindow.swift
//  DuckSort
//
//  Unified Safari-style preferences window. Hosts Rules, Tags, and Shortcuts
//  panes behind a segmented top toolbar. Fixed 720×480, non-resizable.
//

import SwiftUI
import AppKit

// MARK: - Tab Enum

enum SettingsTab: String, CaseIterable {
    case rules      = "Rules"
    case tags       = "Tags"
    case shortcuts  = "Shortcuts"

    var systemImage: String {
        switch self {
        case .rules:     return "folder.badge.gearshape"
        case .tags:      return "tag"
        case .shortcuts: return "keyboard.badge.ellipsis"
        }
    }
}

// MARK: - Root Settings View

struct SettingsPaneView: View {
    @ObservedObject var viewModel: PhotoLibraryViewModel
    var initialTab: SettingsTab = .rules
    var onClose: () -> Void = {}

    @State private var selectedTab: SettingsTab = .rules

    var body: some View {
        VStack(spacing: 0) {
            // ── Top Toolbar ──────────────────────────────────────────────────
            SettingsToolbar(selectedTab: $selectedTab)

            // ── Divider ──────────────────────────────────────────────────────
            Rectangle()
                .fill(dsColor("#323232"))
                .frame(height: 1)

            // ── Body ─────────────────────────────────────────────────────────
            Group {
                switch selectedTab {
                case .rules:
                    SettingsRulesPaneView(
                        ruleStore: viewModel.ruleStore,
                        tagStore: viewModel.tagStore
                    )
                case .tags:
                    SettingsTagsPaneView(
                        viewModel: viewModel,
                        tagStore: viewModel.tagStore
                    )
                case .shortcuts:
                    SettingsShortcutsPaneView(viewModel: viewModel)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            if selectedTab == .tags {
                Rectangle()
                    .fill(dsColor("#323232"))
                    .frame(height: 1)
                SettingsFooter(
                    tagStore: viewModel.tagStore
                )
            }
        }
.frame(minWidth: 720, minHeight: 480)
        .background(dsColor( "#1E1E1E"))
        .onAppear { selectedTab = initialTab }
    }
}


// MARK: - Toolbar

private struct SettingsToolbar: View {
    @Binding var selectedTab: SettingsTab

    var body: some View {
        HStack(spacing: 0) {
            Spacer()
            ForEach(SettingsTab.allCases, id: \.self) { tab in
                SettingsTabButton(tab: tab, isSelected: selectedTab == tab) {
                    withAnimation(.easeInOut(duration: 0.18)) {
                        selectedTab = tab
                    }
                }
            }
            Spacer()
        }
        .padding(.top, 6)
        .padding(.bottom, 10)
        .frame(maxWidth: .infinity)
        .background(dsColor("#1E1E1E"))
    }
}

private struct SettingsTabButton: View {
    let tab: SettingsTab
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 3) {
                Image(systemName: tab.systemImage)
                    .font(.system(size: 22, weight: .light))
                    .frame(width: 24, height: 24)
                Text(tab.rawValue)
                    .font(.system(size: 11))
            }
            .foregroundStyle(isSelected ? Color.white : dsColor("#8A8A8E"))
            .padding(.horizontal, 18)
            .padding(.vertical, 4)
            .background(
                isSelected
                    ? RoundedRectangle(cornerRadius: 8).fill(Color.white.opacity(0.10))
                    : RoundedRectangle(cornerRadius: 8).fill(Color.clear)
            )
            .contentShape(RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
        .animation(.easeInOut(duration: 0.18), value: isSelected)
    }
}

// MARK: - Footer

private struct SettingsFooter: View {
    @ObservedObject var tagStore: TagStore

    var body: some View {
        Button(action: importContacts) {
            Text("Import Contacts…")
                .font(.system(size: 13))
        }
        .buttonStyle(OutlineButtonStyle())
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(dsColor("#1E1E1E"))
    }

    private func importContacts() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.vCard]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.title = "Import Contacts as Tags"
        panel.prompt = "Import"

        if panel.runModal() == .OK, let url = panel.url {
            do {
                let content = try String(contentsOf: url, encoding: .utf8)
                let names = parseVCardNames(content)
                guard !names.isEmpty else { return }

                let categoryName = "People"
                let category: TagCategory
                if let existing = tagStore.categories.first(where: {
                    $0.name.lowercased() == categoryName.lowercased()
                }) {
                    category = existing
                } else {
                    category = tagStore.addCategory(name: categoryName)
                }

                for name in names {
                    let existingTags = tagStore.tags(in: category.id)
                    if !existingTags.contains(where: { $0.name.lowercased() == name.lowercased() }) {
                        _ = tagStore.addTag(name: name, categoryID: category.id)
                    }
                }
            } catch {
                print("Failed to import contacts: \(error)")
            }
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
}

// MARK: - Button Styles

struct AccentCapsuleButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13, weight: .medium))
            .foregroundStyle(.white)
            .padding(.horizontal, 20)
            .padding(.vertical, 6)
            .background(
                Capsule().fill(
                    configuration.isPressed
                        ? dsColor("#0060D0")
                        : dsColor("#0A84FF")
                )
            )
            .animation(.easeInOut(duration: 0.1), value: configuration.isPressed)
    }
}

struct OutlineButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13))
            .foregroundStyle(dsColor("#8A8A8E"))
            .padding(.horizontal, 12)
            .padding(.vertical, 5)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(dsColor("#3C3C3E"), lineWidth: 1)
                    .background(
                        RoundedRectangle(cornerRadius: 6)
                            .fill(configuration.isPressed
                                  ? Color.white.opacity(0.06)
                                  : Color.clear)
                    )
            )
            .animation(.easeInOut(duration: 0.1), value: configuration.isPressed)
    }
}

// MARK: - Shared Settings Layout: Sidebar + Right Panel

struct SettingsSplitLayout<Sidebar: View, Detail: View>: View {
    @ViewBuilder var sidebar: () -> Sidebar
    @ViewBuilder var detail: () -> Detail

    var body: some View {
        HStack(spacing: 0) {
            // Left sidebar — fixed 200px, deep slate
            sidebar()
                .frame(width: 200)
                .background(Color(hex: "#161616"))

            // 1px separator
            Rectangle()
                .fill(dsColor("#323232"))
                .frame(width: 1)

            // Right detail panel
            detail()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(dsColor("#1E1E1E"))
        }
    }
}

// MARK: - Private hex color helper (avoids redeclaring Color.init(hex:) from CustomTag.swift)
// dsColor() is a file-private shorthand used throughout the Settings UI files.

func dsColor(_ hex: String) -> Color {
    Color(hex: hex) ?? .black
}
