//
//  EmptyLibraryView.swift
//  DuckSort
//

import SwiftUI

struct EmptyLibraryView: View {
    let isScanning: Bool
    let selectFolderAction: () -> Void

    var body: some View {
        VStack(spacing: 20) {
            if isScanning {
                ProgressView()
                    .controlSize(.large)
                Text("Scanning photoshoot…")
                    .font(.title3.weight(.medium))
                    .foregroundStyle(.secondary)
            } else {
                Image(systemName: "photo.on.rectangle.angled")
                    .font(.system(size: 44, weight: .regular))
                    .foregroundStyle(.secondary)

                VStack(spacing: 6) {
                    Text("No Photos Loaded")
                        .font(.title2.weight(.semibold))
                        .foregroundStyle(.primary)

                    Text("Drag files or folders into the window, or import a folder from your Mac.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                HStack(spacing: 16) {
                    EmptyActionCard(
                        systemImage: "square.and.arrow.down.on.square",
                        title: "Drag & Drop",
                        subtitle: "Drop folders or photos directly into DuckSort."
                    )
                    EmptyActionCard(
                        systemImage: "folder.badge.plus",
                        title: "Import Folder",
                        subtitle: "Choose Import from the File menu or click below."
                    )
                }
                .padding(.vertical, 8)

                Button("Import…") {
                    selectFolderAction()
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .tint(Theme.Color.accent)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(nsColor: .windowBackgroundColor))
        .contentShape(Rectangle())
    }
}

private struct EmptyActionCard: View {
    let systemImage: String
    let title: String
    let subtitle: String

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: systemImage)
                .font(.system(size: 24, weight: .regular))
                .foregroundStyle(Theme.Color.accent)
            Text(title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.primary)
            Text(subtitle)
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 16)
        .frame(width: 200, height: 132)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color(nsColor: .controlBackgroundColor))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(Color(nsColor: .separatorColor), lineWidth: 1)
        )
    }
}
