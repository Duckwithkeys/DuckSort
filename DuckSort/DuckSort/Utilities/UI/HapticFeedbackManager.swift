//
//  HapticFeedbackManager.swift
//  DuckSort
//
//  Centralized manager for trackpad physical haptic feedback signals.
//  Executes configurable strength patterns (Light Tick, Double Click, Heavy Pulse).
//

import AppKit

final class HapticFeedbackManager: Sendable {
    static let shared = HapticFeedbackManager()

    private init() {}

    /// Performs the specified haptic feedback profile on supported macOS trackpads.
    @MainActor
    func performHaptic(_ profile: HapticProfile) {
        let performer = NSHapticFeedbackManager.defaultPerformer

        switch profile {
        case .lightTick:
            performer.perform(.generic, performanceTime: .now)

        case .doubleClick:
            performer.perform(.alignment, performanceTime: .now)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.04) {
                performer.perform(.alignment, performanceTime: .now)
            }

        case .heavyPulse:
            performer.perform(.levelChange, performanceTime: .now)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.03) {
                performer.perform(.alignment, performanceTime: .now)
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.03) {
                    performer.perform(.alignment, performanceTime: .now)
                }
            }
        }
    }
}
