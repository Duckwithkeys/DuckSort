//
//  EmptyLibraryView.swift
//  DuckSort
//

import SwiftUI

struct EmptyLibraryView: View {
    let isScanning: Bool
    let selectFolderAction: () -> Void

    var body: some View {
        VStack(spacing: Theme.Space.s24) {
            if isScanning {
                ProgressView()
                    .controlSize(.large)
                Text("Scanning photoshoot…")
                    .font(Theme.Font.title)
                    .foregroundStyle(Theme.Color.textPrimary)
            } else {
                Text("Welcome to DuckSort")
                    .font(Theme.Font.display)
                    .foregroundStyle(Theme.Color.textPrimary)

                Text("To get started with DuckSort, do any of the following:")
                    .font(Theme.Font.subheadline)
                    .foregroundStyle(Theme.Color.textSecondary)

                HStack(spacing: Theme.Space.s20) {
                    EmptyActionCard(
                        systemImage: "square.and.arrow.down.on.square",
                        title: "Drag files or folders directly\ninto DuckSort."
                    )
                    EmptyActionCard(
                        systemImage: "folder.badge.gearshape",
                        title: "Choose Import from the File\nmenu."
                    )
                }
                .padding(.vertical, Theme.Space.s20)

                Button("Import…") {
                    selectFolderAction()
                }
                .buttonStyle(.responsive)
                .controlSize(.large)
                .padding(.horizontal, Theme.Space.s24)
                .padding(.vertical, Theme.Space.s12)
                .background(Theme.Color.accent, in: RoundedRectangle(cornerRadius: Theme.Radius.l))
                .foregroundStyle(Theme.Color.textInverse)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.Color.background)
        .contentShape(Rectangle())
    }
}

private struct EmptyActionCard: View {
    let systemImage: String
    let title: String
    @State private var isHovered = false

    var body: some View {
        VStack(spacing: Theme.Space.s12) {
            Image(systemName: systemImage)
                .font(Theme.Font.iconHero)
                .foregroundStyle(isHovered ? Theme.Color.accent : Theme.Color.textSecondary)
                .animation(Theme.Motion.snappy, value: isHovered)
            Text(title)
                .font(Theme.Font.caption)
                .foregroundStyle(Theme.Color.textSecondary)
                .multilineTextAlignment(.center)
        }
        .frame(width: 200, height: 160)
        .background(Theme.Color.cellBackground, in: RoundedRectangle(cornerRadius: Theme.Radius.xl))
        .overlay(
            RoundedRectangle(cornerRadius: Theme.Radius.xl)
                .stroke(isHovered ? Theme.Color.accent.opacity(0.3) : Theme.Color.separator.opacity(0.4), lineWidth: 1)
        )
        .scaleEffect(isHovered ? 1.02 : 1.0)
        .shadow(color: isHovered ? Theme.Color.overlayScrim : .clear, radius: isHovered ? 8 : 0)
        .animation(Theme.Motion.snappy, value: isHovered)
        .onHover { isHovered = $0 }
    }
}
