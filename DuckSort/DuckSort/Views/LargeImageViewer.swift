//
//  LargeImageViewer.swift
//  DuckSort
//
//  Large image viewer overlay containing filmstrip navigation and right sidebar.
//  Extends full-height with clean border layout.
//

import SwiftUI
import AppKit

struct LargeImageViewer: View {
    @ObservedObject var viewModel: PhotoLibraryViewModel

    var body: some View {
        HStack(spacing: 0) {
            VStack(spacing: 0) {
                // Keep the macOS titlebar band completely clean so the traffic lights
                // and native liquid glass sidebar button never overlap viewer controls.
                Theme.Color.sidebarBackground
                    .frame(height: 52)
                    .overlay(
                        Rectangle()
                            .fill(Theme.Color.separator)
                            .frame(height: 1),
                        alignment: .bottom
                    )

                imagePane
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .padding(.horizontal, Theme.Space.s12)
                    .padding(.bottom, Theme.Space.s12)
                    .padding(.top, Theme.Space.s12)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        NSApp.keyWindow?.makeFirstResponder(nil)
                    }
                    .overlay(alignment: .top) {
                        floatingViewerControls
                            .padding(.horizontal, Theme.Space.s20)
                            .padding(.top, Theme.Space.s16)
                    }
                    .overlay(alignment: .bottom) {
                        if let toast = viewModel.cullingToast {
                            HStack(spacing: Theme.Space.s6) {
                                Image(systemName: toast.icon)
                                    .font(.system(size: 12, weight: .bold))
                                    .foregroundStyle(
                                        toast.isWarning ? Theme.Color.warning
                                            : (toast.isPositive ? Theme.Color.success : Theme.Color.textPrimary)
                                    )
                                Text(toast.text)
                                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                                    .foregroundStyle(Theme.Color.textPrimary)
                            }
                            .padding(.horizontal, Theme.Space.s14)
                            .padding(.vertical, Theme.Space.s8)
                            .background(.ultraThinMaterial, in: Capsule())
                            .overlay(
                                Capsule().stroke(.white.opacity(0.22), lineWidth: Theme.Stroke.hairline)
                            )
                            .shadow(color: Theme.Color.overlayScrim, radius: 10, y: 4)
                            .padding(.bottom, Theme.Space.s20)
                            .allowsHitTesting(false)
                            .transition(.opacity.combined(with: .scale(scale: 0.92)))
                        }
                    }
                    .animation(.spring(response: 0.22, dampingFraction: 0.85), value: viewModel.cullingToast?.id)

                FilmstripView(viewModel: viewModel)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Theme.Color.background)

            if viewModel.isInspectorOpen {
                LargeImageViewerSidebar(viewModel: viewModel)
                    .transition(.move(edge: .trailing).combined(with: .opacity))
            }
        }
        .animation(.easeInOut(duration: 0.2), value: viewModel.isInspectorOpen)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .ignoresSafeArea()
        .onChange(of: viewModel.currentFocusedPhotoSet?.id) { _, _ in
            viewModel.singleZoomState.reset()
        }
        .onChange(of: viewModel.selectedPhotoSets.map(\.id)) { _, _ in
            viewModel.sharedZoomState.reset()
        }
    }

    private var floatingViewerControls: some View {
        let activePhoto = viewModel.currentFocusedPhotoSet
        let currentZoom = viewModel.singleZoomState.zoomScale + viewModel.singleZoomState.currentAmount

        return HStack(spacing: Theme.Space.s8) {
            if let photo = activePhoto {
                HStack(spacing: Theme.Space.s8) {
                    Text(photo.baseName)
                        .font(Theme.Font.caption)
                        .fontWeight(.semibold)
                        .foregroundStyle(Theme.Color.textPrimary)
                        .lineLimit(1)

                    Text(photo.formatLabel)
                        .font(.system(size: 10, weight: .bold, design: .rounded))
                        .foregroundStyle(Theme.Color.textSecondary)
                }
                .padding(.horizontal, Theme.Space.s12)
                .padding(.vertical, 6)
                .background(.ultraThinMaterial, in: Capsule())
                .overlay(
                    Capsule().stroke(.white.opacity(0.22), lineWidth: Theme.Stroke.hairline)
                )
            }

            Spacer()

            HStack(spacing: Theme.Space.s6) {
                // Zoom level pill (click to toggle Fit <-> 200%)
                Button {
                    withAnimation(.spring(response: 0.25, dampingFraction: 0.9)) {
                        if currentZoom > 1.05 {
                            viewModel.singleZoomState.reset()
                        } else {
                            viewModel.singleZoomState.zoomScale = 2.0
                        }
                    }
                } label: {
                    Text(currentZoom > 1.05 ? "\(Int((currentZoom * 100).rounded()))%" : "Fit")
                        .font(.system(size: 11, weight: .semibold, design: .monospaced))
                        .foregroundStyle(currentZoom > 1.05 ? Theme.Color.accent : Theme.Color.textPrimary)
                        .padding(.horizontal, 9)
                        .padding(.vertical, 5)
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .help("Toggle Zoom (Fit / 200%)")

                Divider()
                    .frame(height: 14)

                // Edit in Photomator (E)
                Button {
                    viewModel.openFocusedPhotoInPhotomator()
                } label: {
                    Label("Edit", systemImage: "slider.horizontal.3")
                        .font(Theme.Font.caption)
                        .fontWeight(.medium)
                        .foregroundStyle(Theme.Color.textPrimary)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 5)
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .help("Edit in Photomator (E)")

                Divider()
                    .frame(height: 14)

                // Toggle Right Inspector Sidebar (I)
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        viewModel.isInspectorOpen.toggle()
                    }
                } label: {
                    Image(systemName: "sidebar.right")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(viewModel.isInspectorOpen ? Theme.Color.accent : Theme.Color.textPrimary)
                        .frame(width: 26, height: 24)
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .help(viewModel.isInspectorOpen ? "Hide Inspector (I)" : "Show Inspector (I)")

                // Close Viewer (Esc)
                Button {
                    viewModel.closeLargeImageViewer()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(Theme.Color.textPrimary)
                        .frame(width: 24, height: 24)
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .help("Close Viewer (Esc)")
            }
            .padding(.horizontal, Theme.Space.s8)
            .padding(.vertical, 3)
            .background(.ultraThinMaterial, in: Capsule())
            .overlay(
                Capsule().stroke(.white.opacity(0.22), lineWidth: Theme.Stroke.hairline)
            )
            .shadow(color: Theme.Color.overlayScrim, radius: 8, y: 2)
        }
    }

    // MARK: - Component Views

    @ViewBuilder
    private var imagePane: some View {
        let selected = viewModel.selectedPhotoSets
        Group {
            if selected.count >= 2 && selected.count <= 4 {
                comparisonGrid(for: selected)
            } else if viewModel.filteredPhotoSets.isEmpty {
                VStack {
                    Spacer()
                    Text("No photos to display")
                        .foregroundStyle(Theme.Color.textSecondary)
                    Spacer()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Theme.Color.background, in: RoundedRectangle(cornerRadius: Theme.Radius.xl))
            } else if let activePhoto = viewModel.currentFocusedPhotoSet {
                // Render only the focused photo directly instead of laying out a
                // LazyHStack of thousands of full-screen pages on open.
                LargeImagePane(photoSet: activePhoto, zoomState: viewModel.singleZoomState)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Theme.Color.background, in: RoundedRectangle(cornerRadius: Theme.Radius.xl))
                    .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.xl))
            }
        }
    }

    @ViewBuilder
    private func comparisonGrid(for selected: [PhotoSet]) -> some View {
        switch selected.count {
        case 2:
            HStack(spacing: Theme.Space.s12) {
                ForEach(selected) { photo in
                    LargeImagePane(photoSet: photo, zoomState: viewModel.sharedZoomState) {
                        viewModel.openFocusedPhotoInPhotomator()
                    }
                        .background(Theme.Color.background, in: RoundedRectangle(cornerRadius: Theme.Radius.xl))
                        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.xl))
                }
            }
        case 3:
            HStack(spacing: Theme.Space.s12) {
                ForEach(selected) { photo in
                    LargeImagePane(photoSet: photo, zoomState: viewModel.sharedZoomState) {
                        viewModel.openFocusedPhotoInPhotomator()
                    }
                        .background(Theme.Color.background, in: RoundedRectangle(cornerRadius: Theme.Radius.xl))
                        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.xl))
                }
            }
        case 4:
            VStack(spacing: Theme.Space.s12) {
                HStack(spacing: Theme.Space.s12) {
                    LargeImagePane(photoSet: selected[0], zoomState: viewModel.sharedZoomState) {
                        viewModel.openFocusedPhotoInPhotomator()
                    }
                        .background(Theme.Color.background, in: RoundedRectangle(cornerRadius: Theme.Radius.xl))
                        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.xl))
                    LargeImagePane(photoSet: selected[1], zoomState: viewModel.sharedZoomState) {
                        viewModel.openFocusedPhotoInPhotomator()
                    }
                        .background(Theme.Color.background, in: RoundedRectangle(cornerRadius: Theme.Radius.xl))
                        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.xl))
                }
                HStack(spacing: Theme.Space.s12) {
                    LargeImagePane(photoSet: selected[2], zoomState: viewModel.sharedZoomState) {
                        viewModel.openFocusedPhotoInPhotomator()
                    }
                        .background(Theme.Color.background, in: RoundedRectangle(cornerRadius: Theme.Radius.xl))
                        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.xl))
                    LargeImagePane(photoSet: selected[3], zoomState: viewModel.sharedZoomState) {
                        viewModel.openFocusedPhotoInPhotomator()
                    }
                        .background(Theme.Color.background, in: RoundedRectangle(cornerRadius: Theme.Radius.xl))
                        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.xl))
                }
            }
        default:
            EmptyView()
        }
    }
}



