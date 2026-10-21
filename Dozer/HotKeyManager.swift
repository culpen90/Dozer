/* This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/. */

import AppKit
import Carbon

extension Notification.Name {
    static let dozerShortcutChanged = Notification.Name("DozerShortcutChanged")
}

struct KeyboardShortcut: Equatable {
    let keyCode: UInt32
    let modifiers: UInt32
    let keyName: String

    var displayString: String {
        var result = ""
        if modifiers & UInt32(controlKey) != 0 { result += "⌃" }
        if modifiers & UInt32(optionKey) != 0 { result += "⌥" }
        if modifiers & UInt32(shiftKey) != 0 { result += "⇧" }
        if modifiers & UInt32(cmdKey) != 0 { result += "⌘" }
        return result + keyName
    }

    static func carbonModifiers(_ flags: NSEvent.ModifierFlags) -> UInt32 {
        var value: UInt32 = 0
        if flags.contains(.command) { value |= UInt32(cmdKey) }
        if flags.contains(.option) { value |= UInt32(optionKey) }
        if flags.contains(.control) { value |= UInt32(controlKey) }
        if flags.contains(.shift) { value |= UInt32(shiftKey) }
        return value
    }

    /// Validate persisted shortcuts as well as recordings; never intercept unmodified typing.
    var validationError: String? {
        let allowed = UInt32(controlKey | optionKey | shiftKey | cmdKey)
        let required = UInt32(controlKey | optionKey | cmdKey)
        let modifierKeyCodes: Set<UInt32> = [54, 55, 56, 57, 58, 59, 60, 61, 62, 63]
        guard keyCode <= 126, !modifierKeyCodes.contains(keyCode) else {
            return "Choose a letter, number, function key, or navigation key."
        }
        guard modifiers & required != 0, modifiers & ~allowed == 0 else {
            return "Include Command, Option, or Control in the shortcut."
        }
        // Use physical key codes so a malformed stored keyName cannot bypass this check.
        if modifiers == UInt32(cmdKey), [12, 13, 4, 46, 48, 49].contains(keyCode) {
            return "Choose a combination that does not replace a standard macOS command."
        }
        guard !keyName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, keyName.count <= 40 else {
            return "The saved shortcut is invalid. Record a new shortcut."
        }
        return nil
    }

    static func name(for event: NSEvent) -> String {
        let special: [UInt16: String] = [
            36: "Return", 48: "Tab", 49: "Space", 51: "Delete", 53: "Escape",
            76: "Enter", 115: "Home", 116: "Page Up", 117: "Forward Delete",
            119: "End", 121: "Page Down", 123: "←", 124: "→", 125: "↓", 126: "↑",
            122: "F1", 120: "F2", 99: "F3", 118: "F4", 96: "F5", 97: "F6",
            98: "F7", 100: "F8", 101: "F9", 109: "F10", 103: "F11", 111: "F12",
            105: "F13", 107: "F14", 113: "F15", 106: "F16", 64: "F17", 79: "F18", 80: "F19", 90: "F20"
        ]
        return special[event.keyCode] ?? event.charactersIgnoringModifiers?.uppercased() ?? "Key \(event.keyCode)"
    }
}

/// Carbon's global hot-key API works without observing typing or requiring Accessibility access.
final class ShortcutManager {
    static let shared = ShortcutManager()
    private(set) var shortcut: KeyboardShortcut?
    private(set) var lastError: String?
    private var hotKey: EventHotKeyRef?
    private var eventHandler: EventHandlerRef?
    private var handler: (() -> Void)?
    var recordingHandler: (() -> Void)?
    private var identifier: UInt32 = 0
    private let signature: OSType = 0x444F5A52 // DOZR
    private let defaults = UserDefaults.standard

    var isRegistered: Bool { hotKey != nil }
    var shortcutDescription: String { shortcut?.displayString ?? "None" }

    private init() {}

    func start(handler: @escaping () -> Void) {
        self.handler = handler
        guard eventHandler == nil else { return }
        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let status = InstallEventHandler(GetApplicationEventTarget(), { _, event, userData in
            guard let userData, let event else { return OSStatus(eventNotHandledErr) }
            let manager = Unmanaged<ShortcutManager>.fromOpaque(userData).takeUnretainedValue()
            var hotKeyID = EventHotKeyID()
            let result = GetEventParameter(event, EventParamName(kEventParamDirectObject),
                                          EventParamType(typeEventHotKeyID), nil,
                                          MemoryLayout<EventHotKeyID>.size, nil, &hotKeyID)
            guard result == noErr, hotKeyID.signature == manager.signature,
                  hotKeyID.id == manager.identifier else { return OSStatus(eventNotHandledErr) }
            if let recordingHandler = manager.recordingHandler {
                recordingHandler()
            } else {
                manager.handler?()
            }
            return noErr
        }, 1, &eventType, Unmanaged.passUnretained(self).toOpaque(), &eventHandler)
        guard status == noErr else {
            lastError = "The global shortcut could not be initialized (\(status))."
            publishChange()
            return
        }
        if let saved = loadShortcut() {
            _ = setShortcut(saved)
        } else if !defaults.bool(forKey: "dozerShortcutInitialized") {
            // A recoverable default lets fresh installs use no-icon mode immediately.
            defaults.set(true, forKey: "dozerShortcutInitialized")
            _ = setShortcut(KeyboardShortcut(keyCode: 2, modifiers: UInt32(controlKey | optionKey), keyName: "D"))
        } else {
            publishChange()
        }
    }

    /// Register a replacement before releasing the working shortcut, so a conflict never locks the user out.
    @discardableResult
    func setShortcut(_ candidate: KeyboardShortcut?) -> Bool {
        if candidate == shortcut, isRegistered {
            lastError = nil
            return true
        }
        guard let candidate else {
            if let hotKey { UnregisterEventHotKey(hotKey) }
            hotKey = nil
            shortcut = nil
            lastError = nil
            defaults.set(true, forKey: "dozerShortcutInitialized")
            defaults.removeObject(forKey: "dozerKeyboardShortcut")
            defaults.removeObject(forKey: "toggleMenuItems")
            publishChange()
            return true
        }
        if let error = candidate.validationError {
            lastError = error
            publishChange()
            return false
        }
        guard eventHandler != nil else {
            lastError = "The global shortcut is unavailable. Reopen Dozer and try again."
            publishChange()
            return false
        }
        var replacement: EventHotKeyRef?
        let nextIdentifier = identifier &+ 1
        let hotKeyID = EventHotKeyID(signature: signature, id: nextIdentifier)
        let result = RegisterEventHotKey(candidate.keyCode, candidate.modifiers, hotKeyID,
                                         GetApplicationEventTarget(), 0, &replacement)
        guard result == noErr, let replacement else {
            lastError = result == eventHotKeyExistsErr
                ? "That shortcut is already in use. Choose another combination."
                : "That shortcut could not be registered (\(result)). Choose another combination."
            publishChange()
            return false
        }
        if let hotKey { UnregisterEventHotKey(hotKey) }
        hotKey = replacement
        identifier = nextIdentifier
        shortcut = candidate
        lastError = nil
        defaults.set(true, forKey: "dozerShortcutInitialized")
        defaults.set(["keyCode": candidate.keyCode, "modifiers": candidate.modifiers,
                      "keyName": candidate.keyName], forKey: "dozerKeyboardShortcut")
        publishChange()
        return true
    }

    private func loadShortcut() -> KeyboardShortcut? {
        let invalid = KeyboardShortcut(keyCode: UInt32.max, modifiers: 0, keyName: "")
        if let savedValue = defaults.object(forKey: "dozerKeyboardShortcut") {
            guard let saved = savedValue as? [String: Any],
                  let code = saved["keyCode"] as? NSNumber,
                  let modifiers = saved["modifiers"] as? NSNumber,
                  let codeValue = exactUInt32(code), let modifierValue = exactUInt32(modifiers),
                  let name = saved["keyName"] as? String else { return invalid }
            return KeyboardShortcut(keyCode: codeValue, modifiers: modifierValue, keyName: name)
        }
        // MASShortcut stored the physical key and NSEvent modifier mask in this dictionary.
        if let legacyValue = defaults.object(forKey: "toggleMenuItems") {
            guard let legacy = legacyValue as? [String: Any],
                  let code = legacy["keyCode"] as? NSNumber,
                  let modifiers = legacy["modifierFlags"] as? NSNumber,
                  let codeValue = exactUInt32(code), codeValue <= 126,
                  let modifierValue = exactUInt32(modifiers) else { return invalid }
            let flags = NSEvent.ModifierFlags(rawValue: UInt(modifierValue))
            let name = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0,
                                       windowNumber: 0, context: nil, characters: "", charactersIgnoringModifiers: "",
                                       isARepeat: false, keyCode: UInt16(codeValue))
                .map { KeyboardShortcut.name(for: $0) } ?? "Key \(codeValue)"
            return KeyboardShortcut(keyCode: codeValue,
                                    modifiers: KeyboardShortcut.carbonModifiers(flags),
                                    keyName: name.isEmpty ? "Key \(codeValue)" : name)
        }
        return nil
    }

    private func exactUInt32(_ number: NSNumber) -> UInt32? {
        let value = number.doubleValue
        guard value.isFinite, value >= 0, value <= Double(UInt32.max), value.rounded() == value else { return nil }
        return UInt32(value)
    }

    private func publishChange() {
        defaults.set(isRegistered, forKey: "isShortcutSet")
        NotificationCenter.default.post(name: .dozerShortcutChanged, object: self)
    }
}

final class ShortcutRecorderButton: NSButton {
    private(set) var isRecording = false
    var onChange: (() -> Void)?
    private var keyMonitor: Any?
    private var resignObserver: NSObjectProtocol?

    override var acceptsFirstResponder: Bool { true }

    convenience init() {
        self.init(frame: .zero)
        bezelStyle = .rounded
        target = self
        action = #selector(beginRecording)
        setAccessibilityLabel("Record toggle keyboard shortcut")
        refreshTitle()
    }

    deinit {
        if let keyMonitor { NSEvent.removeMonitor(keyMonitor) }
        if let resignObserver { NotificationCenter.default.removeObserver(resignObserver) }
    }

    func refreshTitle() {
        title = isRecording ? "Type shortcut…" : ShortcutManager.shared.shortcutDescription
    }

    @objc private func beginRecording() {
        if isRecording {
            stopRecording()
            return
        }
        isRecording = true
        // The already registered combination is delivered as a Carbon event, not keyDown.
        ShortcutManager.shared.recordingHandler = { [weak self] in
            self?.stopRecording()
            self?.onChange?()
        }
        window?.makeFirstResponder(self)
        refreshTitle()
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, self.isRecording, event.window === self.window else { return event }
            self.capture(event)
            return nil
        }
        resignObserver = NotificationCenter.default.addObserver(forName: NSWindow.didResignKeyNotification,
                                                                object: window, queue: .main) { [weak self] _ in
            self?.stopRecording()
        }
    }

    func stopRecording() {
        isRecording = false
        ShortcutManager.shared.recordingHandler = nil
        if let keyMonitor { NSEvent.removeMonitor(keyMonitor) }
        keyMonitor = nil
        if let resignObserver { NotificationCenter.default.removeObserver(resignObserver) }
        resignObserver = nil
        refreshTitle()
    }

    private func capture(_ event: NSEvent) {
        if event.keyCode == 53 { // Escape cancels without changing the existing shortcut.
            stopRecording()
            return
        }
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        if (event.keyCode == 51 || event.keyCode == 117),
           flags.intersection([.command, .option, .control, .shift]).isEmpty {
            ShortcutManager.shared.setShortcut(nil)
            stopRecording()
            onChange?()
            return
        }
        guard !event.isARepeat else { return }
        guard !flags.intersection([.command, .option, .control]).isEmpty else {
            showError("Include Command, Option, or Control in the shortcut.")
            return
        }
        let name = KeyboardShortcut.name(for: event)
        // Preserve the standard app commands used to escape, close and quit.
        if flags.intersection([.command, .option, .control, .shift]) == .command,
           ["Q", "W", "H", "M", "Tab", "Space"].contains(name) {
            showError("Choose a combination that does not replace a standard macOS command.")
            return
        }
        let shortcut = KeyboardShortcut(keyCode: UInt32(event.keyCode),
                                        modifiers: KeyboardShortcut.carbonModifiers(flags), keyName: name)
        if ShortcutManager.shared.setShortcut(shortcut) {
            stopRecording()
            onChange?()
        } else {
            showError(ShortcutManager.shared.lastError ?? "Choose another shortcut.")
        }
    }

    private func showError(_ message: String) {
        stopRecording()
        let alert = NSAlert()
        alert.messageText = "Choose another shortcut"
        alert.informativeText = message
        if let window { alert.beginSheetModal(for: window) }
        onChange?()
    }
}
