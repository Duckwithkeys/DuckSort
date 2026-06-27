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
    }

    // MARK: - Component Views

    @ViewBuilder
    private var imagePane: some View {
        if let photo = viewModel.currentFocusedPhotoSet {
            LargeImagePane(photoSet: photo)
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
}
