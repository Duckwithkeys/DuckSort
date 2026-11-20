//
//  SettingsAutoTaggingPaneView.swift
//  DuckSort
//
//  Native macOS grouped Form for On-Device AI Vision Auto-Tagging and Speed Culling.
//

import SwiftUI

struct SettingsAutoTaggingPaneView: View {
    @ObservedObject var preferences: UserPreferences
    @ObservedObject var tagStore: TagStore

    var body: some View {
        Form {
            Section {
                Toggle("Enable AI Vision Auto-Tagging", isOn: $preferences.autoTaggingEnabled)

                LabeledContent("Trigger Shortcut") {
                    ShortcutRecorderView(hotkey: $preferences.aiVisionHotkey)
                }
                .disabled(!preferences.autoTaggingEnabled)

                LabeledContent("Processing") {
                    Label("On-Device Apple Vision", systemImage: "checkmark.shield.fill")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            } header: {
                Text("AI Vision Auto-Tagging")
            } footer: {
                Text("Analyzes photos locally using Apple Vision to suggest scene, object, and subject tags without sending data off your Mac.")
            }

            Section {
                Toggle("Enable Speed Culling (Auto-Advance)", isOn: $preferences.speedCullingEnabled)

                LabeledContent("Toggle Shortcut") {
                    ShortcutRecorderView(hotkey: $preferences.autoAdvanceToggleHotkey)
                }

                Toggle("Play Audio Feedback on Advance", isOn: $preferences.autoAdvanceSoundEnabled)
                    .disabled(!preferences.speedCullingEnabled)

                Toggle("Trackpad Haptic Click on Advance", isOn: $preferences.autoAdvanceHapticEnabled)
                    .disabled(!preferences.speedCullingEnabled)
            } header: {
                Text("Speed Culling")
            } footer: {
                Text("Automatically steps to the next photo immediately after assigning a star rating, pick flag, or tag.")
            }
        }
        .formStyle(.grouped)
    }
}
