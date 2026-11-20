//
//  PhotoGridView.swift
//  DuckSort
//
//  Grid of photo sets with selection, focus, shift-click range select,
//  and drag-to-select (marquee) when starting from empty space.
//

import SwiftUI
import AppKit

struct PhotoGridView: View {
    @ObservedObject var viewModel: PhotoLibraryViewModel

    @AppStorage("gridThumbnailWidth") private var itemWidth: Double = 180
    private static let gridSpacing: CGFloat = Theme.Space.s14
    private static let horizontalPadding: CGFloat = Theme.Space.s20
    private static let topPadding: CGFloat = Theme.Space.s16

    // Non-@State scroll offset holder so scrolling causes ZERO SwiftUI body re-evaluations.
    private final class ScrollOffsetBox {
        var y: CGFloat = 0
    }
    @State private var scrollOffsetBox = ScrollOffsetBox()
    @State private var marqueeStart: CGPoint? = nil
    @State private var marqueeCurrent: CGPoint? = nil
    @State private var gridContainerWidth: CGFloat = 800

    private var columns: [GridItem] {
        [GridItem(.adaptive(minimum: CGFloat(itemWidth)), spacing: Self.gridSpacing)]
    }

    private static func columnCount(forWidth width: CGFloat, itemWidth: CGFloat) -> Int {
        guard width.isFinite else { return 1 }
        let available = width - horizontalPadding * 2
        guard available > 0 && available.isFinite else { return 1 }
        let divisor = itemWidth + gridSpacing
        guard divisor > 0 else { return 1 }
        let val = (available + gridSpacing) / divisor
        guard val.isFinite else { return 1 }
        return max(1, Int(floor(val)))
    }

    /// Pure-math cell rect in the visible viewport coordinate space ("PhotoGrid"),
    /// eliminating per-cell GeometryReaders and PreferenceKey updates on every scroll frame.
    private func cellRect(at index: Int, cols: Int) -> CGRect {
        let available = max(1, gridContainerWidth - Self.horizontalPadding * 2)
        let cellW = (available - Self.gridSpacing * CGFloat(max(0, cols - 1))) / CGFloat(max(1, cols))
        // Cell height: 1:1 thumbnail + metadata bar (~38pt) + 8pt vertical padding.
        let cellH = cellW + 46
        let col = index % cols
        let row = index / cols
        let x = Self.horizontalPadding + CGFloat(col) * (cellW + Self.gridSpacing)
        let y = Self.topPadding + CGFloat(row) * (cellH + Self.gridSpacing) - scrollOffsetBox.y
        return CGRect(x: x, y: y, width: cellW, height: cellH)
    }

    private func isPointInAnyCell(_ point: CGPoint) -> Bool {
        let cols = Self.columnCount(forWidth: gridContainerWidth, itemWidth: CGFloat(itemWidth))
        let count = viewModel.filteredPhotoSets.count
        guard count > 0 else { return false }
        let available = max(1, gridContainerWidth - Self.horizontalPadding * 2)
        let cellW = (available - Self.gridSpacing * CGFloat(max(0, cols - 1))) / CGFloat(max(1, cols))
        let cellH = cellW + 46
        let contentY = point.y + scrollOffsetBox.y - Self.topPadding
        let contentX = point.x - Self.horizontalPadding
        guard contentY >= 0, contentX >= 0 else { return false }
        let row = Int(floor(contentY / (cellH + Self.gridSpacing)))
        let col = Int(floor(contentX / (cellW + Self.gridSpacing)))
        guard col >= 0, col < cols, row >= 0 else { return false }
        let idx = row * cols + col
        guard idx >= 0, idx < count else { return false }
        return cellRect(at: idx, cols: cols).contains(point)
    }

    private func photoIDsIntersecting(_ rect: CGRect) -> [PhotoSet.ID] {
        let sets = viewModel.filteredPhotoSets
        guard !sets.isEmpty else { return [] }
        let cols = Self.columnCount(forWidth: gridContainerWidth, itemWidth: CGFloat(itemWidth))
        let available = max(1, gridContainerWidth - Self.horizontalPadding * 2)
        let cellW = (available - Self.gridSpacing * CGFloat(max(0, cols - 1))) / CGFloat(max(1, cols))
        let cellH = cellW + 46
        let strideY = cellH + Self.gridSpacing

        let minRow = max(0, Int(floor((rect.minY + scrollOffsetBox.y - Self.topPadding) / strideY)))
        let maxRow = min((sets.count - 1) / cols, max(0, Int(floor((rect.maxY + scrollOffsetBox.y - Self.topPadding) / strideY))))
        guard minRow <= maxRow else { return [] }

        var hitIDs: [PhotoSet.ID] = []
        for row in minRow...maxRow {
            let startIdx = row * cols
            let endIdx = min(sets.count - 1, startIdx + cols - 1)
            for idx in startIdx...endIdx {
                if cellRect(at: idx, cols: cols).intersects(rect) {
                    hitIDs.append(sets[idx].id)
                }
            }
        }
        return hitIDs
    }

    var body: some View {
        ScrollViewReader { scrollProxy in
            ZStack(alignment: .topLeading) {
                // Layer 1: Empty-space hit area for marquee drag. Cells (above)
                // will absorb clicks first, so this gesture only ever fires
                // when the drag begins on a point not covered by any cell.
                Color.clear
                    .contentShape(Rectangle())
                    .gesture(
                        DragGesture(minimumDistance: 4, coordinateSpace: .named("PhotoGrid"))
                            .onChanged { value in
                                if marqueeStart == nil {
                                    if !isPointInAnyCell(value.startLocation) {
                                        marqueeStart = value.startLocation
                                    } else {
                                        return
                                    }
                                }
                                marqueeCurrent = value.location
                            }
                            .onEnded { value in
                                guard let start = marqueeStart else { return }
                                let end = marqueeCurrent ?? value.location
                                let rect = CGRect(
                                    x: min(start.x, end.x),
                                    y: min(start.y, end.y),
                                    width: abs(end.x - start.x),
                                    height: abs(end.y - start.y)
                                )
                                let hitIDs = photoIDsIntersecting(rect)
                                if !hitIDs.isEmpty {
                                    viewModel.replaceSelection(with: hitIDs)
                                    viewModel.selectionAnchorID = hitIDs.last
                                }
                                marqueeStart = nil
                                marqueeCurrent = nil
                            }
                    )

                // Layer 2: Edge-to-edge virtualized photo grid.
                ScrollView {
                    if viewModel.filteredPhotoSets.isEmpty && viewModel.isScanning {
                        LazyVGrid(columns: columns, spacing: Self.gridSpacing) {
                            ForEach(0..<12, id: \.self) { _ in
                                SkeletonThumbnailView()
                            }
                        }
                        .padding(.horizontal, Self.horizontalPadding)
                        .padding(.top, Self.topPadding)
                        .padding(.bottom, 52)
                    } else {
                        let sets = viewModel.filteredPhotoSets
                        let focusedID = (viewModel.focusedPhotoIndex >= 0 && viewModel.focusedPhotoIndex < sets.count)
                            ? sets[viewModel.focusedPhotoIndex].id
                            : nil
                        LazyVGrid(columns: columns, spacing: Self.gridSpacing) {
                            ForEach(sets) { photoSet in
                                cell(for: photoSet, isFocused: photoSet.id == focusedID)
                                    .id(photoSet.id)
                            }
                        }
                        .padding(.horizontal, Self.horizontalPadding)
                        .padding(.top, Self.topPadding)
                        .padding(.bottom, 52)
                    }
                }
                .onScrollGeometryChange(for: CGFloat.self) { geo in
                    geo.contentOffset.y
                } action: { _, newY in
                    scrollOffsetBox.y = newY
                }
                .coordinateSpace(name: "PhotoGrid")
                .background(GeometryReader { geometry in
                    Color.clear.onAppear {
                        gridContainerWidth = geometry.size.width
                        viewModel.gridColumnCount = Self.columnCount(forWidth: geometry.size.width, itemWidth: CGFloat(itemWidth))
                    }
                    .onChange(of: geometry.size.width) { _, newWidth in
                        gridContainerWidth = newWidth
                        viewModel.gridColumnCount = Self.columnCount(forWidth: newWidth, itemWidth: CGFloat(itemWidth))
                    }
                    .onChange(of: itemWidth) { _, newItemWidth in
                        viewModel.gridColumnCount = Self.columnCount(forWidth: gridContainerWidth, itemWidth: CGFloat(newItemWidth))
                    }
                })
                .onChange(of: viewModel.focusedPhotoIndex) { _, newIndex in
                    if newIndex >= 0 && newIndex < viewModel.filteredPhotoSets.count {
                        let targetID = viewModel.filteredPhotoSets[newIndex].id
                        scrollProxy.scrollTo(targetID)
                    }
                }

                // Layer 3: Marquee rectangle overlay (visual only).
                if let start = marqueeStart, let current = marqueeCurrent {
                    let rect = CGRect(
                        x: min(start.x, current.x),
                        y: min(start.y, current.y),
                        width: abs(current.x - start.x),
                        height: abs(current.y - start.y)
                    )
                    Rectangle()
                        .stroke(Theme.Color.accent, lineWidth: 1)
                        .background(Rectangle().fill(Theme.Color.accent.opacity(0.12)))
                        .frame(width: rect.width, height: rect.height)
                        .offset(x: rect.minX, y: rect.minY)
                        .allowsHitTesting(false)
                }
            }
        }
        .overlay(alignment: .top) {
            if viewModel.isScanning {
                ProgressView("Scanning subfolders...")
                    .padding(Theme.Space.s12)
                    .background(Theme.Color.cellBackground, in: RoundedRectangle(cornerRadius: Theme.Radius.l))
                    .padding(.top, Theme.Space.s12)
            }
        }
        .overlay(alignment: .bottomTrailing) {
            floatingStatusPill
                .padding(.trailing, Theme.Space.s16)
                .padding(.bottom, Theme.Space.s12)
        }
    }

    @ViewBuilder
    private var floatingStatusPill: some View {
        let hasExifProgress = viewModel.exifLoadProgress != nil
        let message = viewModel.statusMessage
        if hasExifProgress || !message.isEmpty {
            HStack(spacing: Theme.Space.s8) {
                if let progress = viewModel.exifLoadProgress, progress.total > 0 {
                    ProgressView()
                        .controlSize(.mini)
                    Text("EXIF \(progress.completed)/\(progress.total)")
                        .font(Theme.Font.caption)
                        .foregroundStyle(Theme.Color.textPrimary)
                        .monospacedDigit()
                    if !message.isEmpty {
                        Text("•")
                            .font(Theme.Font.caption)
                            .foregroundStyle(Theme.Color.textTertiary)
                    }
                }
                if !message.isEmpty {
                    Text(message)
                        .font(Theme.Font.caption)
                        .foregroundStyle(Theme.Color.textSecondary)
                        .lineLimit(1)
                }
            }
            .padding(.horizontal, Theme.Space.s12)
            .padding(.vertical, Theme.Space.s6)
            .background(.ultraThinMaterial, in: Capsule())
            .overlay(
                Capsule()
                    .strokeBorder(Theme.Color.surfaceDivider, lineWidth: Theme.Stroke.hairline)
            )
            .shadow(color: Theme.Color.overlayScrim, radius: 6, y: 2)
            .allowsHitTesting(false)
        }
    }

    @ViewBuilder
    private func cell(for photoSet: PhotoSet, isFocused: Bool) -> some View {
        EquatableView(content: PhotoSetCell(
            photoSet: photoSet,
            tags: viewModel.assignedTags(for: photoSet),
            isFocusedGridItem: isFocused,
            handleClick: { click in
                if let idx = viewModel.filteredPhotoSets.firstIndex(where: { $0.id == photoSet.id }) {
                    viewModel.focusedPhotoIndex = idx
                }
                switch click {
                case .plain:
                    viewModel.replaceSelection(with: [photoSet.id])
                    viewModel.selectionAnchorID = photoSet.id
                case .shiftClick:
                    viewModel.selectRange(to: photoSet.id, additive: false)
                case .commandClick:
                    viewModel.toggleSelection(for: photoSet.id)
                }
            },
            openInViewer: {
                if let idx = viewModel.filteredPhotoSets.firstIndex(where: { $0.id == photoSet.id }) {
                    viewModel.focusedPhotoIndex = idx
                }
                viewModel.openLargeImageViewer()
            }
        ))
    }
}