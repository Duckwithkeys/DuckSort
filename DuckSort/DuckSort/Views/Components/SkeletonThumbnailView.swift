//
//  SkeletonThumbnailView.swift
//  DuckSort
//
//  Animated shimmer placeholder shown in the grid during directory scanning
//  or thumbnail decode operations. Matches the aspect ratio and corner radius
//  of the standard photo cells to prevent layout shifts.
//

import SwiftUI

struct SkeletonThumbnailView: View {
    var cornerRadius: CGFloat = Theme.Radius.xl
    @State private var phase: CGFloat = 0.0

    var body: some View {
        Color.clear
            .aspectRatio(1.0, contentMode: .fit) // Standard 1:1 aspect ratio
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius)
                    .fill(Theme.Color.cellBackground)
                    .overlay(
                        GeometryReader { geo in
                            let width = geo.size.width
                            let height = geo.size.height
                            
                            Rectangle()
                                .fill(
                                    LinearGradient(
                                        stops: [
                                            .init(color: .clear, location: 0),
                                            .init(color: Theme.Color.separator.opacity(0.4), location: 0.5),
                                            .init(color: .clear, location: 1)
                                        ],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    )
                                )
                                // Scale and offset the shimmer gradient to animate across the cell
                                .frame(width: width * 1.5, height: height)
                                .offset(x: -width * 0.75 + (width * 1.5 * phase))
                        }
                    )
                    .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
            }
            .onAppear {
                withAnimation(.linear(duration: 1.5).repeatForever(autoreverses: false)) {
                    phase = 1.0
                }
            }
    }
}
