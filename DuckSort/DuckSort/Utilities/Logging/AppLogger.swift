//
//  AppLogger.swift
//  DuckSort
//
//  Centralized structured logging facade wrapping os.Logger.
//  Provides subsystem-scoped loggers for every module and collects
//  logs in memory for viewing in the Log Console window.
//

import os
import Foundation

struct LogEntry: Identifiable, Sendable {
    let id = UUID()
    let timestamp = Date()
    let subsystem: String
    let category: String
    let level: String
    let message: String
}

@MainActor
final class LogConsoleStore: ObservableObject {
    static let shared = LogConsoleStore()

    @Published var entries: [LogEntry] = []

    func append(category: String, level: String, message: String) {
        let entry = LogEntry(subsystem: "com.ducksort", category: category, level: level, message: message)
        if entries.count > 500 {
            entries.removeFirst(100)
        }
        entries.append(entry)
    }

    func clear() {
        entries = []
    }
}

struct AppSubsystemLogger: Sendable {
    private let logger: Logger
    let category: String

    init(subsystem: String, category: String) {
        self.logger = Logger(subsystem: subsystem, category: category)
        self.category = category
    }

    func debug(_ message: String) {
        logger.debug("\(message, privacy: .public)")
        logToStore(level: "debug", message: message)
    }

    func trace(_ message: String) {
        logger.trace("\(message, privacy: .public)")
        logToStore(level: "debug", message: message)
    }

    func info(_ message: String) {
        logger.info("\(message, privacy: .public)")
        logToStore(level: "info", message: message)
    }

    func warning(_ message: String) {
        logger.warning("\(message, privacy: .public)")
        logToStore(level: "warning", message: message)
    }

    func error(_ message: String) {
        logger.error("\(message, privacy: .public)")
        logToStore(level: "error", message: message)
    }

    func fault(_ message: String) {
        logger.fault("\(message, privacy: .public)")
        logToStore(level: "fault", message: message)
    }

    private func logToStore(level: String, message: String) {
        let cat = category
        Task { @MainActor in
            LogConsoleStore.shared.append(category: cat, level: level, message: message)
        }
    }
}

enum AppLogger {
    private static let subsystem = "com.ducksort"

    // MARK: - Category loggers

    /// Thumbnail loading, decoding, and cache operations.
    static let thumbnails = AppSubsystemLogger(subsystem: subsystem, category: "thumbnails")

    /// Metadata reading, XMP parsing, and index operations.
    static let metadata = AppSubsystemLogger(subsystem: subsystem, category: "metadata")

    /// File copy, move, and routed transfer operations.
    static let transfer = AppSubsystemLogger(subsystem: subsystem, category: "transfer")

    /// UI rendering, Metal, scroll, and memory pressure events.
    static let ui = AppSubsystemLogger(subsystem: subsystem, category: "ui")

    /// File scanning and directory enumeration.
    static let scanner = AppSubsystemLogger(subsystem: subsystem, category: "scanner")

    /// AI / Vision framework operations.
    static let vision = AppSubsystemLogger(subsystem: subsystem, category: "vision")
}
