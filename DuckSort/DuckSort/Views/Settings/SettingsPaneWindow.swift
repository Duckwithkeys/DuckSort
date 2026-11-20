//
//  SettingsPaneWindow.swift
//  DuckSort
//
//  Unified macOS Settings window hosted with a native NSToolbar (.preference style).
//

import SwiftUI
import AppKit

// MARK: - Tab Enum

enum SettingsTab: String, CaseIterable, Identifiable {
    case rules       = "Rules"
    case tags        = "Tags"
    case copyright   = "Copyright"
    case shortcuts   = "Shortcuts"
    case autoTagging = "Mode Switching"
    case appearance  = "Appearance"

    var id: String { rawValue }

    var systemImage: String {
        switch self {
        case .rules:       return "folder.badge.gearshape"
        case .tags:        return "tag"
        case .copyright:   return "c.circle"
        case .shortcuts:   return "keyboard"
        case .autoTagging: return "slider.horizontal.3"
        case .appearance:  return "paintpalette"
        }
    }

    var toolbarIdentifier: NSToolbarItem.Identifier {
        NSToolbarItem.Identifier(rawValue)
    }
}

@MainActor
final class SettingsNavigationModel: ObservableObject {
    @Published var selectedTab: SettingsTab

    init(selectedTab: SettingsTab = .rules) {
        self.selectedTab = selectedTab
    }
}

// MARK: - Root Settings View

struct SettingsPaneView: View {
    @ObservedObject var viewModel: PhotoLibraryViewModel
    @ObservedObject var navigationModel: SettingsNavigationModel
    var onClose: () -> Void = {}

    init(
        viewModel: PhotoLibraryViewModel,
        initialTab: SettingsTab = .rules,
        navigationModel: SettingsNavigationModel? = nil,
        onClose: @escaping () -> Void = {}
    ) {
        self.viewModel = viewModel
        self.navigationModel = navigationModel ?? SettingsNavigationModel(selectedTab: initialTab)
        self.onClose = onClose
    }

    var body: some View {
        Group {
            switch navigationModel.selectedTab {
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
            case .copyright:
                SettingsIPTCPaneView(preferences: UserPreferences.shared)
            case .shortcuts:
                SettingsShortcutsPaneView(viewModel: viewModel)
            case .autoTagging:
                SettingsAutoTaggingPaneView(
                    preferences: UserPreferences.shared,
                    tagStore: viewModel.tagStore
                )
            case .appearance:
                SettingsAppearancePaneView(preferences: UserPreferences.shared)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .frame(minWidth: 760, idealWidth: 860, minHeight: 520, idealHeight: 620)
        .background(Color(nsColor: .windowBackgroundColor))
    }
}

// MARK: - Shared Settings Layout: Sidebar + Right Panel

struct SettingsSplitLayout<Sidebar: View, Detail: View>: View {
    @ViewBuilder var sidebar: () -> Sidebar
    @ViewBuilder var detail: () -> Detail

    var body: some View {
        HStack(spacing: 0) {
            sidebar()
                .frame(width: 215)
                .background(Color(nsColor: .underPageBackgroundColor))

            Divider()

            detail()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color(nsColor: .windowBackgroundColor))
        }
    }
}
