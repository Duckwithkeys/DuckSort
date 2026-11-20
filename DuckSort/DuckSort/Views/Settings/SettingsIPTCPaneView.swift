//
//  SettingsIPTCPaneView.swift
//  DuckSort
//
//  Native macOS grouped Form for Photographer, Rights, and Contact IPTC metadata.
//

import SwiftUI

struct SettingsIPTCPaneView: View {
    @ObservedObject var preferences: UserPreferences

    var body: some View {
        Form {
            Section {
                Toggle("Embed Copyright Metadata in Exports", isOn: $preferences.embedIPTCInExports)
            } footer: {
                Text("When enabled, photographer, copyright, and contact metadata are automatically written into XMP sidecar files during export.")
            }

            Section("Photographer") {
                TextField(
                    "Creator Name",
                    text: $preferences.iptcCreatorName,
                    prompt: Text("e.g. Jane Doe")
                )
            }
            .disabled(!preferences.embedIPTCInExports)

            Section("Rights") {
                TextField(
                    "Copyright Notice",
                    text: $preferences.iptcCopyrightNotice,
                    prompt: Text("e.g. © 2026 Jane Doe. All rights reserved.")
                )
                TextField(
                    "Usage Terms",
                    text: $preferences.iptcRightsUsageTerms,
                    prompt: Text("e.g. Licensed for editorial use only.")
                )
            }
            .disabled(!preferences.embedIPTCInExports)

            Section("Contact Information") {
                TextField(
                    "Email",
                    text: $preferences.iptcContactEmail,
                    prompt: Text("jane@example.com")
                )
                .textContentType(.emailAddress)

                TextField(
                    "Phone",
                    text: $preferences.iptcContactPhone,
                    prompt: Text("+1 555 123 4567")
                )
                .textContentType(.telephoneNumber)

                TextField(
                    "Website",
                    text: $preferences.iptcContactWebsite,
                    prompt: Text("https://janedoe.example")
                )
                .textContentType(.URL)
            }
            .disabled(!preferences.embedIPTCInExports)
        }
        .formStyle(.grouped)
        .onChange(of: preferences.embedIPTCInExports) { _, _ in preferences.save() }
        .onChange(of: preferences.iptcCreatorName) { _, _ in preferences.save() }
        .onChange(of: preferences.iptcCopyrightNotice) { _, _ in preferences.save() }
        .onChange(of: preferences.iptcContactEmail) { _, _ in preferences.save() }
        .onChange(of: preferences.iptcContactPhone) { _, _ in preferences.save() }
        .onChange(of: preferences.iptcContactWebsite) { _, _ in preferences.save() }
        .onChange(of: preferences.iptcRightsUsageTerms) { _, _ in preferences.save() }
    }
}