//
//  LogConsoleView.swift
//  DuckSort
//
//  A high-performance log console view for developer monitoring.
//  Presents real-time logging output categorized by category and level.
//

import SwiftUI

struct LogConsoleView: View {
    @StateObject private var store = LogConsoleStore.shared
    @State private var filterText = ""
    @State private var selectedLevel: String = "All"
    @State private var selectedCategory: String = "All"

    private let levels = ["All", "debug", "info", "warning", "error", "fault"]
    private let categories = ["All", "thumbnails", "metadata", "transfer", "ui", "scanner", "vision"]

    var filteredEntries: [LogEntry] {
        store.entries.filter { entry in
            let matchesFilter = filterText.isEmpty || entry.message.localizedCaseInsensitiveContains(filterText)
            let matchesLevel = selectedLevel == "All" || entry.level == selectedLevel
            let matchesCategory = selectedCategory == "All" || entry.category == selectedCategory
            return matchesFilter && matchesLevel && matchesCategory
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            // Toolbar header
            HStack(spacing: Theme.Space.s12) {
                // Search bar
                HStack(spacing: Theme.Space.s6) {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(Theme.Color.textSecondary)
                    TextField("Filter logs...", text: $filterText)
                        .textFieldStyle(.plain)
                }
                .padding(.horizontal, Theme.Space.s8)
                .padding(.vertical, Theme.Space.s6)
                .background(Theme.Color.separator.opacity(0.3), in: RoundedRectangle(cornerRadius: Theme.Radius.m))
                .frame(maxWidth: 240)

                // Category Picker
                Picker("Category", selection: $selectedCategory) {
                    ForEach(categories, id: \.self) { cat in
                        Text(cat.capitalized).tag(cat)
                    }
                }
                .pickerStyle(.menu)
                .frame(width: 140)

                // Level Picker
                Picker("Level", selection: $selectedLevel) {
                    ForEach(levels, id: \.self) { lvl in
                        Text(lvl.capitalized).tag(lvl)
                    }
                }
                .pickerStyle(.menu)
                .frame(width: 110)

                Spacer()

                // Copy button
                Button {
                    copyToClipboard()
                } label: {
                    Label("Copy All", systemImage: "doc.on.doc")
                }
                .buttonStyle(.bordered)

                // Clear button
                Button(role: .destructive) {
                    store.clear()
                } label: {
                    Label("Clear", systemImage: "trash")
                }
                .buttonStyle(.bordered)
            }
            .padding(Theme.Space.s12)
            .background(.regularMaterial)

            Divider()

            // Logs output
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 4) {
                        ForEach(filteredEntries) { entry in
                            logRow(entry)
                                .id(entry.id)
                        }
                    }
                    .padding(Theme.Space.s12)
                }
                .background(Color(red: 0.1, green: 0.1, blue: 0.1))
                .onChange(of: filteredEntries.count) { _, _ in
                    if let last = filteredEntries.last {
                        withAnimation {
                            proxy.scrollTo(last.id, anchor: .bottom)
                        }
                    }
                }
            }
        }
        .frame(minWidth: 700, minHeight: 400)
    }

    private func logRow(_ entry: LogEntry) -> some View {
        HStack(alignment: .top, spacing: Theme.Space.s8) {
            // Timestamp
            Text(formatTime(entry.timestamp))
                .font(Theme.Font.monoBody)
                .foregroundStyle(Theme.Color.textSecondary)
                .frame(width: 90, alignment: .leading)

            // Category tag
            Text(entry.category.uppercased())
                .font(Theme.Font.caption)
                .fontDesign(.monospaced)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(categoryColor(entry.category).opacity(0.15), in: RoundedRectangle(cornerRadius: 4))
                .foregroundStyle(categoryColor(entry.category))
                .frame(width: 95, alignment: .leading)

            // Level indicator
            Text(entry.level.uppercased())
                .font(Theme.Font.caption)
                .fontDesign(.monospaced)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(levelColor(entry.level).opacity(0.15), in: RoundedRectangle(cornerRadius: 4))
                .foregroundStyle(levelColor(entry.level))
                .frame(width: 75, alignment: .leading)

            // Log Message
            Text(entry.message)
                .font(Theme.Font.monoBody)
                .foregroundStyle(levelColor(entry.level) == Theme.Color.textSecondary ? Theme.Color.textPrimary : levelColor(entry.level))
                .multilineTextAlignment(.leading)
        }
        .padding(.vertical, 2)
        .contextMenu {
            Button("Copy Message") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(entry.message, forType: .string)
            }
        }
    }

    private func formatTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss.SSS"
        return formatter.string(from: date)
    }

    private func categoryColor(_ category: String) -> Color {
        switch category {
        case "thumbnails": return .blue
        case "metadata": return .teal
        case "transfer": return .purple
        case "ui": return .orange
        case "scanner": return .green
        case "vision": return .indigo
        default: return .gray
        }
    }

    private func levelColor(_ level: String) -> Color {
        switch level {
        case "debug": return Theme.Color.textSecondary
        case "info": return .white
        case "warning": return .yellow
        case "error", "fault": return Theme.Color.danger
        default: return .white
        }
    }

    private func copyToClipboard() {
        let text = store.entries.map { entry in
            "[\(formatTime(entry.timestamp))] [\(entry.category.uppercased())] [\(entry.level.uppercased())] \(entry.message)"
        }.joined(separator: "\n")
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }
}
