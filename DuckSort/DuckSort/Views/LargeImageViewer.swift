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

    private var scrollPositionBinding: Binding<Int?> {
        Binding(
            get: { viewModel.focusedPhotoIndex },
            set: { newValue in
                if let newValue {
                    viewModel.focusedPhotoIndex = newValue
                }
            }
        )
    }

    var body: some View {
        HStack(spacing: 0) {
            VStack(spacing: 0) {
                // Darker header separation band
                Theme.Color.sidebarBackground
                    .frame(height: 56)
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
                    .padding(.top, Theme.Space.s12) // Space below the header separation band
                    .contentShape(Rectangle())
                    .onTapGesture {
                        NSApp.keyWindow?.makeFirstResponder(nil)
                    }

                FilmstripView(viewModel: viewModel)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Theme.Color.background)

            LargeImageViewerSidebar(viewModel: viewModel)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .ignoresSafeArea()
        .onChange(of: viewModel.currentFocusedPhotoSet?.id) { _, _ in
            viewModel.singleZoomState.reset()
        }
        .onChange(of: viewModel.selectedPhotoSets.map(\.id)) { _, _ in
            viewModel.sharedZoomState.reset()
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
            } else {
                GeometryReader { geometry in
                    ScrollView(.horizontal, showsIndicators: false) {
                        LazyHStack(spacing: 0) {
                            ForEach(0..<viewModel.filteredPhotoSets.count, id: \.self) { index in
                                let photo = viewModel.filteredPhotoSets[index]
                                LargeImagePane(photoSet: photo, zoomState: viewModel.singleZoomState)
                                    .frame(width: geometry.size.width, height: geometry.size.height)
                                    .background(Theme.Color.background, in: RoundedRectangle(cornerRadius: Theme.Radius.xl))
                                    .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.xl))
                                    .id(index)
                            }
                        }
                        .scrollTargetLayout()
                    }
                    .scrollPosition(id: scrollPositionBinding)
                    .scrollTargetBehavior(.paging)
                }
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



