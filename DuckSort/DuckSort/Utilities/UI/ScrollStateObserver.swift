//
//  ScrollStateObserver.swift
//  PhotomatorSort
//

import AppKit
import Foundation
import SwiftUI

@MainActor
final class ScrollStateObserver: ObservableObject {
    static let shared = ScrollStateObserver()
    
    @Published private(set) var isScrolling = false
    private var timer: Timer?

    private init() {
        NotificationCenter.default.addObserver(self, selector: #selector(handleScrollStart), name: NSScrollView.willStartLiveScrollNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(handleScrollEnd), name: NSScrollView.didEndLiveScrollNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(handleScrollMove), name: NSScrollView.didLiveScrollNotification, object: nil)
    }

    @objc private func handleScrollStart() {
        if !isScrolling { isScrolling = true }
        timer?.invalidate()
    }

    @objc private func handleScrollEnd() {
        scheduleScrollEnd()
    }

    @objc private func handleScrollMove() {
        if !isScrolling { isScrolling = true }
        scheduleScrollEnd()
    }

    private func scheduleScrollEnd() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 0.08, repeats: false) { [weak self] _ in
            Task { @MainActor in
                guard let self, self.isScrolling else { return }
                self.isScrolling = false
            }
        }
    }
}
