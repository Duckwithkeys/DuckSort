//
//  SettingsTagsPaneView.swift
//  DuckSort
//
//  The "Tags" tab of the unified Settings window.
//  Fixed 200px sidebar (category list) + right panel with flat alternating
//  tag table (Tag Name | Hotkey | Color) plus inline add-row footer.
//

import SwiftUI
import UniformTypeIdentifiers

struct SettingsTagsPaneView: View {
    @ObservedObject var viewModel: PhotoLibraryViewModel
    @ObservedObject var tagStore: TagStore

    @State private var selectedCategoryID: UUID? = nil

    var body: some View {
        SettingsSplitLayout {
            TagsCategorySidebar(
                tagStore: tagStore,
                selectedCategoryID: $selectedCategoryID
            )
        } detail: {
            TagsDetailPanel(
                tagStore: tagStore,
                selectedCategoryID: $selectedCategoryID
            )
        }
        .onAppear {
            if selectedCategoryID == nil {
                selectedCategoryID = tagStore.categories.first?.id
            }
        }
        .onChange(of: tagStore.categories) { _, newCategories in
            if let id = selectedCategoryID, !newCategories.contains(where: { $0.id == id }) {
                selectedCategoryID = newCategories.first?.id
            }
        }
    }
}

// MARK: - Category Sidebar

private struct TagsCategorySidebar: View {
    @ObservedObject var tagStore: TagStore
    @Binding var selectedCategoryID: UUID?
    @State private var newCategoryName: String = ""
    @FocusState private var isAddFieldFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("CATEGORIES")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(dsColor( "#8A8A8E"))
                    .tracking(0.3)
                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.top, 10)
            .padding(.bottom, 6)

            // Category rows
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(tagStore.categories) { category in
                        CategorySidebarRow(
                            category: category,
                            tagCount: tagStore.tags(in: category.id).count,
                            isSelected: selectedCategoryID == category.id,
                            onSelect: { selectedCategoryID = category.id },
                            onDelete: { tagStore.deleteCategory(id: category.id) }
                        )
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            // Footer: add new category
            Rectangle()
                .fill(dsColor( "#323232"))
                .frame(height: 1)

            HStack(spacing: 4) {
                TextField("New category", text: $newCategoryName)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12))
                    .foregroundStyle(.white)
                    .focused($isAddFieldFocused)
                    .onSubmit(commitNewCategory)

                Button(action: commitNewCategory) {
                    Image(systemName: "plus")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(
                            newCategoryName.trimmingCharacters(in: .whitespaces).isEmpty
                                ? dsColor( "#3C3C3E")
                                : dsColor( "#8A8A8E")
                        )
                }
                .buttonStyle(.plain)
                .disabled(newCategoryName.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
        }
    }

    private func commitNewCategory() {
        let trimmed = newCategoryName.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        let newCat = tagStore.addCategory(name: trimmed)
        selectedCategoryID = newCat.id
        newCategoryName = ""
        isAddFieldFocused = false
    }
}

private struct CategorySidebarRow: View {
    let category: TagCategory
    let tagCount: Int
    let isSelected: Bool
    let onSelect: () -> Void
    let onDelete: () -> Void
    @State private var isHovered = false

    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: 8) {
                Image(systemName: "folder")
                    .font(.system(size: 11))
                    .foregroundStyle(isSelected ? .white : dsColor( "#8A8A8E"))
                    .frame(width: 14)

                Text(category.name)
                    .font(.system(size: 13, weight: isSelected ? .semibold : .regular))
                    .foregroundStyle(isSelected ? .white : dsColor( "#AEAEB2"))
                    .lineLimit(1)

                Spacer()

                if tagCount > 0 {
                    Text("\(tagCount)")
                        .font(.system(size: 11))
                        .foregroundStyle(isSelected ? Color.white.opacity(0.65) : dsColor( "#636366"))
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(
                isSelected
                    ? dsColor( "#0A84FF")
                    : (isHovered ? Color.white.opacity(0.05) : Color.clear)
            )
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.12)) { isHovered = hovering }
        }
        .contextMenu {
            Button("Delete Category", role: .destructive, action: onDelete)
        }
    }
}

// MARK: - Tags Detail Panel

private struct TagsDetailPanel: View {
    @ObservedObject var tagStore: TagStore
    @Binding var selectedCategoryID: UUID?

    private var selectedCategory: TagCategory? {
        guard let id = selectedCategoryID else { return nil }
        return tagStore.categories.first(where: { $0.id == id })
    }

    private var tagsInCategory: [CustomTag] {
        guard let id = selectedCategoryID else { return [] }
        return tagStore.tags(in: id)
    }

    var body: some View {
        if let category = selectedCategory {
            VStack(spacing: 0) {
                // Column headers
                HStack(spacing: 0) {
                    Text("Tag Name")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(dsColor( "#636366"))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.leading, 16)

                    Text("Hotkey")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(dsColor( "#636366"))
                        .frame(width: 110, alignment: .center)

                    Text("Color")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(dsColor( "#636366"))
                        .frame(width: 64, alignment: .center)
                        .padding(.trailing, 16)
                }
                .padding(.vertical, 8)
                .background(dsColor( "#1E1E1E"))

                Rectangle()
                    .fill(dsColor( "#2C2C2E"))
                    .frame(height: 1)

                // Tag rows
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(Array(tagsInCategory.enumerated()), id: \.element.id) { index, tag in
                            TagTableRow(
                                tag: tag,
                                rowIndex: index,
                                tagStore: tagStore
                            )
                        }

                        // Add row footer
                        AddTagRow(
                            onCommit: { name, colorHex in
                                commitNewTag(for: category, name: name, colorHex: colorHex)
                            }
                        )
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        } else {
            VStack {
                Spacer()
                Image(systemName: "tag")
                    .font(.system(size: 28, weight: .light))
                    .foregroundStyle(dsColor( "#3C3C3E"))
                Text("Select a category")
                    .font(.system(size: 13))
                    .foregroundStyle(dsColor( "#636366"))
                    .padding(.top, 6)
                Spacer()
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func commitNewTag(for category: TagCategory, name: String, colorHex: String) {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        tagStore.addTag(name: trimmed, categoryID: category.id, colorHex: colorHex)
    }
}

// MARK: - Tag Table Row

private struct TagTableRow: View {
    let tag: CustomTag
    let rowIndex: Int
    @ObservedObject var tagStore: TagStore
    @State private var isHovered = false

    var body: some View {
        HStack(spacing: 0) {
            // Tag name — inline editable
            TagNameField(tag: tag, tagStore: tagStore)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.leading, 16)

            // Hotkey recorder
            ShortcutRecorderView(hotkey: Binding(
                get: { tag.hotkey },
                set: { newValue in
                    var updated = tag
                    updated.hotkey = newValue
                    tagStore.updateTag(updated)
                }
            ))
            .frame(width: 110, alignment: .center)

            // Color capsule picker
            HStack {
                Spacer()
                ColorPicker("", selection: Binding(
                    get: { tag.color },
                    set: { newColor in
                        var updated = tag
                        updated.colorHex = newColor.toHex() ?? tag.colorHex
                        tagStore.updateTag(updated)
                    }
                ), supportsOpacity: false)
                .labelsHidden()
                .frame(width: 28, height: 20)
                Spacer()
            }
            .frame(width: 64)
            .padding(.trailing, isHovered ? 0 : 16)

            // Hover-reveal delete button
            if isHovered {
                Button(action: { tagStore.deleteTag(id: tag.id) }) {
                    Image(systemName: "minus.circle")
                        .font(.system(size: 15))
                        .foregroundStyle(dsColor( "#FF453A"))
                }
                .buttonStyle(.plain)
                .padding(.trailing, 16)
                .transition(.opacity.combined(with: .scale(scale: 0.8)))
            }
        }
        .frame(height: 36)
        .background(rowIndex % 2 == 1 ? Color.white.opacity(0.03) : Color.clear)
        .contentShape(Rectangle())
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.12)) { isHovered = hovering }
        }
    }
}

// MARK: - Inline-editable tag name

private struct TagNameField: View {
    let tag: CustomTag
    @ObservedObject var tagStore: TagStore
    @State private var isHovered = false
    @FocusState private var isFocused: Bool

    var body: some View {
        TextField("", text: Binding(
            get: { tag.name },
            set: { newName in
                var updated = tag
                updated.name = newName
                tagStore.updateTag(updated)
            }
        ))
        .textFieldStyle(.plain)
        .font(.system(size: 13))
        .foregroundStyle(.white)
        .padding(.horizontal, 6)
        .padding(.vertical, 3)
        .background(
            RoundedRectangle(cornerRadius: 5)
                .stroke(
                    isFocused || isHovered ? dsColor( "#0A84FF").opacity(0.6) : Color.clear,
                    lineWidth: 1
                )
        )
        .focused($isFocused)
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.1)) { isHovered = hovering }
        }
    }
}

// MARK: - Add Tag Row (footer)

private struct AddTagRow: View {
    let onCommit: (_ name: String, _ colorHex: String) -> Void
    @State private var name: String = ""
    @State private var color: Color = {
        let palette = [
            "#FF6B6B", "#FFA94D", "#FFD43B", "#4ECDC4",
            "#4D96FF", "#A78BFA", "#F472B6", "#6BCB77",
            "#38BDF8", "#FB923C", "#A7F3D0", "#C084FC"
        ]
        return dsColor( palette.randomElement() ?? "#4D96FF")
    }()
    @State private var isHovered = false
    @FocusState private var isFocused: Bool

    private var canSubmit: Bool {
        !name.trimmingCharacters(in: .whitespaces).isEmpty
    }

    private var colorHex: String {
        color.toHex() ?? "#4D96FF"
    }

    private let palette = [
        "#FF6B6B", // Coral Red
        "#FFA94D", // Pastel Orange
        "#FFD43B", // Yellow Gold
        "#4ECDC4", // Mint Teal
        "#4D96FF", // Royal Blue
        "#A78BFA", // Lavender Purple
        "#F472B6", // Warm Rose
        "#6BCB77", // Soft Green
        "#38BDF8", // Sky Blue
        "#FB923C", // Tangerine
        "#A7F3D0", // Emerald Green
        "#C084FC"  // Orchid Purple
    ]

    var body: some View {
        HStack(spacing: 0) {
            TextField("Add new tag…", text: $name)
                .textFieldStyle(.plain)
                .font(.system(size: 13))
                .foregroundStyle(canSubmit ? .white : dsColor( "#636366"))
                .onSubmit(submit)
                .focused($isFocused)
                .padding(.leading, 22)
                .frame(maxWidth: .infinity, alignment: .leading)

            if canSubmit {
                // Color swatch picker for the new tag
                ColorPicker("", selection: $color, supportsOpacity: false)
                    .labelsHidden()
                    .frame(width: 28, height: 20)
                    .padding(.trailing, 8)

                // Add button
                Button(action: submit) {
                    Image(systemName: "plus.circle.fill")
                        .font(.system(size: 18))
                        .foregroundStyle(dsColor( "#0A84FF"))
                }
                .buttonStyle(.plain)
                .padding(.trailing, 14)
            }
        }
        .frame(height: 36)
        .contentShape(Rectangle())
        .onTapGesture { isFocused = true }
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.1)) { isHovered = hovering }
        }
        .background(isHovered ? Color.white.opacity(0.02) : Color.clear)
    }

    private func submit() {
        guard canSubmit else { return }
        onCommit(name, colorHex)
        name = ""
        color = dsColor( palette.randomElement() ?? "#4D96FF")
    }
}
