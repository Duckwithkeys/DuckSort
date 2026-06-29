//
//  LiquidGlassStyle.swift
//  DuckSort
//
//  View modifiers for sidebar/panel/button styling using native Apple HIG
//  materials, specular highlights, and spatial depth shadows.
//

import SwiftUI
import AppKit

extension View {
    /// Applies native visual effect material to the DuckSort sidebar.
    func liquidGlassSidebar(cornerRadius: CGFloat = 0) -> some View {
        self
            .background(.regularMaterial)
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
    }

    /// Applies a premium Liquid Glass floating panel style with specular highlights and spatial shadows.
    func liquidGlassPanel(cornerRadius: CGFloat = Theme.Radius.l, opacity: Double = 0.08) -> some View {
        self
            .background(.thinMaterial)
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius)
                    .strokeBorder(
                        LinearGradient(
                            colors: [
                                Color.white.opacity(0.35),
                                Color.white.opacity(0.10),
                                Color.black.opacity(0.15)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 1
                    )
            )
            .shadow(color: Color.black.opacity(0.15), radius: 10, x: 0, y: 4)
    }

    /// Premium Liquid Glass button with specular bevel and dynamic hover effects.
    func liquidGlassButton(
        isHovered: Bool = false,
        isApplied: Bool = false,
        accentColor: Color = Theme.Color.accent
    ) -> some View {
        self
            .background(
                ZStack {
                    if isApplied {
                        accentColor.opacity(0.25)
                    } else {
                        Rectangle().fill(.ultraThinMaterial)
                        if isHovered {
                            Color.primary.opacity(0.08)
                        }
                    }
                }
            )
            .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.m))
            .overlay(
                RoundedRectangle(cornerRadius: Theme.Radius.m)
                    .strokeBorder(
                        isApplied ? LinearGradient(colors: [accentColor.opacity(0.8), accentColor.opacity(0.4)], startPoint: .top, endPoint: .bottom)
                                  : LinearGradient(colors: [Color.white.opacity(isHovered ? 0.4 : 0.2), Color.white.opacity(0.05)], startPoint: .topLeading, endPoint: .bottomTrailing),
                        lineWidth: 1
                    )
            )
            .shadow(color: isHovered ? Color.black.opacity(0.1) : Color.clear, radius: 4, x: 0, y: 2)
    }

    /// Sidebar item button conforming to native material selection states.
    func flatSidebarButton(
        isHovered: Bool = false,
        isSelected: Bool = false,
        accentColor: Color = Theme.Color.accent
    ) -> some View {
        self
            .background(
                RoundedRectangle(cornerRadius: Theme.Radius.m)
                    .fill(
                        isSelected ? accentColor.opacity(0.22)
                                   : (isHovered ? Color.primary.opacity(0.08) : Color.clear)
                    )
            )
            .contentShape(RoundedRectangle(cornerRadius: Theme.Radius.m))
    }
}

