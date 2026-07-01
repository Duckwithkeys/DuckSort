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
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Space.s16) {
                // Header
                VStack(alignment: .leading, spacing: Theme.Space.s4) {
                    Text("Mode Switching & AI Configuration")
                        .font(Theme.Font.title)
                        .foregroundStyle(Theme.Color.textPrimary)

                    Text("Configure on-device artificial intelligence modes and keyboard shortcut toggles.")
                        .font(Theme.Font.body)
                        .foregroundStyle(Theme.Color.textSecondary)
                }
                .padding(.bottom, Theme.Space.s4)

                Divider()
                    .background(Theme.Color.separator)

                // Mode 1: AI Vision Auto-Tagging Card
                VStack(alignment: .leading, spacing: Theme.Space.s12) {
                    HStack {
                        HStack(spacing: Theme.Space.s12) {
                            Image(systemName: "brain.head.profile")
                                .font(.system(size: 22, weight: .semibold))
                                .foregroundStyle(Theme.Color.accent)

                            VStack(alignment: .leading, spacing: 2) {
                                Text("AI Vision Auto-Tagging")
                                    .font(Theme.Font.headline)
                                    .foregroundStyle(Theme.Color.textPrimary)

                                Text("Automatically classifies scenes, landscapes, objects, and subjects.")
                                    .font(Theme.Font.caption)
                                    .foregroundStyle(Theme.Color.textSecondary)
                            }
                        }

                        Spacer()

                        Toggle("", isOn: $preferences.autoTaggingEnabled)
                            .toggleStyle(.switch)
                            .labelsHidden()
                            .controlSize(.small)
                    }

                    HStack(spacing: Theme.Space.s12) {
                        Text("Shortcut Hotkey:")
                            .font(Theme.Font.caption)
                            .foregroundStyle(Theme.Color.textTertiary)

                        ShortcutRecorderView(hotkey: $preferences.aiVisionHotkey)

                        Spacer()

                        Label("100% On-Device", systemImage: "checkmark.shield.fill")
                            .font(Theme.Font.caption)
                            .foregroundStyle(Theme.Color.success)
                    }
                    .padding(.top, Theme.Space.s4)
                }
                .padding(Theme.Space.s16)
                .background(.thinMaterial)
                .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.l))
                .overlay(
                    RoundedRectangle(cornerRadius: Theme.Radius.l)
                        .strokeBorder(Theme.Color.separator.opacity(0.4), lineWidth: 1)
                )

                // Mode 2: Speed Culling (Auto-Advance) Card
                VStack(alignment: .leading, spacing: Theme.Space.s12) {
                    HStack {
                        HStack(spacing: Theme.Space.s12) {
                            Image(systemName: "bolt.fill")
                                .font(.system(size: 22, weight: .semibold))
                                .foregroundStyle(Theme.Color.accent)

                            VStack(alignment: .leading, spacing: 2) {
                                Text("Speed Culling (Auto-Advance)")
                                    .font(Theme.Font.headline)
                                    .foregroundStyle(Theme.Color.textPrimary)

                                Text("Automatically advance to the next image after rating, picking, or tagging.")
                                    .font(Theme.Font.caption)
                                    .foregroundStyle(Theme.Color.textSecondary)
                            }
                        }

                        Spacer()

                        Toggle("", isOn: $preferences.speedCullingEnabled)
                            .toggleStyle(.switch)
                            .labelsHidden()
                            .controlSize(.small)
                    }

                    if preferences.speedCullingEnabled {
                        Divider()
                            .background(Theme.Color.separator)
                            .padding(.vertical, Theme.Space.s4)

                        VStack(alignment: .leading, spacing: Theme.Space.s8) {
                            Text("FEEDBACK CHANNELS")
                                .font(Theme.Font.caption2)
                                .foregroundStyle(Theme.Color.textTertiary)

                            Toggle("Play short system sound effects", isOn: $preferences.autoAdvanceSoundEnabled)
                                .font(Theme.Font.body)
                            
                            Toggle("Perform haptic click on supported trackpads", isOn: $preferences.autoAdvanceHapticEnabled)
                                .font(Theme.Font.body)
                        }
                    }

                    HStack(spacing: Theme.Space.s12) {
                        Text("Toggle Shortcut:")
                            .font(Theme.Font.caption)
                            .foregroundStyle(Theme.Color.textTertiary)

                        ShortcutRecorderView(hotkey: $preferences.autoAdvanceToggleHotkey)

                        Spacer()
                    }
                    .padding(.top, Theme.Space.s4)
                }
                .padding(Theme.Space.s16)
                .background(.thinMaterial)
                .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.l))
                .overlay(
                    RoundedRectangle(cornerRadius: Theme.Radius.l)
                        .strokeBorder(Theme.Color.separator.opacity(0.4), lineWidth: 1)
                )
            }
            .padding(Theme.Space.s20)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(Theme.Color.surfaceBase)
    }
}
