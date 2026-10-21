// Adapted from Rectangle's AccessibilityElement.swift (EnhancedUI).
// Copyright (c) 2019–2026 Ryan Hanson; based on Spectacle,
// Copyright (c) 2017 Eric Czarny. MIT license; see ThirdParty/Rectangle/.
import AppKit
import ApplicationServices

/// Scope Rectangle's native AX animation mitigation to one synchronous adjustment.
/// Preserve the application's previous setting and active assistive technologies.
enum RectangleWindowAdjustment {
    static func perform<Value>(for window: AXUIElement,
                               adjustment: () throws -> Value) rethrows -> Value {
        var pid: pid_t = 0
        guard AXUIElementGetPid(window, &pid) == .success else { return try adjustment() }
        let application = AXUIElementCreateApplication(pid)
        let attribute = "AXEnhancedUserInterface" as CFString
        return try perform(
            assistiveTechnologyActive: NSWorkspace.shared.isVoiceOverEnabled || NSWorkspace.shared.isSwitchControlEnabled,
            readEnhancedUI: {
                var value: CFTypeRef?
                guard AXUIElementCopyAttributeValue(application, attribute, &value) == .success else { return nil }
                return value as? Bool
            },
            writeEnhancedUI: { enabled in
                AXUIElementSetAttributeValue(application, attribute, enabled as CFBoolean) == .success
            },
            adjustment: adjustment
        )
    }

    /// Injectable boundary for checking state restoration without Accessibility access.
    static func perform<Value>(assistiveTechnologyActive: Bool,
                               readEnhancedUI: () -> Bool?,
                               writeEnhancedUI: (Bool) -> Bool,
                               adjustment: () throws -> Value) rethrows -> Value {
        guard !assistiveTechnologyActive, readEnhancedUI() == true else { return try adjustment() }
        _ = writeEnhancedUI(false)
        // A failed write may still have reached a deferred toolkit handler.
        // Always attempt to restore the true value observed before the scope.
        defer { _ = writeEnhancedUI(true) }
        return try adjustment()
    }
}
