/* This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. https://mozilla.org/MPL/2.0/ */
import AppKit
import Carbon

extension Notification.Name {
    static let dozerWindowShortcutsChanged = Notification.Name("DozerWindowShortcutsChanged")
}

/// Independent Carbon bindings keep window shortcuts separate from Dozer's reveal shortcut.
/// Registering a replacement first means a conflicting recording leaves the working binding intact.
final class WindowShortcutManager {
    static let shared = WindowShortcutManager()
    private(set) var errors: [WindowLayoutAction: String] = [:]
    private(set) var lastError: String?
    private(set) var isEnabled = true
    var recordingHandler: ((KeyboardShortcut) -> Void)?

    private var shortcuts: [WindowLayoutAction: KeyboardShortcut] = [:]
    private var savedBindingErrors: [WindowLayoutAction: String] = [:]
    private var registrations: [WindowLayoutAction: EventHotKeyRef] = [:]
    private var identifiers: [UInt32: WindowLayoutAction] = [:]
    private var eventHandler: EventHandlerRef?
    private var observer: NSObjectProtocol?
    private var nextIdentifier: UInt32 = 0
    private let signature: OSType = 0x445A574E // DZWN
    private let defaults: UserDefaults
    private let observesWindowState: Bool
    private var hasStarted = false
    var actionHandler: (WindowLayoutAction) -> Void = { WindowManager.shared.execute($0) }

    init(defaults: UserDefaults = .standard, observesWindowState: Bool = true) {
        self.defaults = defaults
        self.observesWindowState = observesWindowState
    }

    deinit { stop() }

    func start() {
        guard !hasStarted else { return }
        hasStarted = true
        if observesWindowState {
            isEnabled = WindowManager.shared.isEnabled
            observer = NotificationCenter.default.addObserver(forName: .dozerWindowStateChanged,
                                                               object: nil, queue: .main) { [weak self] _ in
                self?.setEnabled(WindowManager.shared.isEnabled)
            }
        }
        loadBindings()
        installEventHandler()
        if isEnabled { registerConfiguredBindings() }
        publishChange()
    }

    func stop() {
        releaseRegistrations()
        if let eventHandler { RemoveEventHandler(eventHandler) }
        eventHandler = nil
        if let observer { NotificationCenter.default.removeObserver(observer) }
        observer = nil
        recordingHandler = nil
        hasStarted = false
    }

    func shortcut(for action: WindowLayoutAction) -> KeyboardShortcut? { shortcuts[action] }
    func isRegistered(_ action: WindowLayoutAction) -> Bool { registrations[action] != nil }

    func setEnabled(_ enabled: Bool) {
        guard isEnabled != enabled else { return }
        isEnabled = enabled
        releaseRegistrations()
        errors = savedBindingErrors
        lastError = WindowLayoutAction.allCases.compactMap { errors[$0] }.first
        if enabled, hasStarted { registerConfiguredBindings() }
        publishChange()
    }

    @discardableResult
    func setShortcut(_ candidate: KeyboardShortcut?, for action: WindowLayoutAction) -> Bool {
        if let candidate {
            if let error = candidate.validationError { return fail(error, for: action) }
            if let other = shortcuts.first(where: {
                $0.key != action && Self.matches($0.value, candidate)
            }) {
                return fail("That shortcut is assigned to \(other.key.title). Clear it there first.", for: action)
            }
            if let reveal = ShortcutManager.shared.shortcut, Self.matches(reveal, candidate) {
                return fail("That shortcut is assigned to showing menu bar icons.", for: action)
            }
            if let current = shortcuts[action], Self.matches(current, candidate),
               !isEnabled || registrations[action] != nil {
                shortcuts[action] = candidate
                persist(candidate, for: action)
                savedBindingErrors[action] = nil
                errors[action] = nil
                lastError = nil
                publishChange()
                return true
            }
            if isEnabled {
                guard eventHandler != nil else {
                    return fail("Window shortcuts are unavailable. Reopen Dozer and try again.", for: action)
                }
                guard let replacement = register(candidate, for: action) else {
                    publishChange()
                    return false
                }
                removeRegistration(for: action)
                registrations[action] = replacement.reference
                identifiers[replacement.identifier] = action
            }
            shortcuts[action] = candidate
        } else {
            removeRegistration(for: action)
            shortcuts[action] = nil
        }
        persist(candidate, for: action)
        savedBindingErrors[action] = nil
        errors[action] = nil
        lastError = nil
        publishChange()
        return true
    }

    /// Explicitly reset all bindings, including intentional clears and malformed saved values.
    func restoreDefaults() {
        releaseRegistrations()
        for action in WindowLayoutAction.allCases { defaults.removeObject(forKey: storageKey(action)) }
        loadBindings()
        if isEnabled, hasStarted { registerConfiguredBindings() }
        publishChange()
    }

    static func defaultShortcut(for action: WindowLayoutAction) -> KeyboardShortcut? {
        let modifiers = UInt32(controlKey | optionKey)
        let code: UInt32
        let name: String
        var extra: UInt32 = 0
        switch action {
        case .leftHalf: (code, name) = (123, "←")
        case .rightHalf: (code, name) = (124, "→")
        case .topHalf: (code, name) = (126, "↑")
        case .bottomHalf: (code, name) = (125, "↓")
        case .topLeft: (code, name) = (32, "U")
        case .topRight: (code, name) = (34, "I")
        case .bottomLeft: (code, name) = (38, "J")
        case .bottomRight: (code, name) = (40, "K")
        case .firstThird: (code, name) = (14, "E")
        case .centerThird: (code, name) = (17, "T")
        case .lastThird: (code, name) = (15, "R")
        case .firstTwoThirds: (code, name) = (3, "F")
        case .lastTwoThirds: (code, name) = (5, "G")
        case .maximize: (code, name) = (36, "Return")
        case .almostMaximize: (code, name) = (36, "Return"); extra = UInt32(shiftKey)
        case .center: (code, name) = (8, "C")
        case .larger: (code, name) = (24, "=")
        case .smaller: (code, name) = (27, "−")
        case .nextDisplay: (code, name) = (124, "→"); extra = UInt32(shiftKey)
        case .previousDisplay: (code, name) = (123, "←"); extra = UInt32(shiftKey)
        case .restore: (code, name) = (51, "Delete")
        }
        return KeyboardShortcut(keyCode: code, modifiers: modifiers | extra, keyName: name)
    }

    private func installEventHandler() {
        var type = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let status = InstallEventHandler(GetApplicationEventTarget(), { _, event, context in
            guard let event, let context else { return OSStatus(eventNotHandledErr) }
            let manager = Unmanaged<WindowShortcutManager>.fromOpaque(context).takeUnretainedValue()
            var identifier = EventHotKeyID()
            let status = GetEventParameter(event, EventParamName(kEventParamDirectObject),
                                           EventParamType(typeEventHotKeyID), nil,
                                           MemoryLayout<EventHotKeyID>.size, nil, &identifier)
            guard status == noErr, identifier.signature == manager.signature,
                  let action = manager.identifiers[identifier.id],
                  let shortcut = manager.shortcuts[action], manager.isEnabled else {
                return OSStatus(eventNotHandledErr)
            }
            if let recordingHandler = manager.recordingHandler {
                recordingHandler(shortcut)
            } else if let revealRecorder = ShortcutManager.shared.recordingHandler {
                // A shortcut recorder must never move a window as a side effect of recording.
                revealRecorder()
            } else {
                manager.actionHandler(action)
            }
            return noErr
        }, 1, &type, Unmanaged.passUnretained(self).toOpaque(), &eventHandler)
        if status != noErr { lastError = "Window shortcuts could not be initialized (\(status))." }
    }

    private func loadBindings() {
        shortcuts.removeAll()
        errors.removeAll()
        for action in WindowLayoutAction.allCases {
            guard let saved = defaults.object(forKey: storageKey(action)) else {
                shortcuts[action] = Self.defaultShortcut(for: action)
                continue
            }
            guard let dictionary = saved as? [String: Any] else {
                errors[action] = "The saved shortcut is invalid. Record a new shortcut."
                continue
            }
            if dictionary["disabled"] as? Bool == true { continue }
            guard let code = dictionary["keyCode"] as? NSNumber,
                  let modifier = dictionary["modifiers"] as? NSNumber,
                  let keyCode = exactUInt32(code), let modifiers = exactUInt32(modifier),
                  let keyName = dictionary["keyName"] as? String else {
                errors[action] = "The saved shortcut is invalid. Record a new shortcut."
                continue
            }
            let candidate = KeyboardShortcut(keyCode: keyCode, modifiers: modifiers, keyName: keyName)
            if let error = candidate.validationError { errors[action] = error }
            else { shortcuts[action] = candidate }
        }
        savedBindingErrors = errors
        lastError = WindowLayoutAction.allCases.compactMap { errors[$0] }.first
    }

    private func registerConfiguredBindings() {
        guard eventHandler != nil else { return }
        for action in WindowLayoutAction.allCases {
            guard let shortcut = shortcuts[action] else { continue }
            if let reveal = ShortcutManager.shared.shortcut, Self.matches(reveal, shortcut) {
                errors[action] = "That shortcut is assigned to showing menu bar icons."
                continue
            }
            if let duplicate = registrations.keys.first(where: {
                shortcuts[$0].map { Self.matches($0, shortcut) } == true
            }) {
                errors[action] = "That shortcut is assigned to \(duplicate.title)."
                continue
            }
            if let registration = register(shortcut, for: action) {
                registrations[action] = registration.reference
                identifiers[registration.identifier] = action
                errors[action] = nil
            }
        }
        lastError = WindowLayoutAction.allCases.compactMap { errors[$0] }.first
    }

    private func register(_ shortcut: KeyboardShortcut, for action: WindowLayoutAction)
        -> (reference: EventHotKeyRef, identifier: UInt32)? {
        nextIdentifier &+= 1
        if nextIdentifier == 0 { nextIdentifier = 1 }
        var reference: EventHotKeyRef?
        let status = RegisterEventHotKey(shortcut.keyCode, shortcut.modifiers,
                                         EventHotKeyID(signature: signature, id: nextIdentifier),
                                         GetApplicationEventTarget(), 0, &reference)
        guard status == noErr, let reference else {
            _ = fail(status == eventHotKeyExistsErr
                ? "That shortcut is already in use by another app. Choose another combination."
                : "That shortcut could not be registered (\(status)).", for: action, publish: false)
            return nil
        }
        return (reference, nextIdentifier)
    }

    private func removeRegistration(for action: WindowLayoutAction) {
        if let reference = registrations.removeValue(forKey: action) { UnregisterEventHotKey(reference) }
        identifiers = identifiers.filter { $0.value != action }
    }

    private func releaseRegistrations() {
        registrations.values.forEach { UnregisterEventHotKey($0) }
        registrations.removeAll()
        identifiers.removeAll()
    }

    private func persist(_ shortcut: KeyboardShortcut?, for action: WindowLayoutAction) {
        guard let shortcut else {
            defaults.set(["disabled": true], forKey: storageKey(action))
            return
        }
        defaults.set(["keyCode": shortcut.keyCode, "modifiers": shortcut.modifiers,
                      "keyName": shortcut.keyName], forKey: storageKey(action))
    }

    private func storageKey(_ action: WindowLayoutAction) -> String { "dozer.windowShortcut.\(action.rawValue)" }
    private static func matches(_ lhs: KeyboardShortcut, _ rhs: KeyboardShortcut) -> Bool {
        lhs.keyCode == rhs.keyCode && lhs.modifiers == rhs.modifiers
    }
    private func exactUInt32(_ number: NSNumber) -> UInt32? {
        guard CFGetTypeID(number) != CFBooleanGetTypeID() else { return nil }
        let value = number.doubleValue
        guard value.isFinite, value >= 0, value <= Double(UInt32.max), value.rounded() == value else { return nil }
        return UInt32(value)
    }
    @discardableResult private func fail(_ error: String, for action: WindowLayoutAction, publish: Bool = true) -> Bool {
        errors[action] = error
        lastError = error
        if publish { publishChange() }
        return false
    }
    private func publishChange() {
        NotificationCenter.default.post(name: .dozerWindowShortcutsChanged, object: self)
    }
}
