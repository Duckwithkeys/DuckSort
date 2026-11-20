//
//  FloatingWindowManager.swift
//  PhotomatorSort
//
//  Central manager for lightweight, floating utility windows.
//

import SwiftUI
import AppKit

final class FloatingPanel<Content: View>: NSPanel {
    init(title: String, content: Content, width: CGFloat, height: CGFloat, isResizable: Bool = true, hideTrafficLights: Bool = false) {
        var style: NSWindow.StyleMask = [.titled, .closable, .miniaturizable]
        if isResizable {
            style.insert(.resizable)
        }

        super.init(
            contentRect: NSRect(x: 0, y: 0, width: width, height: height),
            styleMask: style,
            backing: .buffered,
            defer: false
        )

        self.title = title
        self.level = .floating
        self.isFloatingPanel = false
        self.hidesOnDeactivate = false
        self.titlebarAppearsTransparent = false
        self.titleVisibility = .visible

        let hostingView = NSHostingView(rootView: content)
        self.contentView = hostingView

        self.center()

        if hideTrafficLights {
            self.standardWindowButton(.closeButton)?.isHidden = true
            self.standardWindowButton(.miniaturizeButton)?.isHidden = true
            self.standardWindowButton(.zoomButton)?.isHidden = true
        }
    }

    override var canBecomeKey: Bool {
        return true
    }
}

@MainActor
final class FloatingWindowManager: ObservableObject {
    static let shared = FloatingWindowManager()

    weak var activeViewModel: PhotoLibraryViewModel? {
        didSet { isReady = (activeViewModel != nil) }
    }

    /// Drives `.disabled` state for menu commands that require an active library.
    @Published private(set) var isReady = false

    private var settingsController: NSWindowController?
    private var settingsNavigationModel: SettingsNavigationModel?
    private var settingsToolbarDelegate: SettingsToolbarDelegate?
    private var logConsoleController: NSWindowController?

    private init() {}

    func showSettings(viewModel: PhotoLibraryViewModel, initialTab: SettingsTab = .rules) {
        if let controller = settingsController, let win = controller.window {
            settingsNavigationModel?.selectedTab = initialTab
            win.toolbar?.selectedItemIdentifier = initialTab.toolbarIdentifier
            win.title = initialTab.rawValue
            controller.showWindow(nil)
            NSApp.activate()
            return
        }

        let navModel = SettingsNavigationModel(selectedTab: initialTab)
        self.settingsNavigationModel = navModel

        let view = SettingsPaneView(
            viewModel: viewModel,
            initialTab: initialTab,
            navigationModel: navModel,
            onClose: { [weak self] in self?.settingsController?.close() }
        )

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 860, height: 620),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = initialTab.rawValue
        window.titlebarAppearsTransparent = false
        window.titleVisibility = .visible
        window.toolbarStyle = .preference
        window.isMovableByWindowBackground = false
        window.minSize = NSSize(width: 760, height: 520)
        window.backgroundColor = .windowBackgroundColor

        let toolbarDelegate = SettingsToolbarDelegate { [weak window, weak navModel] tab in
            navModel?.selectedTab = tab
            window?.title = tab.rawValue
        }
        self.settingsToolbarDelegate = toolbarDelegate

        let toolbar = NSToolbar(identifier: NSToolbar.Identifier("DuckSortSettingsToolbar"))
        toolbar.delegate = toolbarDelegate
        toolbar.allowsUserCustomization = false
        toolbar.displayMode = .iconAndLabel
        toolbar.selectedItemIdentifier = initialTab.toolbarIdentifier
        window.toolbar = toolbar

        let hosting = NSHostingView(rootView: AnyView(view))
        hosting.frame = NSRect(x: 0, y: 0, width: 860, height: 620)
        hosting.autoresizingMask = [.width, .height]
        window.contentView = hosting
        window.center()

        let delegate = PanelDelegate { [weak self] in
            self?.settingsController = nil
            self?.settingsNavigationModel = nil
            self?.settingsToolbarDelegate = nil
        }
        window.delegate = delegate
        window.setAssociatedDelegate(delegate)

        let controller = NSWindowController(window: window)
        self.settingsController = controller
        controller.showWindow(nil)
        NSApp.activate()
    }

    func showLogConsole() {
        if let controller = logConsoleController {
            controller.showWindow(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let view = LogConsoleView()

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 800, height: 500),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Activity Console"
        window.isMovableByWindowBackground = true
        window.minSize = NSSize(width: 700, height: 400)
        window.center()

        let hosting = NSHostingView(rootView: view)
        hosting.autoresizingMask = [.width, .height]
        window.contentView = hosting

        let delegate = PanelDelegate { [weak self] in
            self?.logConsoleController = nil
        }
        window.delegate = delegate
        window.setAssociatedDelegate(delegate)

        let controller = NSWindowController(window: window)
        self.logConsoleController = controller
        controller.showWindow(nil)
        NSApp.activate()
    }

    func closeAll() {
        settingsController?.close()
        logConsoleController?.close()
    }
}

@MainActor
private final class SettingsToolbarDelegate: NSObject, NSToolbarDelegate {
    private let onSelectTab: (SettingsTab) -> Void

    init(onSelectTab: @escaping (SettingsTab) -> Void) {
        self.onSelectTab = onSelectTab
    }

    func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        SettingsTab.allCases.map(\.toolbarIdentifier)
    }

    func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        SettingsTab.allCases.map(\.toolbarIdentifier)
    }

    func toolbarSelectableItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        SettingsTab.allCases.map(\.toolbarIdentifier)
    }

    func toolbar(
        _ toolbar: NSToolbar,
        itemForItemIdentifier itemIdentifier: NSToolbarItem.Identifier,
        willBeInsertedIntoToolbar flag: Bool
    ) -> NSToolbarItem? {
        guard let tab = SettingsTab.allCases.first(where: { $0.toolbarIdentifier == itemIdentifier }) else {
            return nil
        }
        let item = NSToolbarItem(itemIdentifier: itemIdentifier)
        item.label = tab.rawValue
        item.paletteLabel = tab.rawValue
        item.toolTip = tab.rawValue
        item.image = NSImage(systemSymbolName: tab.systemImage, accessibilityDescription: tab.rawValue)
        item.target = self
        item.action = #selector(handleToolbarItemSelected(_:))
        return item
    }

    @objc private func handleToolbarItemSelected(_ sender: NSToolbarItem) {
        guard let tab = SettingsTab.allCases.first(where: { $0.toolbarIdentifier == sender.itemIdentifier }) else {
            return
        }
        onSelectTab(tab)
    }
}

// MARK: - Delegate to retain delegate instance
nonisolated(unsafe) private var delegateKey: UInt8 = 0

extension NSWindow {
    func setAssociatedDelegate(_ delegate: NSWindowDelegate) {
        objc_setAssociatedObject(self, &delegateKey, delegate, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
    }
}

private final class PanelDelegate: NSObject, NSWindowDelegate {
    private let onClose: () -> Void
    
    init(onClose: @escaping () -> Void) {
        self.onClose = onClose
    }
    
    func windowWillClose(_ notification: Notification) {
        onClose()
    }
}
