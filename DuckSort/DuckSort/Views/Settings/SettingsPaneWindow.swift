//
//  SettingsPaneWindow.swift
//  DuckSort
//
//  Unified Safari-style preferences window. Hosts Rules, Tags, and Shortcuts
//  panes behind a segmented top toolbar. Resizable.
//

import SwiftUI
import AppKit

// MARK: - Tab Enum

enum SettingsTab: String, CaseIterable {
    case rules      = "Rules"
    case tags       = "Tags"
    case xmpTags    = "XMP Tags"
    case copyright  = "Copyright"
    case shortcuts  = "Shortcuts"
    case autoTagging = "Mode Switching"

    var systemImage: String {
        switch self {
        case .rules:      return "folder.badge.gearshape"
        case .tags:       return "tag"
        case .xmpTags:    return "doc.badge.plus"
        case .copyright:  return "c.circle"
        case .shortcuts:  return "keyboard.badge.ellipsis"
        case .autoTagging: return "slider.horizontal.3"
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
            SettingsToolbar(selectedTab: $selectedTab)

            Rectangle()
                .fill(Theme.Color.surfaceDivider)
                .frame(height: Theme.Stroke.hairline)

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
                case .xmpTags:
                    SettingsXMPTagsPane(
                        viewModel: viewModel,
                        tagStore: viewModel.tagStore
                    )
                case .copyright:
                    SettingsIPTCPaneView(preferences: UserPreferences.shared)
                case .shortcuts:
                    SettingsShortcutsPaneView(viewModel: viewModel)
                case .autoTagging:
                    SettingsAutoTaggingPaneView(
                        preferences: UserPreferences.shared,
                        tagStore: viewModel.tagStore
                    )
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(minWidth: 820, idealWidth: 960, minHeight: 560, idealHeight: 720)
        .background(Theme.Color.surfaceBase)
        .onAppear { selectedTab = initialTab }
    }
}

// MARK: - Toolbar

private struct SettingsToolbar: View {
    @Binding var selectedTab: SettingsTab

    var body: some View {
        GlassEffectContainer(spacing: Theme.Space.s8) {
            HStack(spacing: Theme.Space.s8) {
                Spacer()
                ForEach(SettingsTab.allCases, id: \.self) { tab in
                    SettingsTabButton(tab: tab, isSelected: selectedTab == tab) {
                        selectedTab = tab
                    }
                }
                Spacer()
            }
        }
        .padding(.top, Theme.Space.s6)
        .padding(.bottom, Theme.Space.s10)
        .frame(maxWidth: .infinity)
        .background(Theme.Color.surfaceBase)
    }
}

private struct SettingsTabButton: View {
    let tab: SettingsTab
    let isSelected: Bool
    let action: () -> Void
    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            VStack(spacing: Theme.Space.s4) {
                Image(systemName: tab.systemImage)
                    .font(.system(size: 22, weight: .light))
                    .frame(width: 24, height: 24)
                Text(tab.rawValue)
                    .font(Theme.Font.subheadline)
            }
            .foregroundStyle(isSelected ? Theme.Color.textInverse : Theme.Color.textTertiary)
            .padding(.horizontal, Theme.Space.s20)
            .padding(.vertical, Theme.Space.s4)
            .liquidGlassTabHighlight(isSelected: isSelected, isHovered: isHovered)
            .contentShape(RoundedRectangle(cornerRadius: Theme.Radius.l))
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
    }
}

// MARK: - Button Styles
//
// Replaced by SwiftUI's built-in `.bordered` and `.borderedProminent` styles
// wherever the previous custom styles were used. If a one-off capsule button
// is needed elsewhere, prefer `.buttonStyle(.borderedProminent)` and let
// SwiftUI handle keyboard focus + accent color.

// MARK: - Shared Settings Layout: Sidebar + Right Panel

struct SettingsSplitLayout<Sidebar: View, Detail: View>: View {
    @ViewBuilder var sidebar: () -> Sidebar
    @ViewBuilder var detail: () -> Detail

    var body: some View {
        HStack(spacing: 0) {
            sidebar()
                .frame(width: 200)
                .background(Theme.Color.surfaceSidebar)

            Rectangle()
                .fill(Theme.Color.surfaceDivider)
                .frame(width: Theme.Stroke.hairline)

            detail()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Theme.Color.surfaceBase)
        }
    }
}

fileprivate extension View {
    func liquidGlassTabHighlight(isSelected: Bool, isHovered: Bool) -> some View {
        self
            .ifTrue(isSelected) { view in
                view.glassEffect(.regular.interactive(), in: .rect(cornerRadius: Theme.Radius.l))
            }
            .ifTrue(!isSelected && isHovered) { view in
                view.glassEffect(.regular, in: .rect(cornerRadius: Theme.Radius.l))
            }
            .padding(.vertical, 1)
    }
}
