/* This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. https://mozilla.org/MPL/2.0/ */
import AppKit
import Carbon

// These checks use actual production window and shortcut sources. They do not
// start WindowManager, request Accessibility, post keyboard input, or move windows.
let app = NSApplication.shared
let suite = "Dozer.WindowShortcutChecks.\(UUID().uuidString)"
guard let defaults = UserDefaults(suiteName: suite) else { fatalError("Cannot create isolated preferences") }
var failures = 0
var checks = 0
func check(_ value: @autoclosure () -> Bool, _ label: String) {
    checks += 1
    if value() { print("PASS: \(label)") }
    else { print("FAIL: \(label)"); failures += 1 }
}

func runChecks() {
    defer { defaults.removePersistentDomain(forName: suite) }
    let manager = WindowShortcutManager(defaults: defaults, observesWindowState: false)
    defer { manager.stop() }
    manager.start()
    check(WindowLayoutAction.allCases.allSatisfy { manager.isRegistered($0) == (WindowShortcutManager.defaultShortcut(for: $0) != nil) }, "configured default shortcuts register and sixths remain unbound")

    // A fresh manager assigns identifier 1 to the first declared action,
    // .leftHalf. Deliver only to this fixture's application event target;
    // this never enters the system keyboard stream or arranges a real window.
    func deliverInitialLeftHalfEvent() -> OSStatus {
        var event: EventRef?
        let creation = CreateEvent(nil, OSType(kEventClassKeyboard), UInt32(kEventHotKeyPressed),
                                   GetCurrentEventTime(), 0, &event)
        guard creation == noErr, let event else { return creation }
        defer { ReleaseEvent(event) }
        var identifier = EventHotKeyID(signature: 0x445A574E, id: 1) // DZWN
        let parameter = SetEventParameter(event, EventParamName(kEventParamDirectObject),
                                           EventParamType(typeEventHotKeyID),
                                           MemoryLayout<EventHotKeyID>.size, &identifier)
        guard parameter == noErr else { return parameter }
        return SendEventToEventTarget(event, GetApplicationEventTarget())
    }
    var dispatched: [WindowLayoutAction] = []
    manager.actionHandler = { dispatched.append($0) }
    check(deliverInitialLeftHalfEvent() == noErr && dispatched == [.leftHalf],
          "Carbon hot-key event dispatches the selected window action")
    var captured: [KeyboardShortcut] = []
    manager.recordingHandler = { captured.append($0) }
    check(deliverInitialLeftHalfEvent() == noErr && captured == [manager.shortcut(for: .leftHalf)!] &&
          dispatched == [.leftHalf], "recording intercepts Carbon hot keys without dispatching window actions")
    manager.recordingHandler = nil
    check(deliverInitialLeftHalfEvent() == noErr && dispatched == [.leftHalf, .leftHalf],
          "ending capture restores Carbon action dispatch")

    let original = manager.shortcut(for: .leftHalf)
    check(!manager.setShortcut(manager.shortcut(for: .rightHalf), for: .leftHalf), "duplicate shortcut is rejected")
    check(manager.shortcut(for: .leftHalf) == original && manager.isRegistered(.leftHalf), "duplicate preserves working binding")
    check(manager.errors[.leftHalf] != nil, "duplicate produces actionable feedback")

    var blocker: EventHotKeyRef?
    let blocked = KeyboardShortcut(keyCode: 90, modifiers: UInt32(controlKey | optionKey | cmdKey | shiftKey), keyName: "F20")
    let result = RegisterEventHotKey(blocked.keyCode, blocked.modifiers,
                                     EventHotKeyID(signature: 0x54455354, id: 400),
                                     GetApplicationEventTarget(), 0, &blocker)
    check(result == noErr, "independent shortcut blocker registers")
    if let blocker {
        check(!manager.setShortcut(blocked, for: .leftHalf), "system registration conflict is rejected")
        check(manager.shortcut(for: .leftHalf) == original && manager.isRegistered(.leftHalf), "system conflict preserves working binding")
        UnregisterEventHotKey(blocker)
    }

    check(manager.setShortcut(nil, for: .leftHalf), "explicit clear succeeds")
    check(!manager.isRegistered(.leftHalf), "clear unregisters binding")
    manager.stop()
    manager.start()
    check(manager.shortcut(for: .leftHalf) == nil && !manager.isRegistered(.leftHalf), "intentional clear survives restart")

    let invalid = KeyboardShortcut(keyCode: 2, modifiers: 0, keyName: "D")
    check(!manager.setShortcut(invalid, for: .rightHalf), "unmodified typing cannot be intercepted")
    manager.setEnabled(false)
    check(WindowLayoutAction.allCases.allSatisfy { !manager.isRegistered($0) }, "disable releases every shortcut")
    check(manager.errors[.rightHalf] == nil, "pause clears stale recording and registration feedback")
    check(manager.setShortcut(blocked, for: .leftHalf), "valid recording saves while disabled")
    check(!manager.isRegistered(.leftHalf), "disabled recording does not register globally")
    manager.setEnabled(true)
    check(manager.isRegistered(.leftHalf), "reenabling registers configured shortcut")
    manager.stop()

    defaults.set(["keyCode": Double.nan, "modifiers": 2304, "keyName": "bad"], forKey: "dozer.windowShortcut.leftHalf")
    defaults.set(["keyCode": true, "modifiers": 2304, "keyName": "bad"], forKey: "dozer.windowShortcut.rightHalf")
    defaults.set(["keyCode": 1, "modifiers": -1, "keyName": "bad"], forKey: "dozer.windowShortcut.topHalf")
    defaults.set("not a shortcut dictionary", forKey: "dozer.windowShortcut.bottomHalf")
    manager.start()
    check(manager.shortcut(for: .leftHalf) == nil && !manager.isRegistered(.leftHalf) && manager.errors[.leftHalf] != nil,
          "nonfinite saved shortcut rejected without fallback")
    check(manager.shortcut(for: .rightHalf) == nil && !manager.isRegistered(.rightHalf) && manager.errors[.rightHalf] != nil,
          "boolean key code rejected without fallback")
    check(manager.shortcut(for: .topHalf) == nil && !manager.isRegistered(.topHalf) && manager.errors[.topHalf] != nil,
          "negative saved modifiers rejected without fallback")
    check(manager.shortcut(for: .bottomHalf) == nil && !manager.isRegistered(.bottomHalf) && manager.errors[.bottomHalf] != nil,
          "malformed saved dictionary rejected without fallback")
    manager.setEnabled(false)
    check(manager.errors[.leftHalf] != nil && manager.errors[.bottomHalf] != nil,
          "pause retains saved preference validation feedback")
    manager.setEnabled(true)
    manager.restoreDefaults()
    check(WindowLayoutAction.allCases.allSatisfy { manager.isRegistered($0) == (WindowShortcutManager.defaultShortcut(for: $0) != nil) }, "restore defaults recovers invalid and cleared bindings")
    check(manager.errors.isEmpty, "successful reset clears errors")
    manager.stop()
    check(WindowLayoutAction.allCases.allSatisfy { !manager.isRegistered($0) }, "stop releases every registered shortcut")

    weak var releasedRecorder: WindowShortcutRecorder?
    autoreleasepool {
        let recorder = WindowShortcutRecorder(action: .leftHalf)
        releasedRecorder = recorder
        // Send the actual button action without AppKit's performClick highlight
        // animation, which temporarily retains its control after the action.
        _ = NSApp.sendAction(recorder.action!, to: recorder.target, from: recorder)
        check(recorder.isRecording && WindowShortcutManager.shared.recordingHandler != nil &&
              ShortcutManager.shared.recordingHandler != nil, "recorder protects both shortcut systems while capturing")
        recorder.stopRecording()
        check(WindowShortcutManager.shared.recordingHandler == nil && ShortcutManager.shared.recordingHandler == nil,
              "stopping a recorder releases both capture callbacks")
        _ = NSApp.sendAction(recorder.action!, to: recorder.target, from: recorder)
    }
    check(releasedRecorder == nil && WindowShortcutManager.shared.recordingHandler == nil &&
          ShortcutManager.shared.recordingHandler == nil, "releasing the last recorder cannot leave shortcuts captured")
}

runChecks()
print("\(checks - failures)/\(checks) window shortcut checks passed")
exit(failures == 0 ? 0 : 1)
