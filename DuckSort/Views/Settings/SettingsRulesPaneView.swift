//
//  SettingsRulesPaneView.swift
//  DuckSort
//
//  The "Rules" tab of the unified Settings window.
//  Overhauled to match the premium dark macOS design system.
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
        VStack(spacing: Theme.Space.s4) {
            HStack {
                Text("EXPORT RULE SETS")
                    .font(Theme.Font.caption2)
                    .tracking(0.5)
                    .foregroundStyle(Theme.Color.textTertiary)
                Spacer()
            }
            .padding(.horizontal, Theme.Space.s12)
            .padding(.top, Theme.Space.s12)
            .padding(.bottom, Theme.Space.s6)

            ScrollView {
                LazyVStack(spacing: Theme.Space.s4) {
                    ForEach(ruleStore.rules) { rule in
                        RuleSidebarRow(
                            rule: rule,
                            isSelected: ruleStore.selectedRuleID == rule.id,
                            tagStore: tagStore,
                            onSelect: {
                                withAnimation(.smooth(duration: 0.15)) {
                                    ruleStore.selectRule(id: rule.id)
                                }
                            },
                            onDelete: { ruleStore.deleteRule(id: rule.id) }
                        )
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            Rectangle()
                .fill(Theme.Color.separator)
                .frame(height: Theme.Stroke.hairline)
                .padding(.horizontal, Theme.Space.s12)

            HStack(spacing: Theme.Space.s8) {
                TextField("New rule set", text: $newRuleName)
                    .textFieldStyle(.plain)
                    .font(Theme.Font.subheadline)
                    .foregroundStyle(Theme.Color.textPrimary)
                    .focused($isAddFieldFocused)
                    .onSubmit(commitNewRule)

                Button(action: commitNewRule) {
                    Image(systemName: "plus.circle.fill")
                        .font(.system(size: 16))
                        .foregroundStyle(
                            newRuleName.trimmingCharacters(in: .whitespaces).isEmpty
                                ? Theme.Color.textTertiary
                                : Theme.Color.accent
                        )
                }
                .buttonStyle(.plain)
                .disabled(newRuleName.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            .padding(.horizontal, Theme.Space.s12)
            .padding(.vertical, Theme.Space.s10)
            .background(
                RoundedRectangle(cornerRadius: Theme.Radius.m)
                    .fill(Theme.Color.cellBackground)
            )
            .overlay(
                RoundedRectangle(cornerRadius: Theme.Radius.m)
                    .stroke(Theme.Color.separator, lineWidth: Theme.Stroke.hairline)
            )
            .padding(.horizontal, Theme.Space.s8)
            .padding(.bottom, Theme.Space.s8)
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
            HStack(spacing: Theme.Space.s10) {
                Image(systemName: "folder.fill")
                    .font(.system(size: 12))
                    .foregroundStyle(isSelected ? .white : Theme.Color.accent)
                    .frame(width: 16)

                VStack(alignment: .leading, spacing: 2) {
                    Text(rule.name)
                        .font(isSelected ? Theme.Font.bodyBold : Theme.Font.body)
                        .foregroundStyle(isSelected ? Theme.Color.textInverse : Theme.Color.textPrimary)
                        .lineLimit(1)
                    if !rule.components.isEmpty {
                        Text(ExportPathRouter.describe(rule.components) {
                            tagStore.categoryName(id: $0)
                        })
                        .font(Theme.Font.badge)
                        .foregroundStyle(isSelected ? Theme.Color.textInverse.opacity(0.75) : Theme.Color.textSecondary)
                        .lineLimit(1)
                    }
                }

                Spacer()
            }
            .padding(.horizontal, Theme.Space.s10)
            .padding(.vertical, Theme.Space.s8)
            .background(
                RoundedRectangle(cornerRadius: Theme.Radius.m)
                    .fill(isSelected ? Theme.Color.accent : (isHovered ? Theme.Color.overlaySofter : Color.clear))
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.horizontal, Theme.Space.s8)
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.12)) { isHovered = hovering }
        }
        .contextMenu {
            Button("Delete Rule Set", role: .destructive, action: onDelete)
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
            VStack(spacing: Theme.Space.s12) {
                Spacer()
                Image(systemName: "folder.badge.gearshape")
                    .font(.system(size: 44))
                    .foregroundStyle(Theme.Color.textTertiary)
                Text("Select an Export Rule Set")
                    .font(Theme.Font.headline)
                    .foregroundStyle(Theme.Color.textSecondary)
                Text("Choose a rule set from the left sidebar to configure its directory layout rules.")
                    .font(Theme.Font.caption)
                    .foregroundStyle(Theme.Color.textTertiary)
                Spacer()
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Theme.Color.surfaceBase)
        }
    }
}

private struct RuleEditorDetail: View {
    let rule: ExportPathRule
    @ObservedObject var ruleStore: ExportRuleStore
    @ObservedObject var tagStore: TagStore

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Space.s16) {
                // Title Header
                VStack(alignment: .leading, spacing: Theme.Space.s4) {
                    Text("Export Directory Rules")
                        .font(Theme.Font.title)
                        .foregroundStyle(Theme.Color.textPrimary)
                    Text("Configure automated subfolder structures generated when exporting media.")
                        .font(Theme.Font.body)
                        .foregroundStyle(Theme.Color.textSecondary)
                }
                .padding(.bottom, Theme.Space.s4)

                // Rule Configuration Card
                VStack(alignment: .leading, spacing: Theme.Space.s12) {
                    HStack(spacing: Theme.Space.s12) {
                        Text("Rule Name")
                            .font(Theme.Font.bodyBold)
                            .foregroundStyle(Theme.Color.textPrimary)
                            .frame(width: 90, alignment: .leading)

                        TextField("Rule set name", text: Binding(
                            get: { rule.name },
                            set: { newName in
                                var updated = rule
                                updated.name = newName
                                ruleStore.updateRule(updated)
                            }
                        ))
                        .textFieldStyle(.roundedBorder)
                        .font(Theme.Font.body)

                        Spacer()

                        Text("\(rule.components.count) folder level\(rule.components.count == 1 ? "" : "s")")
                            .font(Theme.Font.caption)
                            .foregroundStyle(Theme.Color.textSecondary)
                            .padding(.horizontal, Theme.Space.s8)
                            .padding(.vertical, Theme.Space.s4)
                            .background(Theme.Color.surfaceRaised, in: RoundedRectangle(cornerRadius: Theme.Radius.s))
                    }

                    Rectangle()
                        .fill(Theme.Color.separator)
                        .frame(height: Theme.Stroke.hairline)

                    // Components list header
                    HStack {
                        Text("SUBFOLDER HIERARCHY")
                            .font(Theme.Font.caption2)
                            .tracking(0.5)
                            .foregroundStyle(Theme.Color.textTertiary)

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
                            Label("Add Folder Level", systemImage: "plus")
                                .font(Theme.Font.subheadline)
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)
                    }

                    if rule.components.isEmpty {
                        VStack(spacing: Theme.Space.s8) {
                            Image(systemName: "square.dashed")
                                .font(.system(size: 28))
                                .foregroundStyle(Theme.Color.textTertiary)
                            Text("No Subfolder Levels Defined")
                                .font(Theme.Font.subheadline)
                                .foregroundStyle(Theme.Color.textSecondary)
                            Text("Click '+ Add Folder Level' to build a custom export path.")
                                .font(Theme.Font.caption)
                                .foregroundStyle(Theme.Color.textTertiary)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, Theme.Space.s24)
                        .background(
                            RoundedRectangle(cornerRadius: Theme.Radius.m)
                                .fill(Theme.Color.surfaceBase)
                        )
                    } else {
                        VStack(spacing: Theme.Space.s8) {
                            ForEach(Array(rule.components.enumerated()), id: \.offset) { index, component in
                                RuleComponentRow(
                                    component: component,
                                    index: index,
                                    rule: rule,
                                    ruleStore: ruleStore,
                                    tagStore: tagStore
                                )
                            }
                        }
                    }
                }
                .padding(Theme.Space.s16)
                .background(
                    RoundedRectangle(cornerRadius: Theme.Radius.l)
                        .fill(Theme.Color.cellBackground)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: Theme.Radius.l)
                        .stroke(Theme.Color.separator, lineWidth: Theme.Stroke.hairline)
                )
            }
            .padding(Theme.Space.s20)
        }
        .background(Theme.Color.surfaceBase)
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
        HStack(spacing: Theme.Space.s10) {
            Image(systemName: "line.3.horizontal")
                .font(.system(size: 12))
                .foregroundStyle(Theme.Color.textTertiary)

            Text("Level \(index + 1)")
                .font(Theme.Font.caption)
                .fontWeight(.bold)
                .foregroundStyle(Theme.Color.accent)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(Theme.Color.accent.opacity(0.15), in: RoundedRectangle(cornerRadius: Theme.Radius.s))

            HStack(spacing: Theme.Space.s8) {
                Image(systemName: component.systemImage)
                    .font(Theme.Font.body)
                    .foregroundStyle(Theme.Color.textSecondary)
                    .frame(width: 18)

                componentContent
            }

            Spacer()

            Button(action: removeComponent) {
                Image(systemName: "trash")
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.Color.danger)
            }
            .buttonStyle(.plain)
            .opacity(isHovered ? 1.0 : 0.4)
        }
        .padding(.horizontal, Theme.Space.s12)
        .padding(.vertical, Theme.Space.s10)
        .background(
            RoundedRectangle(cornerRadius: Theme.Radius.m)
                .fill(Theme.Color.surfaceBase)
        )
        .overlay(
            RoundedRectangle(cornerRadius: Theme.Radius.m)
                .stroke(Theme.Color.surfaceDivider, lineWidth: Theme.Stroke.hairline)
        )
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.12)) { isHovered = hovering }
        }
    }

    @ViewBuilder
    private var componentContent: some View {
        switch component {
        case .cameraModel, .lensModel, .captureDate:
            Text(component.displayName)
                .font(Theme.Font.bodyBold)
                .foregroundStyle(Theme.Color.textPrimary)

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
            .pickerStyle(.menu)
            .labelsHidden()
            .font(Theme.Font.body)
            .frame(maxWidth: 180, alignment: .leading)

        case .customText(let text):
            TextField("Custom text", text: Binding(
                get: { text },
                set: { newText in
                    var updated = rule
                    updated.components[index] = .customText(newText)
                    ruleStore.updateRule(updated)
                }
            ))
            .textFieldStyle(.roundedBorder)
            .font(Theme.Font.body)
            .frame(maxWidth: 180)
        }
    }

    private func removeComponent() {
        var updated = rule
        updated.components.remove(at: index)
        ruleStore.updateRule(updated)
    }
}
