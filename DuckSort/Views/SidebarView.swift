//
//  SidebarView.swift
//  DuckSort
//

import SwiftUI

struct SidebarView: View {
    @ObservedObject var viewModel: PhotoLibraryViewModel
    @FocusState private var isSearchFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            // Search
            HStack(spacing: Theme.Space.s6) {
                Image(systemName: "magnifyingglass")
                    .font(Theme.Font.caption)
                    .foregroundStyle(Theme.Color.textSecondary)
                TextField("Search files…", text: $viewModel.searchText)
                    .textFieldStyle(.plain)
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.Color.textPrimary)
                    .focused($isSearchFocused)
                if !viewModel.searchText.isEmpty {
                    Button {
                        viewModel.searchText = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(Theme.Font.caption)
                            .foregroundStyle(Theme.Color.textSecondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, Theme.Space.s8)
            .padding(.vertical, Theme.Space.s4)
            .background(Theme.Color.cellBackground, in: RoundedRectangle(cornerRadius: Theme.Radius.m))
            .overlay(
                RoundedRectangle(cornerRadius: Theme.Radius.m)
                    .stroke(Theme.Color.separator, lineWidth: Theme.Stroke.hairline)
            )
            .padding(.horizontal, Theme.Space.s16)
            .padding(.bottom, Theme.Space.s8)

            // Permanent filter bar — stays put so it doesn't shift the
            // rest of the sidebar when the user picks or clears filters.
            // Greys out when no filters are active.
            ActiveFiltersBar(
                count: viewModel.activeFilterCount,
                isEmpty: viewModel.activeFilterCount == 0,
                onClear: viewModel.clearAllFilters
            )
            .padding(.horizontal, Theme.Space.s16)
            .padding(.bottom, Theme.Space.s8)

            List {
                LibrarySectionView(viewModel: viewModel)
                SourcesSectionView(viewModel: viewModel)
                TagsSectionView(viewModel: viewModel)
            }
            .listStyle(.sidebar)
            .scrollContentBackground(.hidden)
        }
        .frame(minWidth: 220, idealWidth: 240, maxWidth: 280)
        .background(Theme.Color.sidebarBackground)
        .onAppear {
            // Don't let the first responder auto-grab the search field;
            // keyboard shortcuts in the grid should work without the user
            // having to click out of the field first.
            isSearchFocused = false
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                isSearchFocused = false
            }
        }
    }

    private var brandBar: some View {
        HStack(spacing: Theme.Space.s8) {
            Image("duck_logo")
                .resizable()
                .interpolation(.high)
                .aspectRatio(contentMode: .fit)
                .frame(width: 24, height: 24)

            Text("DuckSort")
                .font(Theme.Font.headline)
                .foregroundStyle(Theme.Color.textPrimary)
            Spacer()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, Theme.Space.s16)
        .padding(.bottom, Theme.Space.s12)
        .background(Theme.Color.sidebarBackground)
    }
}

// MARK: - Library Section View

struct LibrarySectionView: View {
    @ObservedObject var viewModel: PhotoLibraryViewModel
    @State private var hoveredRule: PhotoFilterRule? = nil

    var body: some View {
        Section("LIBRARY") {
            ForEach(PhotoFilterRule.allCases) { rule in
                Button {
                    viewModel.filterRule = rule
                } label: {
                    HStack {
                        Image(systemName: rule.systemImage)
                            .foregroundStyle(viewModel.filterRule == rule ? Theme.Color.accent : Theme.Color.textSecondary)
                            .frame(width: 16)
                        Text(rule.rawValue)
                            .foregroundStyle(Theme.Color.textPrimary)
                        Spacer()
                        let count = count(for: rule)
                        if count > 0 {
                            Text("\(count)")
                                .font(Theme.Font.caption)
                                .foregroundStyle(Theme.Color.textSecondary)
                        }
                    }
                    .padding(.vertical, Theme.Space.s4)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .onHover { hovering in
                    withAnimation(.easeInOut(duration: 0.12)) {
                        hoveredRule = hovering ? rule : nil
                    }
                }
                .listRowBackground(
                    RoundedRectangle(cornerRadius: Theme.Radius.m)
                        .fill(
                            viewModel.filterRule == rule
                            ? Theme.Color.rowSelectedFill
                            : (hoveredRule == rule ? Theme.Color.rowHoverFill : Color.clear)
                        )
                        .padding(.horizontal, Theme.Space.s8)
                )
            }
        }
    }

    private func count(for rule: PhotoFilterRule) -> Int {
        switch rule {
        case .allPhotos:   return viewModel.cachedAllPhotosCount
        case .editedOnly:  return viewModel.cachedEditedCount
        case .uneditedOnly: return viewModel.cachedUneditedCount
        }
    }
}

// MARK: - Sources Section View

struct SourcesSectionView: View {
    @ObservedObject var viewModel: PhotoLibraryViewModel

    var body: some View {
        Section("SOURCES") {
            ForEach(viewModel.sourceDirectories, id: \.self) { url in
                FolderTreeNode(
                    viewModel: viewModel,
                    folder: url,
                    parentSource: url,
                    depth: 0,
                    isRoot: true
                )
            }

            ForEach(viewModel.looseFiles, id: \.self) { url in
                SourceRow(
                    url: url,
                    isFolder: false,
                    hasError: viewModel.failedSources.contains(url),
                    onReveal: {
                        NSWorkspace.shared.activateFileViewerSelecting([url])
                    },
                    onRemove: {
                        viewModel.removeLooseFile(url)
                    }
                )
            }

            Button(action: { viewModel.addSourceDirectory() }) {
                HStack(spacing: Theme.Space.s8) {
                    Image(systemName: "plus.circle")
                        .foregroundStyle(Theme.Color.accent)
                        .frame(width: 16)
                    Text("Add Source…")
                        .foregroundStyle(Theme.Color.accent)
                }
                .padding(.vertical, Theme.Space.s4)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .listRowBackground(Color.clear)
        }
    }
}

// MARK: - Tags Section View

struct TagsSectionView: View {
    @ObservedObject var viewModel: PhotoLibraryViewModel
    @State private var hoveredTagID: UUID? = nil
    @State private var isFlagsExpanded = true
    @State private var isFlagsHovered = false
    @State private var expandedCategoryIDs: Set<UUID> = []
    @State private var hoveredCategoryID: UUID? = nil

    var body: some View {
        Section("TAGS") {
            DisclosureGroup(isExpanded: $isFlagsExpanded) {
                SystemFilterRow(
                    name: "Flagged",
                    systemImage: "flag.fill",
                    iconColor: Theme.Color.textInverse,
                    isSelected: viewModel.selectedFlags.contains(1),
                    count: viewModel.cachedFlagCounts[1] ?? 0,
                    action: { viewModel.toggleFlagFilter(1) }
                )
                SystemFilterRow(
                    name: "Rejected",
                    systemImage: "flag.slash.fill",
                    iconColor: Theme.Color.danger,
                    isSelected: viewModel.selectedFlags.contains(-1),
                    count: viewModel.cachedFlagCounts[-1] ?? 0,
                    action: { viewModel.toggleFlagFilter(-1) }
                )
                SystemFilterRow(
                    name: "Unrated",
                    systemImage: "star.slash",
                    iconColor: Theme.Color.textTertiary,
                    isSelected: viewModel.selectedRatings.contains(0),
                    count: viewModel.cachedRatingCounts[0] ?? 0,
                    action: { viewModel.toggleRatingFilter(0) }
                )
                ForEach((1...5).reversed(), id: \.self) { rating in
                    SystemFilterRow(
                        name: "\(rating) Star\(rating == 1 ? "" : "s")",
                        systemImage: "star.fill",
                        iconColor: Theme.Color.rating,
                        isSelected: viewModel.selectedRatings.contains(rating),
                        count: viewModel.cachedRatingCounts[rating] ?? 0,
                        action: { viewModel.toggleRatingFilter(rating) }
                    )
                }
            } label: {
                HStack {
                    Text("Flags & Ratings")
                        .font(Theme.Font.subheadline)
                        .foregroundStyle(Theme.Color.textPrimary)
                    Spacer()
                }
                .contentShape(Rectangle())
                .onTapGesture { isFlagsExpanded.toggle() }
                .onHover { hovering in
                    withAnimation(.easeInOut(duration: 0.12)) { isFlagsHovered = hovering }
                }
            }
            .tint(Theme.Color.textSecondary)
            .listRowBackground(
                RoundedRectangle(cornerRadius: Theme.Radius.m)
                    .fill(isFlagsHovered ? Theme.Color.rowHoverFill : Color.clear)
                    .padding(.horizontal, Theme.Space.s8)
            )

            if viewModel.tagStore.tags.isEmpty {
                Text("No tags")
                    .font(Theme.Font.caption)
                    .foregroundStyle(Theme.Color.textTertiary)
            } else {
                ForEach(viewModel.tagStore.categories) { category in
                    let tagsInCategory = viewModel.tagStore.tags(in: category.id)
                    if !tagsInCategory.isEmpty {
                        let isExpandedBinding = Binding<Bool>(
                            get: { expandedCategoryIDs.contains(category.id) },
                            set: { isExpanded in
                                if isExpanded {
                                    expandedCategoryIDs.insert(category.id)
                                } else {
                                    expandedCategoryIDs.remove(category.id)
                                }
                            }
                        )
                        DisclosureGroup(isExpanded: isExpandedBinding) {
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
                                            .foregroundStyle(Theme.Color.textPrimary)
                                        Spacer()
                                        let count = viewModel.cachedTagCounts[tag.id] ?? 0
                                        if count > 0 {
                                            Text("\(count)")
                                                .font(Theme.Font.caption)
                                                .foregroundStyle(Theme.Color.textSecondary)
                                        }
                                    }
                                    .padding(.vertical, Theme.Space.s4)
                                    .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)
                                .onHover { hovering in
                                    withAnimation(.easeInOut(duration: 0.12)) {
                                        hoveredTagID = hovering ? tag.id : nil
                                    }
                                }
                                .listRowBackground(
                                    RoundedRectangle(cornerRadius: Theme.Radius.m)
                                        .fill(
                                            viewModel.selectedTagFilters.contains(tag.id)
                                            ? Theme.Color.rowSelectedFill
                                            : (hoveredTagID == tag.id ? Theme.Color.rowHoverFill : Color.clear)
                                        )
                                        .padding(.horizontal, Theme.Space.s8)
                                )
                            }
                        } label: {
                            HStack {
                                Text(category.name)
                                    .font(Theme.Font.subheadline)
                                    .foregroundStyle(Theme.Color.textPrimary)
                                Spacer()
                            }
                            .contentShape(Rectangle())
                            .onTapGesture { isExpandedBinding.wrappedValue.toggle() }
                            .onHover { hovering in
                                withAnimation(.easeInOut(duration: 0.12)) {
                                    hoveredCategoryID = hovering ? category.id : nil
                                }
                            }
                        }
                        .tint(Theme.Color.textSecondary)
                        .listRowBackground(
                            RoundedRectangle(cornerRadius: Theme.Radius.m)
                                .fill(hoveredCategoryID == category.id ? Theme.Color.rowHoverFill : Color.clear)
                                .padding(.horizontal, Theme.Space.s8)
                        )
                    }
                }
            }
        }
        .onAppear {
            if expandedCategoryIDs.isEmpty {
                expandedCategoryIDs = Set(viewModel.tagStore.categories.map(\.id))
            }
        }
    }
}

// MARK: - Component Row Views

struct SourceRow: View {
    let url: URL
    let isFolder: Bool
    let hasError: Bool
    let onReveal: () -> Void
    let onRemove: () -> Void
    @State private var isHovered = false

    var body: some View {
        HStack {
            Image(systemName: isFolder ? "folder" : "photo")
                .foregroundStyle(hasError ? Theme.Color.danger : Theme.Color.textSecondary)
                .frame(width: 16)
            Text(url.lastPathComponent)
                .foregroundStyle(hasError ? Theme.Color.danger : Theme.Color.textPrimary)
                .lineLimit(1)
                .truncationMode(.middle)

            if hasError {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(Theme.Font.caption)
                    .foregroundStyle(Theme.Color.danger)
                    .help("Failed to read this source")
            }

            Spacer()

            if isHovered {
                HStack(spacing: Theme.Space.s8) {
                    Button(action: onReveal) {
                        Image(systemName: "magnifyingglass")
                            .font(Theme.Font.caption)
                            .foregroundStyle(Theme.Color.textSecondary)
                    }
                    .buttonStyle(.plain)
                    .help("Reveal in Finder")

                    Button(action: onRemove) {
                        Image(systemName: "xmark.circle")
                            .font(Theme.Font.caption)
                            .foregroundStyle(Theme.Color.textSecondary)
                    }
                    .buttonStyle(.plain)
                    .help(isFolder ? "Remove source folder" : "Remove source file")
                }
            }
        }
        .padding(.vertical, Theme.Space.s4)
        .contentShape(Rectangle())
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.12)) { isHovered = hovering }
        }
        .contextMenu {
            Button("Reveal in Finder") { onReveal() }
            Button(isFolder ? "Remove Source Folder" : "Remove Source File") { onRemove() }
        }
        .listRowBackground(
            RoundedRectangle(cornerRadius: Theme.Radius.m)
                .fill(isHovered ? Theme.Color.rowHoverFill : Color.clear)
                .padding(.horizontal, Theme.Space.s8)
        )
    }
}

struct SystemFilterRow: View {
    let name: String
    let systemImage: String
    let iconColor: Color
    let isSelected: Bool
    let count: Int
    let action: () -> Void
    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            HStack {
                Image(systemName: systemImage)
                    .foregroundStyle(iconColor)
                    .frame(width: 12, height: 12)
                Text(name)
                    .foregroundStyle(Theme.Color.textPrimary)
                Spacer()
                if count > 0 {
                    Text("\(count)")
                        .font(Theme.Font.caption)
                        .foregroundStyle(Theme.Color.textSecondary)
                }
            }
            .padding(.vertical, Theme.Space.s4)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.12)) { isHovered = hovering }
        }
        .listRowBackground(
            RoundedRectangle(cornerRadius: Theme.Radius.m)
                .fill(
                    isSelected
                    ? Theme.Color.rowSelectedFill
                    : (isHovered ? Theme.Color.rowHoverFill : Color.clear)
                )
                .padding(.horizontal, Theme.Space.s8)
        )
    }
}

// MARK: - Custom Section / Subfolder Rows

// Recursive tree node for a folder under a source. The root node (a
// source itself) gets a slightly different visual treatment (chevron
// rotates, "Remove" replaces "Reveal"); deeper nodes reuse the same
// row template but with a leading indent that grows with `depth`.
//
// Each node lazily computes its children only when expanded, so the
// sidebar stays responsive even with deeply nested photo libraries.
// Children themselves are recursive `FolderTreeNode` views — there's no
// arbitrary depth limit.
struct FolderTreeNode: View {
    @ObservedObject var viewModel: PhotoLibraryViewModel
    let folder: URL
    let parentSource: URL
    let depth: Int
    let isRoot: Bool

    @State private var isExpanded: Bool = false
    @State private var isHovered: Bool = false

    /// Subfolder children are computed once on first expansion, then cached
    /// in `@State` so expanding/collapsing doesn't re-walk `photoSets`.
    @State private var cachedChildren: [URL]? = nil

    /// Photo sets directly in this folder (not in subfolders) are computed
    /// once on first expansion, then cached in `@State`.
    @State private var cachedPhotos: [PhotoSet]? = nil

    private var hasFailed: Bool {
        isRoot && viewModel.failedSources.contains(folder)
    }

    private var isSubtreeSelected: Bool {
        guard let active = viewModel.selectedSubfolderFilter else { return false }
        let activePath = active.standardizedFileURL.path
        let folderPath = folder.standardizedFileURL.path
        return activePath == folderPath
            || (activePath.count > folderPath.count
                && activePath.hasPrefix(folderPath)
                && activePath[folderPath.endIndex] == "/")
    }

    private var displayName: String {
        if isRoot { return folder.lastPathComponent.isEmpty ? folder.path : folder.lastPathComponent }
        return viewModel.relativePath(of: folder, relativeTo: parentSource)
    }

    private var photoCount: Int { viewModel.recursivePhotoCount(in: folder) }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            row
            if isExpanded {
                // Render child subfolders.
                if let children = cachedChildren, !children.isEmpty {
                    ForEach(children, id: \.self) { child in
                        FolderTreeNode(
                            viewModel: viewModel,
                            folder: child,
                            parentSource: parentSource,
                            depth: depth + 1,
                            isRoot: false
                        )
                    }
                }
                // Render photo leaf nodes for photos directly in this folder.
                if let photos = cachedPhotos, !photos.isEmpty {
                    ForEach(photos, id: \.id) { photoSet in
                        PhotoLeafNode(
                            viewModel: viewModel,
                            photoSet: photoSet,
                            parentFolder: folder,
                            parentSource: parentSource,
                            depth: depth + 1
                        )
                    }
                }
            }
        }
    }

    private var row: some View {
        HStack(spacing: 0) {
            // Depth-based indent applied to the entire row so the
            // disclosure triangle and folder content move together.
            Spacer().frame(width: CGFloat(depth) * Theme.Space.s12)

            // Clickable disclosure triangle on the left of the row.
            // Clicking it expands/collapses the subtree without applying
            // the filter, so the user can browse without losing their
            // current grid view.
            Button(action: toggleExpansion) {
                HStack(spacing: 2) {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(Theme.Color.textTertiary)
                        .rotationEffect(.degrees(isExpanded ? 90 : 0))
                        .opacity(canExpand ? 1 : 0)
                        .animation(.easeInOut(duration: 0.12), value: isExpanded)
                }
                .frame(width: 18, height: 22)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help(canExpand
                  ? (isExpanded ? "Collapse" : "Expand")
                  : "Empty folder")

            // Main row click → filter the grid to this subtree.
            Button(action: toggleSelection) {
                HStack(spacing: Theme.Space.s6) {
                    Image(systemName: hasFailed ? "exclamationmark.triangle.fill"
                                               : (isRoot ? "folder.fill" : "folder"))
                        .foregroundStyle(hasFailed ? Theme.Color.danger
                                                  : (isSubtreeSelected ? Theme.Color.accent
                                                                       : Theme.Color.textSecondary))
                        .font(.system(size: isRoot ? 14 : 12))
                        .frame(width: 16)

                    Text(displayName)
                        .font(isRoot ? Theme.Font.subheadline : Theme.Font.caption)
                        .foregroundStyle(hasFailed ? Theme.Color.danger
                                                  : Theme.Color.textPrimary)
                        .lineLimit(1)
                        .truncationMode(.middle)

                    if hasFailed {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.system(size: 11))
                            .foregroundStyle(Theme.Color.danger)
                            .help("Failed to read this source")
                    }

                    Spacer(minLength: 4)

                    if photoCount > 0 {
                        Text("\(photoCount)")
                            .font(.system(size: 11, weight: .semibold, design: .rounded))
                            .foregroundStyle(isSubtreeSelected ? Theme.Color.accent
                                                              : Theme.Color.textSecondary)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(
                                Capsule().fill(
                                    isSubtreeSelected
                                    ? Theme.Color.accent.opacity(0.18)
                                    : Theme.Color.overlaySoft
                                )
                            )
                    }

                    if isHovered {
                        HStack(spacing: Theme.Space.s6) {
                            Button {
                                NSWorkspace.shared.activateFileViewerSelecting([folder])
                            } label: {
                                Image(systemName: "magnifyingglass")
                                    .font(Theme.Font.caption)
                                    .foregroundStyle(Theme.Color.textSecondary)
                            }
                            .buttonStyle(.plain)
                            .help("Reveal in Finder")

                            if isRoot {
                                Button {
                                    viewModel.removeSourceDirectory(folder)
                                } label: {
                                    Image(systemName: "xmark.circle")
                                        .font(Theme.Font.caption)
                                        .foregroundStyle(Theme.Color.textSecondary)
                                }
                                .buttonStyle(.plain)
                                .help("Remove source folder")
                            }
                        }
                    }
                }
                .padding(.leading, Theme.Space.s4)
                .padding(.trailing, Theme.Space.s10)
                .padding(.vertical, Theme.Space.s4)
                .contentShape(Rectangle())
                .background(
                    // Highlight the entire subtree when the user is
                    // filtering by it.
                    RoundedRectangle(cornerRadius: Theme.Radius.m)
                        .fill(isSubtreeSelected
                              ? Theme.Color.rowSelectedFill
                              : (isHovered ? Theme.Color.rowHoverFill : Color.clear))
                        .padding(.horizontal, Theme.Space.s4)
                )
            }
            .buttonStyle(.plain)
        }
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.12)) { isHovered = hovering }
        }
        .contextMenu {
            Button(isSubtreeSelected ? "Clear Filter" : "Filter to This Folder") {
                toggleSelection()
            }
            Divider()
            Button("Reveal in Finder") {
                NSWorkspace.shared.activateFileViewerSelecting([folder])
            }
            if canExpand {
                Button(isExpanded ? "Collapse" : "Expand") {
                    toggleExpansion()
                }
                Divider()
            }
            if isRoot {
                Button("Remove Source Folder") {
                    viewModel.removeSourceDirectory(folder)
                }
            }
        }
    }

    /// True if this folder contains any photo sets directly (not in
    /// subfolders). Used to show the disclosure triangle when a folder
    /// has photos at the leaf level.
    private var hasDirectPhotos: Bool {
        if let cached = cachedPhotos {
            return !cached.isEmpty
        }
        return viewModel.hasPhotosDirectly(in: folder)
    }

    private var canExpand: Bool {
        if let cached = cachedChildren { return !cached.isEmpty }
        // We haven't computed children yet — assume yes if there's at
        // least one photo in the subtree (any deeper folder must be
        // photo-bearing to exist), or if this folder directly contains
        // photos that can be shown as leaf nodes.
        return photoCount > 0 || hasDirectPhotos
    }

    /// True when this folder has at least one direct photo (leaf node).
    private var hasLeafPhotos: Bool {
        if let cached = cachedPhotos {
            return !cached.isEmpty
        }
        return hasDirectPhotos
    }

    private func toggleSelection() {
        if isSubtreeSelected {
            viewModel.selectedSubfolderFilter = nil
        } else {
            viewModel.selectedSubfolderFilter = folder
        }
    }

    private func toggleExpansion() {
        guard canExpand else { return }
        if cachedChildren == nil {
            cachedChildren = viewModel.childSubfolders(of: folder)
        }
        // Also load direct photo sets when expanding.
        if cachedPhotos == nil {
            cachedPhotos = viewModel.photoSetsDirectlyIn(folder: folder)
        }
        withAnimation(.easeInOut(duration: 0.12)) {
            isExpanded.toggle()
        }
    }
}

// MARK: - Photo Leaf Node

/// A leaf node rendered inside an expanded `FolderTreeNode`. Shows
/// individual photo sets that live directly in this folder (not in
/// subfolders). Clicking filters the grid to that single photo.
struct PhotoLeafNode: View {
    @ObservedObject var viewModel: PhotoLibraryViewModel
    let photoSet: PhotoSet
    let parentFolder: URL
    let parentSource: URL
    let depth: Int

    private var isSelected: Bool {
        guard let active = viewModel.selectedSubfolderFilter else { return false }
        let activePath = active.standardizedFileURL.path
        let folderPath = parentFolder.standardizedFileURL.path
        return activePath == folderPath
            || (activePath.count > folderPath.count
                && activePath.hasPrefix(folderPath)
                && activePath[folderPath.endIndex] == "/")
    }

    var body: some View {
        HStack(spacing: 0) {
            Spacer().frame(width: CGFloat(depth) * Theme.Space.s12)
            // Camera icon with format badge.
            Image(systemName: "camera.fill")
                .font(.system(size: 11, weight: .light))
                .foregroundStyle(
                    colorForFormat(photoSet.formatLabel)
                        .opacity(0.7)
                )
                .frame(width: 18, height: 22)
                .contentShape(Rectangle())

            // Photo name (base name of the first file).
            Button(action: selectPhoto) {
                Text(photoSet.displayName)
                    .font(Theme.Font.body)
                    .foregroundStyle(isSelected ? Theme.Color.accent : Theme.Color.textSecondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            .buttonStyle(.plain)
            .help("Filter grid to: \(photoSet.displayName)")

            Spacer()

            // Format badge (RAW, JPEG, HEIF).
            if !photoSet.formatLabel.isEmpty {
                Text(photoSet.formatLabel)
                    .font(Theme.Font.caption2)
                    .foregroundStyle(
                        colorForFormat(photoSet.formatLabel)
                            .opacity(0.85)
                    )
                    .padding(.horizontal, 4)
                    .padding(.vertical, 1)
                    .background(Theme.Color.overlaySoft)
                    .clipShape(RoundedRectangle(cornerRadius: 2))
            }

            // Photo count (if the set has multiple files).
            if photoSet.mediaFiles.count > 1 {
                Text("×\(photoSet.mediaFiles.count)")
                    .font(Theme.Font.caption2)
                    .foregroundStyle(Theme.Color.textTertiary)
                    .padding(.trailing, Theme.Space.s4)
            }
        }
        .frame(height: 22)
        .padding(.leading, Theme.Space.s4)
    }

    private func selectPhoto() {
        viewModel.selectedSubfolderFilter = parentFolder
        // Set the focused photo index so the main view shows this photo.
        if let idx = viewModel.filteredPhotoSets.firstIndex(where: { $0.id == photoSet.id }) {
            viewModel.focusedPhotoIndex = idx
        }
    }

    /// Returns the Theme.FileColor matching the format label.
    private func colorForFormat(_ label: String) -> Color {
        let upper = label.uppercased()
        if upper.contains("JPEG") { return Theme.Color.FileColor.jpeg }
        if upper.contains("HEIF") { return Theme.Color.FileColor.heif }
        if upper.contains("RAW")  { return Theme.Color.FileColor.raw }
        return Theme.Color.FileColor.other
    }
}

// MARK: - Active Filters Bar

struct ActiveFiltersBar: View {
    let count: Int
    let isEmpty: Bool
    let onClear: () -> Void
    @State private var isHovered = false

    var body: some View {
        HStack(spacing: Theme.Space.s6) {
            Image(systemName: isEmpty
                  ? "line.3.horizontal.decrease.circle"
                  : "line.3.horizontal.decrease.circle.fill")
                .foregroundStyle(isEmpty ? Theme.Color.textTertiary : Theme.Color.accent)
                .font(Theme.Font.subheadline)

            Text(isEmpty
                 ? "No active filters"
                 : "^[\(count) active filter](inflect: true)")
                .font(Theme.Font.caption)
                .foregroundStyle(isEmpty ? Theme.Color.textTertiary : Theme.Color.textPrimary)
                .lineLimit(1)

            Spacer(minLength: Theme.Space.s4)

            Button(action: onClear) {
                Text("Clear")
                    .font(Theme.Font.caption)
                    .foregroundStyle(isEmpty ? Theme.Color.textTertiary : Theme.Color.accent)
                    .padding(.horizontal, Theme.Space.s8)
                    .padding(.vertical, Theme.Space.s2)
                    .background(
                        isHovered && !isEmpty
                            ? Theme.Color.rowSelectedFill
                            : Color.clear,
                        in: RoundedRectangle(cornerRadius: Theme.Radius.s)
                    )
            }
            .buttonStyle(.plain)
            .disabled(isEmpty)
            .help(isEmpty
                  ? "Pick a tag, rating, or flag in the list below to filter the grid."
                  : "Clear all filters and search")
        }
        .padding(.horizontal, Theme.Space.s8)
        .padding(.vertical, Theme.Space.s4)
        .background(
            isEmpty
                ? Theme.Color.surfaceRaised.opacity(0.4)
                : Theme.Color.rowSelectedFill,
            in: RoundedRectangle(cornerRadius: Theme.Radius.m)
        )
        .overlay(
            RoundedRectangle(cornerRadius: Theme.Radius.m)
                .stroke(
                    isEmpty
                        ? Theme.Color.surfaceDivider
                        : Theme.Color.accent.opacity(0.3),
                    lineWidth: Theme.Stroke.hairline
                )
        )
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.12)) { isHovered = hovering }
        }
    }
}
