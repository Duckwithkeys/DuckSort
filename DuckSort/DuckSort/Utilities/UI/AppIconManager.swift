//
//  AppIconManager.swift
//  DuckSort
//
//  Manages dynamic dock / application icon switching according to
//  system light/dark appearance and user preferences.
//

import AppKit
import SwiftUI

@MainActor
final class AppIconManager: ObservableObject {
    static let shared = AppIconManager()

    private var isConfigured = false

    private init() {}

    /// Starts observing system appearance changes and applies the active icon.
    func startObserving() {
        guard !isConfigured else { return }
        isConfigured = true

        updateDockIcon()

        // Observe effective appearance changes on NSApplication
        NotificationCenter.default.addObserver(
            forName: NSApplication.didBecomeActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.updateDockIcon()
            }
        }

        // Distributed notification for macOS system-wide theme changes
        DistributedNotificationCenter.default().addObserver(
            forName: NSNotification.Name("AppleInterfaceThemeChangedNotification"),
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.updateDockIcon()
            }
        }
    }

    /// Updates the application dock icon based on UserPreferences icon selection
    /// and current system dark/light appearance.
    func updateDockIcon() {
        let style = UserPreferences.shared.appIconStyle

        let isDark: Bool
        switch style {
        case .system:
            if let appearance = NSApp?.effectiveAppearance {
                isDark = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            } else {
                let appearanceName = UserDefaults.standard.string(forKey: "AppleInterfaceStyle")
                isDark = (appearanceName == "Dark")
            }
        case .dark:
            isDark = true
        case .light:
            isDark = false
        }

        let imageName = isDark ? "AppIcon-Dark" : "AppIcon-Light"

        if let image = loadIconImage(named: imageName) {
            NSApplication.shared.applicationIconImage = image
        }
    }

    private func loadIconImage(named name: String) -> NSImage? {
        // 1. Bundle resources search
        if let url = Bundle.main.url(forResource: name, withExtension: "png", subdirectory: "AppIcons") ??
                     Bundle.main.url(forResource: name, withExtension: "png") ??
                     Bundle.main.url(forResource: name, withExtension: "icns") {
            return NSImage(contentsOf: url)
        }

        // 2. Relative search inside standard application bundle layout
        let bundlePath = Bundle.main.bundlePath
        let possiblePaths = [
            bundlePath + "/Contents/Resources/" + name + ".png",
            bundlePath + "/Contents/Resources/AppIcons/" + name + ".png",
            bundlePath + "/Contents/Resources/" + name + ".icns"
        ]

        for path in possiblePaths {
            if FileManager.default.fileExists(atPath: path), let img = NSImage(contentsOfFile: path) {
                return img
            }
        }

        // 3. Fallback to bundled Asset catalog if needed
        return NSImage(named: name)
    }
}
