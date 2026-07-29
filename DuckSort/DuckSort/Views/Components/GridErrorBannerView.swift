//
//  GridErrorBannerView.swift
//  DuckSort
//
//  Top-anchored dismissable error banner for grid-level and non-fatal failures,
//  such as scan errors or unreadable files. Replaces blocking modal Alerts.
//

import SwiftUI

struct GridErrorBannerView: View {
    let message: String
    let onDismiss: () -> Void

    var body: some View {
        let formatted = ErrorFormatter.format(message)
        HStack(spacing: Theme.Space.s12) {
            Image(systemName: "exclamationmark.octagon.fill")
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(Theme.Color.danger)

            VStack(alignment: .leading, spacing: 2) {
                Text(formatted.cleanMessage)
                    .font(Theme.Font.bodyBold)
                    .foregroundStyle(Theme.Color.textPrimary)
                    .lineLimit(1)

                Text(formatted.suggestion)
                    .font(Theme.Font.caption)
                    .foregroundStyle(Theme.Color.textSecondary)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
            }

            Spacer()

            Button(action: onDismiss) {
                Image(systemName: "xmark")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(Theme.Color.textSecondary)
                    .padding(Theme.Space.s6)
                    .background(Circle().fill(Theme.Color.separator.opacity(0.3)))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, Theme.Space.s16)
        .padding(.vertical, Theme.Space.s12)
        .background(
            RoundedRectangle(cornerRadius: Theme.Radius.l)
                .fill(Theme.Color.cellBackground)
                .shadow(color: .black.opacity(0.15), radius: 6, x: 0, y: 3)
        )

        .overlay(
            RoundedRectangle(cornerRadius: Theme.Radius.l)
                .stroke(Theme.Color.danger.opacity(0.3), lineWidth: Theme.Stroke.hairline)
        )
        .transition(.move(edge: .top).combined(with: .opacity))
        .padding(.top, Theme.Space.s12)
        .padding(.horizontal, Theme.Space.s20)
    }
}
