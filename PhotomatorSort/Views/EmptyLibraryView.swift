//
//  EmptyLibraryView.swift
//  PhotomatorSort
//

import SwiftUI

struct EmptyLibraryView: View {
    let isScanning: Bool
    let selectFolderAction: () -> Void

    var body: some View {
        VStack(spacing: 24) {
            if isScanning {
                ProgressView()
                    .controlSize(.large)
                Text("Scanning photoshoot...")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(.primary)
            } else {
                Text("Welcome to Photomator Sort")
                    .font(.largeTitle.weight(.bold))
                    .foregroundStyle(PhotomatorTheme.textPrimary)
                
                Text("To get started with Photomator Sort, do any of the following:")
                    .font(.subheadline)
                    .foregroundStyle(PhotomatorTheme.textSecondary)
                
                HStack(spacing: 20) {
                    VStack(spacing: 12) {
                        Image(systemName: "square.and.arrow.down.on.square")
                            .font(.system(size: 36))
                            .foregroundStyle(PhotomatorTheme.textSecondary)
                        Text("Drag files or folders directly\ninto Photomator Sort.")
                            .font(.caption)
                            .foregroundStyle(PhotomatorTheme.textSecondary)
                            .multilineTextAlignment(.center)
                    }
                    .frame(width: 200, height: 160)
                    .background(PhotomatorTheme.cellBackground, in: RoundedRectangle(cornerRadius: 8))
                    
                    VStack(spacing: 12) {
                        Image(systemName: "filemenu.and.selection")
                            .font(.system(size: 36))
                            .foregroundStyle(PhotomatorTheme.textSecondary)
                        Text("Choose Import from the File\nmenu.")
                            .font(.caption)
                            .foregroundStyle(PhotomatorTheme.textSecondary)
                            .multilineTextAlignment(.center)
                    }
                    .frame(width: 200, height: 160)
                    .background(PhotomatorTheme.cellBackground, in: RoundedRectangle(cornerRadius: 8))
                }
                .padding(.vertical, 20)
                
                Button("Import...") {
                    selectFolderAction()
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .tint(PhotomatorTheme.selectedBlue)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(PhotomatorTheme.background)
    }
}
