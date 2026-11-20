//
//  SettingsRulesPaneView.swift
//  DuckSort
//
//  Native macOS Rules settings pane with sidebar List and grouped Form.
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

    var body: some View {
        VStack(spacing: 0) {
            List(selection: Binding(
                get: { ruleStore.selectedRuleID },
                set: { newID in
                    if let newID, newID != ruleStore.selectedRuleID {
                        Task { @MainActor in
                            ruleStore.selectRule(id: newID)
                        }
                    }
                }
            )) {
                Section("Export Rule Sets") {
                    ForEach(ruleStore.rules) { rule in
                        VStack(alignment: .leading, spacing: 2) {
                            Label(rule.name, systemImage: "folder")
                                .lineLimit(1)
                            if !rule.components.isEmpty {
                                Text(ExportPathRouter.describe(rule.components) {
                                    tagStore.categoryName(id: $0)
                                })
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                            }
                        }
                        .tag(rule.id)
                        .contextMenu {
                            Button("Delete Rule Set", role: .destructive) {
                                ruleStore.deleteRule(id: rule.id)
                            }
                            .disabled(ruleStore.rules.count <= 1)
                        }
                    }
                }
            }
            .listStyle(.sidebar)

            Divider()

            HStack(spacing: 4) {
                Button {
                    let nextNumber = ruleStore.rules.count + 1
                    ruleStore.addRule(name: "Rule Set \(nextNumber)")
                } label: {
                    Image(systemName: "plus")
                        .frame(width: 24, height: 22)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.borderless)
                .help("Add Rule Set")

                Button {
                    if let selectedID = ruleStore.selectedRuleID {
                        ruleStore.deleteRule(id: selectedID)
                    }
                } label: {
                    Image(systemName: "minus")
                        .frame(width: 24, height: 22)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.borderless)
                .disabled(ruleStore.selectedRuleID == nil || ruleStore.rules.count <= 1)
                .help("Remove Selected Rule Set")

                Spacer()
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Color(nsColor: .underPageBackgroundColor))
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
            ContentUnavailableView(
                "Select an Export Rule Set",
                systemImage: "folder.badge.gearshape",
                description: Text("Choose a rule set from the sidebar to configure its export folder hierarchy.")
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

private struct RuleEditorDetail: View {
    let rule: ExportPathRule
    @ObservedObject var ruleStore: ExportRuleStore
    @ObservedObject var tagStore: TagStore

    var body: some View {
        Form {
            Section {
                TextField("Rule Name", text: Binding(
                    get: { rule.name },
                    set: { newName in
                        var updated = rule
                        updated.name = newName
                        ruleStore.updateRule(updated)
                    }
                ))

                LabeledContent("Path Preview") {
                    Text(
                        rule.components.isEmpty
                            ? "Destination Root (Flat)"
                            : ExportPathRouter.describe(rule.components) { tagStore.categoryName(id: $0) }
                    )
                    .font(.system(.subheadline, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                }
            } header: {
                Text("Rule Set")
            } footer: {
                Text("Configure automated subfolder structures created inside your destination folder when copying or moving photos.")
            }

            Section {
                if rule.components.isEmpty {
                    Text("No subfolder levels defined. Exported files will be placed directly in the destination folder.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .padding(.vertical, 4)
                } else {
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

                HStack {
                    Menu {
                        Button("Camera Model") { addComponent(.cameraModel, to: rule) }
                        Button("Lens Model")   { addComponent(.lensModel, to: rule) }
                        Button("Capture Date") { addComponent(.captureDate, to: rule) }
                        Divider()
                        ForEach(tagStore.categories) { category in
                            Button("Tag Category: \(category.name)") {
                                addComponent(.tagCategory(category.id), to: rule)
                            }
                        }
                        Divider()
                        Button("Custom Folder Name…") { addComponent(.customText("Custom"), to: rule) }
                    } label: {
                        Label("Add Folder Level…", systemImage: "plus")
                    }
                    .controlSize(.small)

                    Spacer()
                }
            } header: {
                Text("Subfolder Hierarchy")
            }
        }
        .formStyle(.grouped)
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

    var body: some View {
        LabeledContent {
            HStack(spacing: 8) {
                componentContent

                Button(role: .destructive, action: removeComponent) {
                    Image(systemName: "minus.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.borderless)
                .help("Remove folder level")
            }
        } label: {
            HStack(spacing: 8) {
                Text("Level \(index + 1)")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 52, alignment: .leading)

                Image(systemName: component.systemImage)
                    .foregroundStyle(Theme.Color.accent)
                    .frame(width: 16)

                Text(componentLabel)
                    .font(.body)
            }
        }
    }

    private var componentLabel: String {
        switch component {
        case .tagCategory:
            return "Tag Category"
        case .customText:
            return "Custom Folder"
        default:
            return component.displayName
        }
    }

    @ViewBuilder
    private var componentContent: some View {
        switch component {
        case .cameraModel, .lensModel, .captureDate,
             .year, .month, .day, .camera, .lens, .iso, .aperture, .shutterSpeed, .ratingStars, .flagStatus, .primaryTag:
            Text("Metadata token")
                .font(.caption)
                .foregroundStyle(.secondary)

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
            .frame(width: 170)

        case .customText(let text):
            TextField("Folder name", text: Binding(
                get: { text },
                set: { newText in
                    var updated = rule
                    updated.components[index] = .customText(newText)
                    ruleStore.updateRule(updated)
                }
            ))
            .textFieldStyle(.roundedBorder)
            .frame(width: 170)
        }
    }

    private func removeComponent() {
        var updated = rule
        updated.components.remove(at: index)
        ruleStore.updateRule(updated)
    }
}
