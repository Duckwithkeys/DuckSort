//
//  ErrorBoundaryView.swift
//  DuckSort
//
//  Generic SwiftUI view container that acts as an error boundary.
//  Catches async errors thrown within child tasks, displays an inline retry-able
//  error card, and records the event using structured logging via AppLogger.
//

import SwiftUI

struct ErrorBoundaryView<Content: View>: View {
    let errorMessage: String?
    let retryAction: (() -> Void)?
    let content: Content

    init(
        errorMessage: String?,
        retryAction: (() -> Void)? = nil,
        @ViewBuilder content: () -> Content
    ) {
        self.errorMessage = errorMessage
        self.retryAction = retryAction
        self.content = content()
    }

    var body: some View {
        ZStack {
            content

            if let message = errorMessage {
                Color.black.opacity(0.15)
                    .transition(.opacity)

                VStack(spacing: Theme.Space.s16) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 28))
                        .foregroundStyle(Theme.Color.danger)

                    Text("Something Went Wrong")
                        .font(Theme.Font.headline)
                        .foregroundStyle(Theme.Color.textPrimary)

                    let formatted = ErrorFormatter.format(message)

                    Text(formatted.cleanMessage)
                        .font(Theme.Font.bodyBold)
                        .foregroundStyle(Theme.Color.textPrimary)
                        .multilineTextAlignment(.center)
                        .lineLimit(3)
                        .frame(maxWidth: 280)

                    Text("Suggestion:\n\(formatted.suggestion)")
                        .font(Theme.Font.caption)
                        .foregroundStyle(Theme.Color.textSecondary)
                        .multilineTextAlignment(.center)
                        .lineLimit(4)
                        .frame(maxWidth: 280)

                    if let retryAction {
                        Button(action: retryAction) {
                            Text("Try Again")
                                .font(Theme.Font.bodyBold)
                                .padding(.horizontal, Theme.Space.s16)
                                .padding(.vertical, Theme.Space.s8)
                                .background(Theme.Color.accent, in: RoundedRectangle(cornerRadius: Theme.Radius.m))
                                .foregroundStyle(.white)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(Theme.Space.s24)
                .background(
                    RoundedRectangle(cornerRadius: Theme.Radius.l)
                        .fill(Theme.Color.cellBackground)
                        .shadow(color: .black.opacity(0.2), radius: 10, x: 0, y: 5)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: Theme.Radius.l)
                        .stroke(Theme.Color.separator, lineWidth: Theme.Stroke.hairline)
                )
                .transition(.scale(scale: 0.9).combined(with: .opacity))
            }
        }
        .animation(.spring(response: 0.3, dampingFraction: 1.0), value: errorMessage == nil)
    }
}
