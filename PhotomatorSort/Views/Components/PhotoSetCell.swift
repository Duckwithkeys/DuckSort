//
//  PhotoSetCell.swift
//  PhotomatorSort
//

import SwiftUI

struct PhotoSetCell: View {
    let photoSet: PhotoSet
    let tags: [CustomTag]
    let isFocusedGridItem: Bool
    let isJpegOnlyMode: Bool
    let toggleSelection: () -> Void
    let openBigView: () -> Void
    @State private var isHovered = false

    private var statusColor: Color {
        if photoSet.isSelected { return .green }
        if isJpegOnlyMode { return .blue }
        if !photoSet.hasEdit { return .red }
        return .orange
    }

    private var statusBackground: Color {
        statusColor.opacity(photoSet.isSelected ? 0.18 : 0.10)
    }

    var body: some View {
        Button(action: toggleSelection) {
            VStack(alignment: .leading, spacing: 8) {
                ZStack(alignment: .topTrailing) {
                    ThumbnailView(url: photoSet.preferredPreviewURL)
                        .frame(maxWidth: .infinity)
                        .aspectRatio(1, contentMode: .fit)
                        .clipShape(RoundedRectangle(cornerRadius: 6))

                    statusBadge

                    if isHovered {
                        Image(systemName: "info.circle.fill")
                            .font(.title3)
                            .foregroundStyle(.white)
                            .padding(6)
                            .background(.ultraThinMaterial, in: Circle())
                            .shadow(color: .black.opacity(0.2), radius: 2)
                            .highPriorityGesture(
                                TapGesture().onEnded {
                                    openBigView()
                                }
                            )
                            .transition(.opacity.combined(with: .scale))
                            .padding(8)
                            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                            .help("Open large image viewer")
                    }
                }

                HStack(spacing: 8) {
                    Image(systemName: photoSet.isSelected ? "checkmark.circle.fill" : "circle.fill")
                        .font(.system(size: 20, weight: .medium))
                        .foregroundStyle(statusColor)
                        .frame(width: 24, height: 24)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(photoSet.baseName)
                            .font(.callout.weight(.medium))
                            .lineLimit(1)

                        Text("\(photoSet.mediaCount) media\(photoSet.hasEdit ? " + edit" : "")")
                            .font(.caption)
                            .foregroundStyle(photoSet.hasEdit ? Color.secondary : Color.red)
                            .lineLimit(1)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }

                if !tags.isEmpty {
                    tagPills
                }
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .topLeading)
            .background(Color(nsColor: .controlBackgroundColor).opacity(0.5)) // Base layer
            .liquidGlassButton(isHovered: isHovered, isApplied: photoSet.isSelected, accentColor: statusColor)
            .overlay {
                if isFocusedGridItem {
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color.accentColor, lineWidth: 2.5)
                        .padding(-2)
                }
            }
            .onHover { isHovered in
                self.isHovered = isHovered
                if isHovered {
                    LargeImageLoader.preload(url: photoSet.preferredPreviewURL)
                }
            }
        }
        .buttonStyle(.plain)
        .contentShape(RoundedRectangle(cornerRadius: 8))
    }

    @ViewBuilder
    private var statusBadge: some View {
        if !isJpegOnlyMode {
            Label(
                photoSet.hasEdit ? "Edited" : "Needs edit",
                systemImage: photoSet.hasEdit ? "wand.and.stars" : "exclamationmark.triangle.fill"
            )
            .font(.caption.weight(.bold))
            .foregroundStyle(.white)
            .labelStyle(.iconOnly)
            .padding(7)
            .background(statusColor, in: Circle())
            .padding(7)
            .help(photoSet.hasEdit ? "Photomator edit detected" : "No Photomator edit sidecar found")
        }
    }

    private var tagPills: some View {
        HStack(spacing: 4) {
            ForEach(tags) { tag in
                HStack(spacing: 3) {
                    Circle()
                        .fill(tag.color)
                        .frame(width: 7, height: 7)
                    Text(tag.name)
                        .font(.caption2.weight(.medium))
                        .lineLimit(1)
                }
                .padding(.horizontal, 5)
                .padding(.vertical, 2)
                .background(tag.color.opacity(0.15), in: Capsule())
            }
        }
    }
}
