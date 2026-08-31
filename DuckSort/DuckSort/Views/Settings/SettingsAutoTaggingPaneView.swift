//
//  SettingsAutoTaggingPaneView.swift
//  DuckSort
//
//  Settings tab for configuring AI Modes: On-Device AI Vision Auto-Tagging
//  and Perceptual Burst Deduplication & Best Shot AI, with configurable hotkeys.
//

import SwiftUI

struct SettingsAutoTaggingPaneView: View {
    @ObservedObject var preferences: UserPreferences
    @ObservedObject var tagStore: TagStore

    var body: some View {
        Form {
            Section {
                HStack(spacing: Theme.Space.s12) {
                    Image(systemName: "brain.head.profile")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(Theme.Color.accent)
                        .frame(width: 24)

                    Toggle("Enable AI Vision Auto-Tagging", isOn: $preferences.autoTaggingEnabled)
                        .toggleStyle(.switch)
                }

                if preferences.autoTaggingEnabled {
                    HStack {
                        Text("Shortcut Hotkey")
                        Spacer()
                        ShortcutRecorderView(hotkey: $preferences.aiVisionHotkey)
                    }

                    HStack {
                        Label("100% On-Device & Private", systemImage: "checkmark.shield.fill")
                            .font(Theme.Font.caption)
                            .foregroundStyle(Theme.Color.success)
                    }
                }
            } header: {
                Text("AI Vision Auto-Tagging")
            } footer: {
                Text("Automatically analyzes and suggests scene, object, and subject tags using local Apple Vision frameworks without sending data to the cloud.")
                    .foregroundStyle(.secondary)
            }

            Section {
                HStack(spacing: Theme.Space.s12) {
                    Image(systemName: "bolt.fill")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(Theme.Color.accent)
                        .frame(width: 24)

                    Toggle("Enable Speed Culling", isOn: $preferences.speedCullingEnabled)
                        .toggleStyle(.switch)
                }

                if preferences.speedCullingEnabled {
                    Toggle("Play short audio feedback", isOn: $preferences.autoAdvanceSoundEnabled)
                    Toggle("Perform trackpad haptic click", isOn: $preferences.autoAdvanceHapticEnabled)

                    HStack {
                        Text("Toggle Hotkey")
                        Spacer()
                        ShortcutRecorderView(hotkey: $preferences.autoAdvanceToggleHotkey)
                    }
                }
            } header: {
                Text("Speed Culling (Auto-Advance)")
            } footer: {
                Text("Automatically steps to the next photo immediately upon assigning a rating, flag, or tag.")
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }
}
