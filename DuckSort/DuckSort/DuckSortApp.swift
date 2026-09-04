//
//  PhotomatorSortApp.swift
//  PhotomatorSort
//

import SwiftUI
import AppKit

class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSSetUncaughtExceptionHandler { exception in
            AppLogger.ui.fault("CRASH: Uncaught exception: \(exception.name.rawValue) - \(exception.reason ?? "")\nStack trace: \(exception.callStackSymbols.joined(separator: "\n"))")
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return true
    }
}

@main
struct DuckSortApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    
    // Observe shared state so menu commands reflect customizable hotkeys and
    // enable/disable as the active library appears.
    @ObservedObject private var windowManager = FloatingWindowManager.shared
    @ObservedObject private var preferences = UserPreferences.shared

    init() {
        NSApplication.shared.setActivationPolicy(.regular)
        NSApplication.shared.activate(ignoringOtherApps: true)
        NSWindow.allowsAutomaticWindowTabbing = false
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .commands {
            SidebarCommands()
            TextEditingCommands()

            CommandMenu("Sort") {
                ForEach(PhotoLibraryViewModel.SortOption.allCases) { option in
                    Button {
                        FloatingWindowManager.shared.activeViewModel?.sortOption = option
                    } label: {
                        if FloatingWindowManager.shared.activeViewModel?.sortOption == option {
                            Text("✓ " + option.rawValue)
                        } else {
                            Text(option.rawValue)
                        }
                    }
                    .disabled(!windowManager.isReady)
                }
            }

            CommandGroup(after: .sidebar) {
                Toggle("Show Advanced EXIF", isOn: Binding(
                    get: { preferences.showAdvancedEXIF },
                    set: { newValue in
                        preferences.showAdvancedEXIF = newValue
                        preferences.save()
                    }
                ))
                .keyboardShortcut("e", modifiers: [.command, .shift])
                .disabled(!windowManager.isReady)

                Button("Activity Console...") {
                    FloatingWindowManager.shared.showLogConsole()
                }
                .keyboardShortcut("c", modifiers: [.command, .shift])
                .disabled(!windowManager.isReady)
            }

            CommandGroup(after: .newItem) {
                Button("Add Source Folder...") {
                    FloatingWindowManager.shared.activeViewModel?.addSourceDirectory()
                }
                .optionalKeyboardShortcut(KeyboardShortcutInfo.parse(preferences.openSourceHotkey).keyboardShortcut)
                .disabled(!windowManager.isReady)

                Button("Import...") {
                    FloatingWindowManager.shared.activeViewModel?.importItems()
                }
                .keyboardShortcut("i", modifiers: [.command, .shift])
                .disabled(!windowManager.isReady)
            }

            // Tag-pack switching is intentionally menu-less. The user
            // sets an optional activation hotkey per pack through the
            // ellipsis (•••) menu in Settings → Tags. By default, packs
            // have no hotkey, so the menu bar stays uncluttered.

            CommandGroup(replacing: .appSettings) {
                Button("Settings…") {
                    if let vm = FloatingWindowManager.shared.activeViewModel {
                        FloatingWindowManager.shared.showSettings(viewModel: vm)
                    }
                }
                .keyboardShortcut(",", modifiers: .command)
                .disabled(!windowManager.isReady)
            }

            // Custom Help menu so users can re-run the onboarding wizard
            // from the menu bar after the first launch.
            CommandGroup(replacing: .help) {
                Button("Show Welcome Guide…") {
                    NotificationCenter.default.post(
                        name: .ducksortShowOnboarding,
                        object: nil
                    )
                }
                .keyboardShortcut("/", modifiers: .command)
            }
        }
    }
}

extension Notification.Name {
    static let ducksortShowOnboarding = Notification.Name("ducksortShowOnboarding")
}
