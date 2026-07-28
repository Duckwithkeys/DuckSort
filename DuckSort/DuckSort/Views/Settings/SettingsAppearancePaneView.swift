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
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Space.s24) {
                headerSection

                accentColorSection

                glassTranslucencySection

                highContrastSection

                hapticsSection

                Spacer()
            }
            .padding(Theme.Space.s24)
        }
        .background(Theme.Color.surfaceBase)
    }

    private var headerSection: some View {
        VStack(alignment: .leading, spacing: Theme.Space.s6) {
            HStack(spacing: Theme.Space.s8) {
                Image(systemName: "paintpalette.fill")
                    .font(.title2)
                    .foregroundStyle(Theme.Color.accent)
                Text("Appearance & Haptics")
                    .font(Theme.Font.title)
                    .foregroundStyle(Theme.Color.textPrimary)
            }
            Text("Customize theme highlights, liquid glass translucency, high-contrast culling, and trackpad haptics.")
                .font(Theme.Font.body)
                .foregroundStyle(Theme.Color.textSecondary)
        }
    }

    private var accentColorSection: some View {
        VStack(alignment: .leading, spacing: Theme.Space.s12) {
            Text("Accent Highlight Color")
                .font(Theme.Font.headline)
                .foregroundStyle(Theme.Color.textPrimary)

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
        }
        .padding(Theme.Space.s16)
        .background(Theme.Color.surfaceSidebar, in: RoundedRectangle(cornerRadius: Theme.Radius.xl))
    }

    private var glassTranslucencySection: some View {
        VStack(alignment: .leading, spacing: Theme.Space.s12) {
            Text("Liquid Glass Translucency")
                .font(Theme.Font.headline)
                .foregroundStyle(Theme.Color.textPrimary)

            Picker("Glass Mode", selection: $preferences.glassTranslucency) {
                ForEach(GlassTranslucencyMode.allCases) { mode in
                    Text(mode.rawValue).tag(mode)
                }
            }
            .pickerStyle(.segmented)

            Text("Adjust background blur and translucency depth across control panels and viewer overlays.")
                .font(Theme.Font.caption)
                .foregroundStyle(Theme.Color.textSecondary)
        }
        .padding(Theme.Space.s16)
        .background(Theme.Color.surfaceSidebar, in: RoundedRectangle(cornerRadius: Theme.Radius.xl))
    }

    private var highContrastSection: some View {
        VStack(alignment: .leading, spacing: Theme.Space.s12) {
            Toggle(isOn: $preferences.highContrastEnabled) {
                VStack(alignment: .leading, spacing: Theme.Space.s2) {
                    Text("High Contrast Mode")
                        .font(Theme.Font.headline)
                        .foregroundStyle(Theme.Color.textPrimary)
                    Text("Boosts label contrast and outline borders for outdoor daylight culling.")
                        .font(Theme.Font.caption)
                        .foregroundStyle(Theme.Color.textSecondary)
                }
            }
            .toggleStyle(.switch)
        }
        .padding(Theme.Space.s16)
        .background(Theme.Color.surfaceSidebar, in: RoundedRectangle(cornerRadius: Theme.Radius.xl))
    }

    private var hapticsSection: some View {
        VStack(alignment: .leading, spacing: Theme.Space.s16) {
            HStack {
                Image(systemName: "hand.tap.fill")
                    .font(.title3)
                    .foregroundStyle(Theme.Color.accent)
                Text("Trackpad Physical Haptics")
                    .font(Theme.Font.headline)
                    .foregroundStyle(Theme.Color.textPrimary)
            }

            VStack(spacing: Theme.Space.s12) {
                hapticRow(title: "Flagging Pick (Keep)", icon: "flag.fill", color: Theme.Color.danger, selection: $preferences.hapticProfileFlag)
                Divider().background(Theme.Color.surfaceDivider)
                hapticRow(title: "Rejecting Photo", icon: "flag.slash.fill", color: Theme.Color.warning, selection: $preferences.hapticProfileReject)
                Divider().background(Theme.Color.surfaceDivider)
                hapticRow(title: "Star Rating", icon: "star.fill", color: Theme.Color.rating, selection: $preferences.hapticProfileRating)
            }
        }
        .padding(Theme.Space.s16)
        .background(Theme.Color.surfaceSidebar, in: RoundedRectangle(cornerRadius: Theme.Radius.xl))
    }

    private func hapticRow(title: String, icon: String, color: Color, selection: Binding<HapticProfile>) -> some View {
        HStack {
            HStack(spacing: Theme.Space.s8) {
                Image(systemName: icon)
                    .foregroundStyle(color)
                Text(title)
                    .font(Theme.Font.callout)
                    .foregroundStyle(Theme.Color.textPrimary)
            }

            Spacer()

            Picker("", selection: selection) {
                ForEach(HapticProfile.allCases) { profile in
                    Text(profile.rawValue).tag(profile)
                }
            }
            .pickerStyle(.menu)
            .frame(width: 150)

            Button("Test") {
                HapticFeedbackManager.shared.performHaptic(selection.wrappedValue)
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
        }
    }
}
