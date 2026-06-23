//
//  SettingsRulesPaneView.swift
//  DuckSort
//
//  The "Rules" tab of the unified Settings window.
//  Fixed 200px sidebar (rule set list) + right detail panel (rule editor).
//  Matches the macOS Safari preferences aesthetic described in the spec.
//

import SwiftUI

struct SettingsRulesPaneView: View {
    @ObservedObject var ruleStore: ExportRuleStore
    @ObservedObject var tagStore: TagStore

    var body: some View {
        SettingsSplitLayout {
            RulesSidebar(ruleStore: ruleStore, tagStore: tagStore)
        } detail: {
            RulesDetailPanel(ruleStore: ruleStore, tagStore: tagStore)
        }
    }
}

// MARK: - Left Sidebar

private struct RulesSidebar: View {
    @ObservedObject var ruleStore: ExportRuleStore
    @ObservedObject var tagStore: TagStore
    @State private var newRuleName: String = ""
    @FocusState private var isAddFieldFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            // Section header
            HStack {
                Text("MY RULE SETS")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(dsColor( "#8A8A8E"))
                    .tracking(0.3)
                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.top, 10)
            .padding(.bottom, 6)

            // Rule list
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(ruleStore.rules) { rule in
                        RuleSidebarRow(
                            rule: rule,
                            isSelected: ruleStore.selectedRuleID == rule.id,
                            tagStore: tagStore,
                            onSelect: { ruleStore.selectRule(id: rule.id) },
                            onDelete: { ruleStore.deleteRule(id: rule.id) }
                        )
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            // Divider + add field
            Rectangle()
                .fill(dsColor("#323232"))
                .frame(height: 1)
                .padding(.horizontal, 16)

            HStack(spacing: 4) {
                TextField("New rule set", text: $newRuleName)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12))
                    .foregroundStyle(.white)
                    .focused($isAddFieldFocused)
                    .onSubmit(commitNewRule)

                Button(action: commitNewRule) {
                    Image(systemName: "plus")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(
                            newRuleName.trimmingCharacters(in: .whitespaces).isEmpty
                                ? dsColor("#3C3C3E")
                                : dsColor("#8A8A8E")
                        )
                }
                .buttonStyle(.plain)
                .disabled(newRuleName.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
        }
    }

    private func commitNewRule() {
        let trimmed = newRuleName.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        ruleStore.addRule(name: trimmed)
        newRuleName = ""
        isAddFieldFocused = false
    }
}

private struct RuleSidebarRow: View {
    let rule: ExportPathRule
    let isSelected: Bool
    let tagStore: TagStore
    let onSelect: () -> Void
    let onDelete: () -> Void
    @State private var isHovered = false

    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: 8) {
                Image(systemName: "circle")
                    .font(.system(size: 11))
                    .foregroundStyle(isSelected ? .white : dsColor( "#8A8A8E"))
                    .frame(width: 14)

                VStack(alignment: .leading, spacing: 1) {
                    Text(rule.name)
                        .font(.system(size: 13, weight: isSelected ? .semibold : .regular))
                        .foregroundStyle(isSelected ? .white : dsColor( "#AEAEB2"))
                        .lineLimit(1)
                    if !rule.components.isEmpty {
                        Text(ExportPathRouter.describe(rule.components) {
                            tagStore.categoryName(id: $0)
                        })
                        .font(.system(size: 10))
                        .foregroundStyle(isSelected ? Color.white.opacity(0.65) : dsColor( "#636366"))
                        .lineLimit(1)
                    }
                }

                Spacer()
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
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
            Button("Delete", role: .destructive, action: onDelete)
        }
    }
}

// MARK: - Right Detail Panel

private struct RulesDetailPanel: View {
    @ObservedObject var ruleStore: ExportRuleStore
    @ObservedObject var tagStore: TagStore

    var body: some View {
        if let rule = ruleStore.selectedRule {
            RuleEditorDetail(rule: rule, ruleStore: ruleStore, tagStore: tagStore)
        } else {
            VStack {
                Spacer()
                Image(systemName: "arrow.triangle.branch")
                    .font(.system(size: 28, weight: .light))
                    .foregroundStyle(dsColor( "#3C3C3E"))
                Text("Select a rule set to edit")
                    .font(.system(size: 13))
                    .foregroundStyle(dsColor( "#636366"))
                    .padding(.top, 6)
                Spacer()
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

private struct RuleEditorDetail: View {
    let rule: ExportPathRule
    @ObservedObject var ruleStore: ExportRuleStore
    @ObservedObject var tagStore: TagStore

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Rule Name field
            HStack(spacing: 12) {
                Text("Rule Name:")
                    .font(.system(size: 13))
                    .foregroundStyle(dsColor( "#8A8A8E"))
                    .frame(width: 80, alignment: .trailing)

                TextField("Rule name", text: Binding(
                    get: { rule.name },
                    set: { newName in
                        var updated = rule
                        updated.name = newName
                        ruleStore.updateRule(updated)
                    }
                ))
                .textFieldStyle(.plain)
                .font(.system(size: 13))
                .foregroundStyle(.white)
                .padding(.horizontal, 8)
                .padding(.vertical, 5)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(Color.white.opacity(0.06))
                        .overlay(
                            RoundedRectangle(cornerRadius: 6)
                                .stroke(dsColor( "#3C3C3E"), lineWidth: 1)
                        )
                )

                Spacer()

                Text("\(rule.components.count) folder level\(rule.components.count == 1 ? "" : "s")")
                    .font(.system(size: 11))
                    .foregroundStyle(dsColor( "#636366"))
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)

            Rectangle()
                .fill(dsColor( "#2C2C2E"))
                .frame(height: 1)
                .padding(.horizontal, 16)

            // Component rows
            if rule.components.isEmpty {
                VStack {
                    Spacer()
                    Text("No folder levels yet. Add one below.")
                        .font(.system(size: 12))
                        .foregroundStyle(dsColor( "#636366"))
                    Spacer()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List {
                    ForEach(Array(rule.components.enumerated()), id: \.offset) { index, component in
                        RuleComponentRow(
                            component: component,
                            index: index,
                            rule: rule,
                            ruleStore: ruleStore,
                            tagStore: tagStore
                        )
                        .listRowBackground(Color.clear)
                        .listRowSeparatorTint(dsColor( "#2C2C2E"))
                        .listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 0))
                    }
                    .onMove { from, to in
                        var updated = rule
                        updated.components.move(fromOffsets: from, toOffset: to)
                        ruleStore.updateRule(updated)
                    }
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
                .background(Color.clear)
            }

            Rectangle()
                .fill(dsColor( "#2C2C2E"))
                .frame(height: 1)
                .padding(.horizontal, 16)

            // "Add Folder Level" menu
            HStack {
                Spacer()

                Menu {
                    Button("Camera Model") { addComponent(.cameraModel, to: rule) }
                    Button("Lens Model")   { addComponent(.lensModel, to: rule) }
                    Button("Capture Date") { addComponent(.captureDate, to: rule) }
                    Divider()
                    ForEach(tagStore.categories) { category in
                        Button(category.name) {
                            addComponent(.tagCategory(category.id), to: rule)
                        }
                    }
                    Divider()
                    Button("Custom Text…") { addComponent(.customText("Custom"), to: rule) }
                } label: {
                    HStack(spacing: 5) {
                        Text("Add Folder Level")
                            .font(.system(size: 12))
                        Image(systemName: "plus")
                            .font(.system(size: 11))
                    }
                    .foregroundStyle(dsColor("#0A84FF"))
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .fixedSize()
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
        }
    }

    private func addComponent(_ component: ExportPathComponent, to rule: ExportPathRule) {
        var updated = rule
        updated.components.append(component)
        ruleStore.updateRule(updated)
    }
}

private struct RuleComponentRow: View {
    let component: ExportPathComponent
    let index: Int
    let rule: ExportPathRule
    @ObservedObject var ruleStore: ExportRuleStore
    @ObservedObject var tagStore: TagStore
    @State private var isHovered = false

    var body: some View {
        HStack(spacing: 10) {
            // Drag handle
            Image(systemName: "line.3.horizontal")
                .font(.system(size: 11))
                .foregroundStyle(dsColor("#636366"))

            // Icon + label/picker/text, tightly grouped
            HStack(spacing: 8) {
                Image(systemName: component.systemImage)
                    .font(.system(size: 13))
                    .foregroundStyle(dsColor("#8A8A8E"))
                    .frame(width: 18)

                componentContent
            }

            Spacer()

            // Remove button — always visible when hovered
            if isHovered {
                Button(action: removeComponent) {
                    Image(systemName: "minus.circle")
                        .font(.system(size: 15))
                        .foregroundStyle(dsColor("#FF453A"))
                }
                .buttonStyle(.plain)
                .transition(.opacity.combined(with: .scale(scale: 0.8)))
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .contentShape(Rectangle())
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.12)) { isHovered = hovering }
        }
    }

    @ViewBuilder
    private var componentContent: some View {
        switch component {
        case .cameraModel, .lensModel, .captureDate:
            Text(component.displayName)
                .font(.system(size: 13))
                .foregroundStyle(.white)

        case .tagCategory(let id):
            Picker("", selection: Binding(
                get: {
                    tagStore.categories.contains(where: { $0.id == id })
                        ? id : (tagStore.categories.first?.id ?? id)
                },
                set: { newID in
                    var updated = rule
                    updated.components[index] = .tagCategory(newID)
                    ruleStore.updateRule(updated)
                }
            )) {
                ForEach(tagStore.categories) { cat in
                    Text(cat.name).tag(cat.id)
                }
            }
            .labelsHidden()
            .font(.system(size: 13))
            .frame(maxWidth: 160, alignment: .leading)

        case .customText(let text):
            TextField("Custom text", text: Binding(
                get: { text },
                set: { newText in
                    var updated = rule
                    updated.components[index] = .customText(newText)
                    ruleStore.updateRule(updated)
                }
            ))
            .textFieldStyle(.plain)
            .font(.system(size: 13))
            .foregroundStyle(.white)
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(
                RoundedRectangle(cornerRadius: 5)
                    .fill(Color.white.opacity(0.06))
                    .overlay(RoundedRectangle(cornerRadius: 5).stroke(dsColor( "#3C3C3E"), lineWidth: 1))
            )
            .frame(maxWidth: 160)
        }
    }

    private func removeComponent() {
        var updated = rule
        updated.components.remove(at: index)
        ruleStore.updateRule(updated)
    }
}
