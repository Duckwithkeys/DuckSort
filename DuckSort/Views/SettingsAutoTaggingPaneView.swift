//
//  SettingsAutoTaggingPaneView.swift
//  DuckSort
//
//  Settings tab for configuring AI Vision Machine Learning auto-tagging.
//

import SwiftUI

struct SettingsAutoTaggingPaneView: View {
    @ObservedObject var preferences: UserPreferences
    @ObservedObject var tagStore: TagStore

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.s16) {
            // Header
            HStack {
                VStack(alignment: .leading, spacing: Theme.Space.s4) {
                    Text("AI Vision Auto Tagging")
                        .font(Theme.Font.title)
                        .foregroundStyle(Theme.Color.textPrimary)

                    Text("On-device machine learning automatically analyzes scenes, objects, and subjects.")
                        .font(Theme.Font.body)
                        .foregroundStyle(Theme.Color.textSecondary)
                }

                Spacer()

                Toggle("", isOn: $preferences.autoTaggingEnabled)
                    .toggleStyle(.switch)
                    .labelsHidden()
                    .controlSize(.small)
            }
            .padding(.bottom, Theme.Space.s4)

            Divider()
                .background(Theme.Color.separator)

            // AI Vision Engine Info Card
            VStack(alignment: .leading, spacing: Theme.Space.s12) {
                HStack(spacing: Theme.Space.s12) {
                    Image(systemName: "brain.head.profile")
                        .font(.system(size: 24, weight: .semibold))
                        .foregroundStyle(Theme.Color.accent)

                    VStack(alignment: .leading, spacing: 2) {
                        Text("Apple Vision Framework & Neural Engine")
                            .font(Theme.Font.headline)
                            .foregroundStyle(Theme.Color.textPrimary)

                        Text("All photo classification runs 100% locally on your Mac without external cloud APIs.")
                            .font(Theme.Font.caption)
                            .foregroundStyle(Theme.Color.textSecondary)
                    }
                }

                HStack(spacing: Theme.Space.s8) {
                    Label("Scene Detection", systemImage: "checkmark.circle.fill")
                        .font(Theme.Font.caption)
                        .foregroundStyle(Theme.Color.success)

                    Label("Face & Body Clustering", systemImage: "checkmark.circle.fill")
                        .font(Theme.Font.caption)
                        .foregroundStyle(Theme.Color.success)

                    Label("Zero Cloud Uploads", systemImage: "checkmark.circle.fill")
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

            Spacer()
        }
        .padding(Theme.Space.s20)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(Theme.Color.surfaceBase)
    }
}
