//
//  SidebarView.swift
//  PhotomatorSort
//

import SwiftUI

struct SidebarView: View {
    @ObservedObject var viewModel: PhotoLibraryViewModel

    var body: some View {
        VStack(spacing: 0) {
            Spacer().frame(height: 38) // Space for macOS traffic lights

            List {
                // MARK: - Library Section
                Section("LIBRARY") {
                    ForEach(PhotoFilterRule.allCases) { rule in
                        Button {
                            viewModel.filterRule = rule
                        } label: {
                            HStack {
                                Image(systemName: rule.systemImage)
                                    .foregroundStyle(viewModel.filterRule == rule ? PhotomatorTheme.selectedBlue : PhotomatorTheme.textSecondary)
                                    .frame(width: 16)
                                Text(rule.rawValue)
                                    .foregroundStyle(PhotomatorTheme.textPrimary)
                                Spacer()
                                // Count badge
                                let count = count(for: rule)
                                if count > 0 {
                                    Text("\(count)")
                                        .font(.caption)
                                        .foregroundStyle(PhotomatorTheme.textSecondary)
                                }
                            }
                            .padding(.vertical, 4)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .listRowBackground(
                            RoundedRectangle(cornerRadius: 6)
                                .fill(viewModel.filterRule == rule ? PhotomatorTheme.selectedBlue.opacity(0.15) : Color.clear)
                                .padding(.horizontal, 8)
                        )
                    }
                }
                
                // MARK: - Sources Section
                Section("SOURCES") {
                    if viewModel.sourceDirectories.isEmpty {
                        Text("No sources")
                            .font(.caption)
                            .foregroundStyle(PhotomatorTheme.textTertiary)
                    } else {
                        ForEach(viewModel.sourceDirectories, id: \.self) { url in
                            HStack {
                                Image(systemName: "folder")
                                    .foregroundStyle(PhotomatorTheme.textSecondary)
                                    .frame(width: 16)
                                Text(url.lastPathComponent)
                                    .foregroundStyle(PhotomatorTheme.textPrimary)
                                    .lineLimit(1)
                                    .truncationMode(.middle)
                            }
                            .padding(.vertical, 4)
                            .listRowBackground(Color.clear)
                        }
                    }
                }
                
                // MARK: - Tags Section
                Section("TAGS") {
                    if viewModel.tagStore.tags.isEmpty {
                        Text("No tags")
                            .font(.caption)
                            .foregroundStyle(PhotomatorTheme.textTertiary)
                    } else {
                        ForEach(viewModel.tagStore.categories) { category in
                            let tagsInCategory = viewModel.tagStore.tags(in: category.id)
                            if !tagsInCategory.isEmpty {
                                DisclosureGroup {
                                    ForEach(tagsInCategory) { tag in
                                        Button {
                                            if viewModel.selectedTagFilters.contains(tag.id) {
                                                viewModel.selectedTagFilters.remove(tag.id)
                                            } else {
                                                viewModel.selectedTagFilters.insert(tag.id)
                                            }
                                        } label: {
                                            HStack {
                                                Circle()
                                                    .fill(tag.color)
                                                    .frame(width: 10, height: 10)
                                                Text(tag.name)
                                                    .foregroundStyle(PhotomatorTheme.textPrimary)
                                                Spacer()
                                                let count = count(forTag: tag.id)
                                                if count > 0 {
                                                    Text("\(count)")
                                                        .font(.caption)
                                                        .foregroundStyle(PhotomatorTheme.textSecondary)
                                                }
                                            }
                                            .padding(.vertical, 4)
                                            .contentShape(Rectangle())
                                        }
                                        .buttonStyle(.plain)
                                        .listRowBackground(
                                            RoundedRectangle(cornerRadius: 6)
                                                .fill(viewModel.selectedTagFilters.contains(tag.id) ? PhotomatorTheme.selectedBlue.opacity(0.15) : Color.clear)
                                                .padding(.horizontal, 8)
                                        )
                                    }
                                } label: {
                                    Text(category.name)
                                        .font(.subheadline)
                                        .foregroundStyle(PhotomatorTheme.textPrimary)
                                }
                                .tint(PhotomatorTheme.textSecondary)
                            }
                        }
                    }
                }
            }
            .listStyle(.sidebar)
            .scrollContentBackground(.hidden)
            .background(PhotomatorTheme.sidebarBackground)
        }
        .frame(minWidth: 160, idealWidth: 180, maxWidth: 240)
    }
    
    private func count(for rule: PhotoFilterRule) -> Int {
        switch rule {
        case .allPhotos:
            return viewModel.photoSets.count
        case .editedOnly:
            return viewModel.editedCount
        case .uneditedOnly:
            return viewModel.uneditedCount
        }
    }
    
    private func count(forTag tagID: UUID) -> Int {
        viewModel.photoSets.filter { viewModel.tagStore.assignedTagIDs(for: $0.id).contains(tagID) }.count
    }
}
