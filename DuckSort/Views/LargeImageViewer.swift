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

    @StateObject private var singleZoomState = SynchronizedZoomState()
    @StateObject private var sharedZoomState = SynchronizedZoomState()

    var body: some View {
        HStack(spacing: 0) {
            VStack(spacing: 0) {
                imagePane
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .padding(.horizontal, Theme.Space.s12)
                    .padding(.bottom, Theme.Space.s12)
                    .padding(.top, 54)

                FilmstripView(viewModel: viewModel)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Theme.Color.background)

            LargeImageViewerSidebar(viewModel: viewModel)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .ignoresSafeArea()
        .onChange(of: viewModel.currentFocusedPhotoSet?.id) { _, _ in
            singleZoomState.reset()
        }
        .onChange(of: viewModel.selectedPhotoSets.map(\.id)) { _, _ in
            sharedZoomState.reset()
        }
    }

    // MARK: - Component Views

    @ViewBuilder
    private var imagePane: some View {
        let selected = viewModel.selectedPhotoSets
        if selected.count >= 2 && selected.count <= 4 {
            comparisonGrid(for: selected)
        } else if let photo = viewModel.currentFocusedPhotoSet {
            LargeImagePane(photoSet: photo, zoomState: singleZoomState) {
                viewModel.openFocusedPhotoInPhotomator()
            }
                .background(Theme.Color.scrim, in: RoundedRectangle(cornerRadius: Theme.Radius.xl))
                .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.xl))
        } else {
            VStack {
                Spacer()
                Text("No photos to display")
                    .foregroundStyle(Theme.Color.textSecondary)
                Spacer()
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Theme.Color.scrim, in: RoundedRectangle(cornerRadius: Theme.Radius.xl))
        }
    }

    @ViewBuilder
    private func comparisonGrid(for selected: [PhotoSet]) -> some View {
        switch selected.count {
        case 2:
            HStack(spacing: Theme.Space.s12) {
                ForEach(selected) { photo in
                    LargeImagePane(photoSet: photo, zoomState: sharedZoomState) {
                        viewModel.openFocusedPhotoInPhotomator()
                    }
                        .background(Theme.Color.scrim, in: RoundedRectangle(cornerRadius: Theme.Radius.xl))
                        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.xl))
                }
            }
        case 3:
            HStack(spacing: Theme.Space.s12) {
                ForEach(selected) { photo in
                    LargeImagePane(photoSet: photo, zoomState: sharedZoomState) {
                        viewModel.openFocusedPhotoInPhotomator()
                    }
                        .background(Theme.Color.scrim, in: RoundedRectangle(cornerRadius: Theme.Radius.xl))
                        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.xl))
                }
            }
        case 4:
            VStack(spacing: Theme.Space.s12) {
                HStack(spacing: Theme.Space.s12) {
                    LargeImagePane(photoSet: selected[0], zoomState: sharedZoomState) {
                        viewModel.openFocusedPhotoInPhotomator()
                    }
                        .background(Theme.Color.scrim, in: RoundedRectangle(cornerRadius: Theme.Radius.xl))
                        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.xl))
                    LargeImagePane(photoSet: selected[1], zoomState: sharedZoomState) {
                        viewModel.openFocusedPhotoInPhotomator()
                    }
                        .background(Theme.Color.scrim, in: RoundedRectangle(cornerRadius: Theme.Radius.xl))
                        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.xl))
                }
                HStack(spacing: Theme.Space.s12) {
                    LargeImagePane(photoSet: selected[2], zoomState: sharedZoomState) {
                        viewModel.openFocusedPhotoInPhotomator()
                    }
                        .background(Theme.Color.scrim, in: RoundedRectangle(cornerRadius: Theme.Radius.xl))
                        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.xl))
                    LargeImagePane(photoSet: selected[3], zoomState: sharedZoomState) {
                        viewModel.openFocusedPhotoInPhotomator()
                    }
                        .background(Theme.Color.scrim, in: RoundedRectangle(cornerRadius: Theme.Radius.xl))
                        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.xl))
                }
            }
        default:
            EmptyView()
        }
    }
}
