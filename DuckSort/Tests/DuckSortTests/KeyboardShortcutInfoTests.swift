//
//  KeyboardShortcutInfoTests.swift
//  DuckSortTests
//
//  Covers the shortcut parsing + SwiftUI mapping that drives the unified
//  menu/keyboard-shortcut handling.
//

import Testing
import Foundation
import SwiftUI
@testable import DuckSort

struct KeyboardShortcutInfoTests {

    @Test
    func ParseSingleModifier() {
        let info = KeyboardShortcutInfo.parse("cmd+t")
        #expect(info.key == "t")
        #expect(info.command)
        #expect(!(info.shift))
        #expect(!(info.option))
        #expect(!(info.control))
    }

    @Test
    func ParseMultipleModifiersAndAliases() {
        let info = KeyboardShortcutInfo.parse("control+opt+shift+x")
        #expect(info.key == "x")
        #expect(info.control)
        #expect(info.option)
        #expect(info.shift)
        #expect(!(info.command))
    }

    @Test
    func RoundTripSerialization() {
        let info = KeyboardShortcutInfo.parse("shift+cmd+a")
        #expect(KeyboardShortcutInfo.parse(info.serializedString) == info)
    }

    @Test
    func KeyboardShortcutMapsKeyAndModifiers() throws {
        let shortcut = try #require(KeyboardShortcutInfo.parse("cmd+shift+t").keyboardShortcut)
        #expect(shortcut.key.character == "t")
        #expect(shortcut.modifiers.contains(.command))
        #expect(shortcut.modifiers.contains(.shift))
        #expect(!(shortcut.modifiers.contains(.option)))
        #expect(!(shortcut.modifiers.contains(.control)))
    }

    @Test
    func KeyboardShortcutNilWithoutKey() {
        // No printable key means there's nothing for a menu command to bind.
        #expect(KeyboardShortcutInfo.parse("cmd").keyboardShortcut == nil)
        #expect(KeyboardShortcutInfo.parse("").keyboardShortcut == nil)
    }
}
