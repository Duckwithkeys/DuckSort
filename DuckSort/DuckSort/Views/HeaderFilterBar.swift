//
//  HeaderFilterBar.swift
//  DuckSort
//
//  Horizontal culling and filter menu bar + native Filter popover.
//

import SwiftUI
import AppKit

struct HeaderFilterBar: View {
    @ObservedObject var viewModel: PhotoLibraryViewModel
    @State private var showFilterPopover = false

    var body: some View {
        HStack(spacing: 12) {
            sortControls

            Spacer()

            Button {
                showFilterPopover.toggle()
            } label: {
                let hasActiveFilters = viewModel.activeFilterCount > 0 && viewModel.isFilterPopoverEnabled
                Image(systemName: "line.3.horizontal.decrease.circle")
                    .foregroundStyle(hasActiveFilters ? Theme.Color.accent : .secondary)
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .popover(isPresented: $showFilterPopover, arrowEdge: .bottom) {
                FilterPopoverContent(viewModel: viewModel)
            }
            .help("Filter Options")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(.bar)
        .overlay(
            Divider(),
            alignment: .bottom
        )
        .zIndex(1000)
    }

    // MARK: - Sort Controls
    private var sortControls: some View {
        HStack(spacing: 8) {
            Picker("Sort", selection: $viewModel.sortOrder) {
                Text("Date").tag(PhotoLibraryViewModel.SortOrder.date)
                Text("Name").tag(PhotoLibraryViewModel.SortOrder.name)
                Text("Size").tag(PhotoLibraryViewModel.SortOrder.size)
            }
            .pickerStyle(.segmented)
            .controlSize(.small)
            .frame(width: 180)

            Button {
                withAnimation(Theme.Motion.snappy) {
                    viewModel.sortDirection = viewModel.sortDirection == .ascending ? .descending : .ascending
                }
            } label: {
                Image(systemName: viewModel.sortDirection == .ascending ? "arrow.up" : "arrow.down")
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .help("Sort Direction: \(viewModel.sortDirection.rawValue)")
        }
    }
}

// MARK: - Popover Filter Panel Content
struct FilterPopoverContent: View {
    @ObservedObject var viewModel: PhotoLibraryViewModel

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Text("Filter")
                    .font(.headline)
                    .foregroundStyle(.primary)

                Spacer()

                Button("Reset") {
                    withAnimation(.smooth(duration: 0.2)) {
                        viewModel.resetFilterPopover()
                    }
                }
                .buttonStyle(.borderless)
                .controlSize(.small)
                .help("Reset all filters")

                Toggle("", isOn: $viewModel.isFilterPopoverEnabled)
                    .toggleStyle(.switch)
                    .labelsHidden()
                    .controlSize(.small)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)

            Divider()

            ScrollView {
                VStack(spacing: 10) {
                    HStack(spacing: 8) {
                        Image(systemName: "arrow.up.arrow.down")
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                            .frame(width: 16)

                        Text("Sort By")
                            .font(.body)
                            .foregroundStyle(.primary)

                        Spacer()

                        Picker("", selection: $viewModel.sortOrder) {
                            Text("Date").tag(PhotoLibraryViewModel.SortOrder.date)
                            Text("Name").tag(PhotoLibraryViewModel.SortOrder.name)
                            Text("Size").tag(PhotoLibraryViewModel.SortOrder.size)
                        }
                        .pickerStyle(.menu)
                        .labelsHidden()
                        .frame(width: 90)
                        .controlSize(.small)

                        Button {
                            withAnimation(Theme.Motion.snappy) {
                                viewModel.sortDirection = viewModel.sortDirection == .ascending ? .descending : .ascending
                            }
                        } label: {
                            Image(systemName: viewModel.sortDirection == .ascending ? "arrow.up" : "arrow.down")
                                .font(.system(size: 11, weight: .semibold))
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        .help("Toggle Sort Direction (\(viewModel.sortDirection.rawValue))")
                    }
                    .frame(height: 26)

                    Divider()

                    FilterRow(
                        isActive: $viewModel.filterEditedActive,
                        icon: "slider.horizontal.3",
                        title: "Edited"
                    ) {
                        Picker("", selection: $viewModel.filterEdited) {
                            Text("Include").tag(PhotoLibraryViewModel.BinaryFilter.include)
                            Text("Exclude").tag(PhotoLibraryViewModel.BinaryFilter.exclude)
                        }
                        .pickerStyle(.menu)
                        .labelsHidden()
                        .frame(width: 100)
                        .controlSize(.small)
                    }

                    Divider()

                    FilterRow(
                        isActive: $viewModel.filterRawActive,
                        icon: "r.square",
                        title: "RAW"
                    ) {
                        Picker("", selection: $viewModel.filterRaw) {
                            Text("Include").tag(PhotoLibraryViewModel.BinaryFilter.include)
                            Text("Exclude").tag(PhotoLibraryViewModel.BinaryFilter.exclude)
                        }
                        .pickerStyle(.menu)
                        .labelsHidden()
                        .frame(width: 100)
                        .controlSize(.small)
                    }

                    Divider()

                    FilterRow(
                        isActive: $viewModel.filterRatingActive,
                        icon: "star",
                        title: "Rating"
                    ) {
                        HStack(spacing: 4) {
                            Picker("", selection: $viewModel.filterRatingValue) {
                                Text("Unrated").tag(0)
                                Text("★").tag(1)
                                Text("★★").tag(2)
                                Text("★★★").tag(3)
                                Text("★★★★").tag(4)
                                Text("★★★★★").tag(5)
                            }
                            .pickerStyle(.menu)
                            .labelsHidden()
                            .frame(width: 100)
                            .controlSize(.small)

                            Menu {
                                ForEach(PhotoLibraryViewModel.RatingCondition.allCases, id: \.self) { condition in
                                    Button(condition.rawValue) {
                                        viewModel.filterRatingCondition = condition
                                    }
                                }
                            } label: {
                                Image(systemName: "ellipsis.circle")
                                    .font(.system(size: 13))
                                    .foregroundStyle(.secondary)
                            }
                            .menuStyle(.borderlessButton)
                            .menuIndicator(.hidden)
                            .frame(width: 22, height: 22)
                            .help("Condition: \(viewModel.filterRatingCondition.rawValue)")
                        }
                    }

                    Divider()

                    FilterRow(
                        isActive: $viewModel.filterFlagActive,
                        icon: "flag",
                        title: "Flag"
                    ) {
                        Picker("", selection: $viewModel.filterFlag) {
                            Text("All Flags").tag(PhotoLibraryViewModel.FlagFilter.all)
                            Text("Flagged").tag(PhotoLibraryViewModel.FlagFilter.flagged)
                            Text("Rejected").tag(PhotoLibraryViewModel.FlagFilter.rejected)
                            Text("Unflagged").tag(PhotoLibraryViewModel.FlagFilter.unflagged)
                        }
                        .pickerStyle(.menu)
                        .labelsHidden()
                        .frame(width: 110)
                        .controlSize(.small)
                    }

                    Divider()

                    VStack(alignment: .leading, spacing: 6) {
                        FilterRow(
                            isActive: $viewModel.filterNameActive,
                            icon: "doc",
                            title: "File Name"
                        ) {
                            Picker("", selection: $viewModel.nameFilterCondition) {
                                Text("Contains").tag(PhotoLibraryViewModel.NameCondition.contains)
                                Text("Matches").tag(PhotoLibraryViewModel.NameCondition.matches)
                                Text("Starts with").tag(PhotoLibraryViewModel.NameCondition.startsWith)
                                Text("Ends with").tag(PhotoLibraryViewModel.NameCondition.endsWith)
                            }
                            .pickerStyle(.menu)
                            .labelsHidden()
                            .frame(width: 110)
                            .controlSize(.small)
                        }

                        if viewModel.filterNameActive {
                            TextField("File name text", text: $viewModel.nameFilterQuery)
                                .textFieldStyle(.roundedBorder)
                                .controlSize(.small)
                                .padding(.leading, 24)
                        }
                    }

                    Divider()

                    VStack(alignment: .leading, spacing: 6) {
                        FilterRow(
                            isActive: $viewModel.filterDateActive,
                            icon: "calendar",
                            title: "Date"
                        ) {
                            Spacer()
                        }

                        if viewModel.filterDateActive {
                            HStack(spacing: 6) {
                                DatePicker("", selection: $viewModel.filterStartDate, displayedComponents: .date)
                                    .labelsHidden()
                                    .controlSize(.small)
                                    .frame(maxWidth: .infinity)

                                Text("to")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)

                                DatePicker("", selection: $viewModel.filterEndDate, displayedComponents: .date)
                                    .labelsHidden()
                                    .controlSize(.small)
                                    .frame(maxWidth: .infinity)
                            }
                            .padding(.leading, 24)
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
            }
        }
        .frame(width: 320)
        .padding(.bottom, 8)
    }
}

// MARK: - Row Helper Component
struct FilterRow<Content: View>: View {
    @Binding var isActive: Bool
    let icon: String
    let title: String
    let content: () -> Content

    var body: some View {
        HStack(spacing: 8) {
            Toggle("", isOn: $isActive)
                .toggleStyle(.checkbox)
                .labelsHidden()

            Image(systemName: icon)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .frame(width: 16)

            Text(title)
                .font(.body)
                .foregroundStyle(.primary)

            Spacer()

            content()
                .disabled(!isActive)
                .opacity(isActive ? 1.0 : 0.5)
        }
        .frame(height: 26)
    }
}
