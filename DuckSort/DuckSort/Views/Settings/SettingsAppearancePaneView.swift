//
//  SettingsAppearancePaneView.swift
//  DuckSort
//
//  Native macOS System Settings–style Appearance & Haptics pane.
//

import SwiftUI

struct SettingsAppearancePaneView: View {
    @ObservedObject var preferences = UserPreferences.shared

    var body: some View {
        Form {
            Section {
                LabeledContent("App & Dock Icon") {
                    Picker("App & Dock Icon", selection: $preferences.appIconStyle) {
                        Text("Auto").tag(AppIconStyle.system)
                        Text("Light").tag(AppIconStyle.light)
                        Text("Dark").tag(AppIconStyle.dark)
                    }
                    .labelsHidden()
                    .pickerStyle(.segmented)
                    .frame(width: 210)
                }

                LabeledContent("Accent Color") {
                    HStack(spacing: 12) {
                        Text(preferences.customAccent.rawValue)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)

                        HStack(spacing: 8) {
                            ForEach(CustomAccentColor.allCases) { accent in
                                AccentSwatchButton(
                                    accent: accent,
                                    isSelected: preferences.customAccent == accent
                                ) {
                                    preferences.customAccent = accent
                                }
                            }
                        }
                    }
                }
            } header: {
                Text("Appearance")
            } footer: {
                Text("Choose how the DuckSort Dock icon adapts to macOS appearance and customize the highlight accent used across selections and badges.")
            }

            Section {
                Picker("Material Style", selection: $preferences.glassTranslucency) {
                    ForEach(GlassTranslucencyMode.allCases) { mode in
                        Text(mode.rawValue).tag(mode)
                    }
                }
                .pickerStyle(.menu)

                Toggle("Increase Contrast", isOn: $preferences.highContrastEnabled)
            } header: {
                Text("Windows & Surfaces")
            } footer: {
                Text("Adjust background blur and surface contrast across toolbars, sidebars, and viewer overlays.")
            }

            Section {
                hapticRow(
                    title: "Flagging Pick (Keep)",
                    selection: $preferences.hapticProfileFlag
                )
                hapticRow(
                    title: "Rejecting Photo",
                    selection: $preferences.hapticProfileReject
                )
                hapticRow(
                    title: "Assigning Star Rating",
                    selection: $preferences.hapticProfileRating
                )
            } header: {
                Text("Trackpad Haptics")
            } footer: {
                Text("Customize Force Touch trackpad tactile feedback when culling photos.")
            }
        }
        .formStyle(.grouped)
    }

    private func hapticRow(title: String, selection: Binding<HapticProfile>) -> some View {
        LabeledContent(title) {
            HStack(spacing: 8) {
                Picker("", selection: selection) {
                    ForEach(HapticProfile.allCases) { profile in
                        Text(profile.rawValue).tag(profile)
                    }
                }
                .labelsHidden()
                .pickerStyle(.menu)
                .frame(width: 135)

                Button("Test") {
                    HapticFeedbackManager.shared.performHaptic(selection.wrappedValue)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
        }
    }
}

private struct AccentSwatchButton: View {
    let accent: CustomAccentColor
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            ZStack {
                if accent == .system {
                    Circle()
                        .fill(
                            AngularGradient(
                                colors: [.blue, .purple, .pink, .orange, .yellow, .green, .blue],
                                center: .center
                            )
                        )
                        .frame(width: 18, height: 18)
                } else {
                    Circle()
                        .fill(accent.color)
                        .frame(width: 18, height: 18)
                }

                Circle()
                    .strokeBorder(Color.primary.opacity(0.18), lineWidth: 1)
                    .frame(width: 18, height: 18)

                if isSelected {
                    Circle()
                        .fill(Color.white)
                        .frame(width: 6, height: 6)
                        .shadow(color: .black.opacity(0.35), radius: 1, x: 0, y: 0.5)
                }
            }
            .frame(width: 22, height: 22)
            .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .help(accent.rawValue)
    }
}
