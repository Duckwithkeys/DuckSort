//
//  LiquidGlassStyle.swift
//  PhotomatorSort
//
//  Design system modifiers inspired by Photomator's dark professional aesthetic.
//  Provides flat dark panels, subtle hover highlights, and consistent styling.
//

import SwiftUI

// MARK: - Photomator Color Constants

enum PhotomatorTheme {
    static let background = Color(red: 0.176, green: 0.176, blue: 0.176)        // #2D2D2D
    static let sidebarBackground = Color(red: 0.145, green: 0.145, blue: 0.145) // #252525
    static let toolbarBackground = Color(red: 0.200, green: 0.200, blue: 0.200) // #333333
    static let cellBackground = Color(red: 0.160, green: 0.160, blue: 0.160)    // #292929
    static let separator = Color(red: 0.227, green: 0.227, blue: 0.227)         // #3A3A3A
    static let selectedBlue = Color(red: 0.251, green: 0.537, blue: 1.0)        // #4089FF
    static let textPrimary = Color.white.opacity(0.88)
    static let textSecondary = Color.white.opacity(0.50)
    static let textTertiary = Color.white.opacity(0.30)
}

extension View {
    /// Applies the Photomator-style dark sidebar background.
    func liquidGlassSidebar(cornerRadius: CGFloat = 0) -> some View {
        self
            .background(PhotomatorTheme.sidebarBackground)
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
    }

    /// Applies a flat dark panel style with subtle border.
    func liquidGlassPanel(cornerRadius: CGFloat = 8, opacity: Double = 0.08) -> some View {
        self
            .background(PhotomatorTheme.cellBackground)
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius)
                    .stroke(PhotomatorTheme.separator, lineWidth: 1)
            )
    }

    /// Applies a flat dark button style with subtle hover and selection states.
    func liquidGlassButton(isHovered: Bool = false, isApplied: Bool = false, accentColor: Color = PhotomatorTheme.selectedBlue) -> some View {
        self
            .background(
                ZStack {
                    if isApplied {
                        accentColor.opacity(0.20)
                    } else if isHovered {
                        Color.white.opacity(0.08)
                    } else {
                        Color.white.opacity(0.04)
                    }
                }
            )
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(
                        isApplied ? accentColor.opacity(0.5) : Color.white.opacity(isHovered ? 0.15 : 0.08),
                        lineWidth: 1
                    )
            )
    }
}
