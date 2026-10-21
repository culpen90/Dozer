/* This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. https://mozilla.org/MPL/2.0/ */
import Foundation

enum MenuBarItemRole: String, CaseIterable {
    case control, divider, extraDivider
}

/// Logical visibility is independent of AppKit's asynchronously changing window frames.
struct MenuBarState: Equatable {
    private(set) var isHidden = false
    private(set) var isExtraHidden = false
    var extraEnabled = false
    var hideControl = false
    var shortcutAvailable = false

    var controlVisible: Bool { !(isHidden && hideControl && shortcutAvailable) }

    mutating func hide() {
        isHidden = true
        isExtraHidden = extraEnabled
    }

    mutating func show() {
        isHidden = false
        isExtraHidden = extraEnabled
    }

    mutating func showAll() {
        isHidden = false
        isExtraHidden = false
    }

    mutating func toggle() {
        if isHidden { show() } else { hide() }
    }

    mutating func toggleExtra() {
        guard extraEnabled else { show(); return }
        if isHidden { showAll() } else { isExtraHidden.toggle() }
    }

    func isExpanded(_ role: MenuBarItemRole) -> Bool {
        switch role {
        case .control: return false
        case .divider: return isHidden
        case .extraDivider: return extraEnabled && isExtraHidden
        }
    }
}

enum PreferenceValidation {
    static func delay(_ value: Double) -> Double {
        guard value.isFinite else { return 10 }
        return min(max(value, 1), 3600)
    }

    static func iconSize(_ value: Int) -> Int { min(max(value, 6), 18) }

    static func padding(_ value: Double) -> Double {
        guard value.isFinite else { return 25 }
        return min(max(value, 20), 60)
    }

    static func hiddenLength(screenWidths: [Double]) -> Double {
        let width = screenWidths.filter { $0.isFinite && $0 > 0 }.max() ?? 5000
        return min(max(width * 2, 500), 10_000)
    }
}
