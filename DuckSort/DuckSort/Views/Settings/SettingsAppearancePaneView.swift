//
//  SettingsAppearancePaneView.swift
//  DuckSort
//
//  Settings pane for Liquid Glassmorphism, Theme Customization (Custom Accent,
//  Glass Translucency, High Contrast), and Customizable Trackpad Haptics.
//

import SwiftUI

struct SettingsAppearancePaneView: View {
    @ObservedObject var preferences = UserPreferences.shared

    var body: some View {
        Form {
            Section {
                Picker("App Icon Mode", selection: $preferences.appIconStyle) {
                    ForEach(AppIconStyle.allCases) { style in
                        Text(style.rawValue).tag(style)
                    }
                }
                .pickerStyle(.segmented)
            } header: {
                Text("App & Dock Icon")
            } footer: {
                Text("Automatically match macOS Light/Dark appearance or lock to a specific variant.")
                    .foregroundStyle(.secondary)
            }

            Section {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 140))], spacing: Theme.Space.s12) {
                    ForEach(CustomAccentColor.allCases) { accent in
                        Button {
                            preferences.customAccent = accent
                        } label: {
                            HStack(spacing: Theme.Space.s8) {
                                Circle()
                                    .fill(accent.color)
                                    .frame(width: 16, height: 16)
                                    .overlay(
                                        Circle()
                                            .stroke(Color.white.opacity(0.4), lineWidth: 1)
                                    )
                                Text(accent.rawValue)
                                    .font(Theme.Font.callout)
                                    .foregroundStyle(Theme.Color.textPrimary)
                            }
                            .padding(.horizontal, Theme.Space.s12)
                            .padding(.vertical, Theme.Space.s8)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(
                                RoundedRectangle(cornerRadius: Theme.Radius.l)
                                    .fill(preferences.customAccent == accent ? Theme.Color.surfaceRaised : Theme.Color.overlaySoft)
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: Theme.Radius.l)
                                    .stroke(preferences.customAccent == accent ? accent.color : Theme.Color.surfaceStroke, lineWidth: preferences.customAccent == accent ? 2 : 1)
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
            } header: {
                Text("Accent Highlight Color")
            }

            Section {
                Picker("Glass Mode", selection: $preferences.glassTranslucency) {
                    ForEach(GlassTranslucencyMode.allCases) { mode in
                        Text(mode.rawValue).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
            } header: {
                Text("Liquid Glass Translucency")
            } footer: {
                Text("Adjust background blur and translucency depth across control panels and viewer overlays.")
                    .foregroundStyle(.secondary)
            }

            Section {
                Toggle("High Contrast Mode", isOn: $preferences.highContrastEnabled)
                    .toggleStyle(.switch)
            } header: {
                Text("Accessibility")
            } footer: {
                Text("Boosts label contrast and outline borders for outdoor daylight culling.")
                    .foregroundStyle(.secondary)
            }

            Section {
                hapticRow(title: "Flagging Pick (Keep)", icon: "flag.fill", color: Theme.Color.danger, selection: $preferences.hapticProfileFlag)
                hapticRow(title: "Rejecting Photo", icon: "flag.slash.fill", color: Theme.Color.warning, selection: $preferences.hapticProfileReject)
                hapticRow(title: "Star Rating", icon: "star.fill", color: Theme.Color.rating, selection: $preferences.hapticProfileRating)
            } header: {
                Text("Trackpad Physical Haptics")
            }
        }
        .formStyle(.grouped)
    }

    private func hapticRow(title: String, icon: String, color: Color, selection: Binding<HapticProfile>) -> some View {
        HStack {
            HStack(spacing: Theme.Space.s8) {
                Image(systemName: icon)
                    .foregroundStyle(color)
                    .frame(width: 20)
                Text(title)
            }

            Spacer()

            Picker("", selection: selection) {
                ForEach(HapticProfile.allCases) { profile in
                    Text(profile.rawValue).tag(profile)
                }
            }
            .labelsHidden()
            .pickerStyle(.menu)
            .frame(width: 130)

            Button("Test") {
                HapticFeedbackManager.shared.performHaptic(selection.wrappedValue)
            }
            .buttonStyle(.bordered)
        }
    }
}
