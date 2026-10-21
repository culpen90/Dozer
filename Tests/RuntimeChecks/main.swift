/* Local integration checks: creates only Dozer-owned menu items, never moves other apps. */
import Cocoa
import Carbon

let app = NSApplication.shared
let appDelegate = AppDelegate() // Required by status-item actions; not installed as this harness's delegate.
app.setActivationPolicy(.accessory)
DispatchQueue.main.async { runChecks() }
func runChecks() {
Settings.registerDefaults()
Settings.store.set(false, forKey: "showIconAndMenuEnabled")
Settings.store.set(false, forKey: "hideAfterDelayEnabled")
Settings.store.set(false, forKey: "noIconMode")
Settings.store.set(false, forKey: "removeStatusIconEnabled")
var failures: [String] = []
var passed = 0
func check(_ condition: @autoclosure () -> Bool, _ message: String) {
    if condition() { passed += 1; print("PASS \(message)") }
    else { failures.append(message); print("FAIL \(message)") }
}
func settle(_ seconds: Double = 2) {
    let end = Date().addingTimeInterval(seconds)
    while Date() < end {
        if let event = app.nextEvent(matching: .any, until: Date().addingTimeInterval(0.02), inMode: .default, dequeue: true) {
            app.sendEvent(event)
        }
        app.updateWindows()
    }
}
func onscreen(_ item: NSStatusItem) -> Bool {
    guard let frame = item.button?.window?.frame, frame.width > 0 else { return false }
    return NSScreen.screens.contains { frame.intersection($0.frame).width > 1 }
}
func hostedOnscreen(_ name: String) -> Bool {
    let windows = CGWindowListCopyWindowInfo(.optionOnScreenOnly, kCGNullWindowID) as? [[String: Any]] ?? []
    return windows.contains { ($0[kCGWindowName as String] as? String) == name }
}
func dump(_ name: String, _ icons: DozerIcons, _ sentinel: NSStatusItem) {
    func geometry(_ rect: CGRect?) -> String {
        guard let rect else { return "unavailable" }
        return "[\(Int(rect.minX)),\(Int(rect.minY)) \(Int(rect.width))x\(Int(rect.height))]"
    }
    let items = icons.items.map {
        "\($0.role.rawValue)=\(geometry($0.frame))/length:\(Int($0.statusIcon.length))"
    }.joined(separator: " ")
    print("LAYOUT \(name) screens=\(NSScreen.screens.map { geometry($0.frame) }.joined(separator: ",")) \(items) sentinel=\(geometry(sentinel.button?.window?.frame))")
    if let windows = CGWindowListCopyWindowInfo(.optionOnScreenOnly, kCGNullWindowID) as? [[String: Any]] {
        let owned = windows.compactMap { window -> String? in
            guard let title = window[kCGWindowName as String] as? String, title.hasPrefix("Dozer.") else { return nil }
            let values = window[kCGWindowBounds as String] as? [String: NSNumber] ?? [:]
            let bounds = CGRect(x: values["X"]?.doubleValue ?? 0, y: values["Y"]?.doubleValue ?? 0,
                                width: values["Width"]?.doubleValue ?? 0, height: values["Height"]?.doubleValue ?? 0)
            let identifier = window[kCGWindowNumber as String] as? Int ?? 0
            return "\(title)#\(identifier)=\(geometry(bounds))"
        }
        print("HOSTED \(name) \(owned.isEmpty ? "no Dozer windows" : owned.joined(separator: " "))")
    }
}
var hotkeyActivations = 0
ShortcutManager.shared.start(handler: { hotkeyActivations += 1; DozerIcons.shared.toggle() })
let icons = DozerIcons.shared
icons.showAll()
let sentinel = NSStatusBar.system.statusItem(withLength: 25)
sentinel.autosaveName = "Dozer.TestSentinel"
sentinel.button?.title = "T"
settle(1)
check(icons.items.count == 2, "two stable menu controls")
check(icons.items.allSatisfy { onscreen($0.statusIcon) }, "controls physically onscreen")
check(onscreen(sentinel), "test item initially onscreen")
check(hostedOnscreen("Dozer.TestSentinel"), "remote menu host initially shows test item")
check(ShortcutManager.shared.isRegistered, "global shortcut registered")
dump("shown", icons, sentinel)

icons.hide()
settle()
dump("hidden", icons, sentinel)
check(icons.isHidden, "logical hidden state")
check(!onscreen(sentinel), "real AppKit overflow hides test item")
check(!hostedOnscreen("Dozer.TestSentinel"), "remote menu host confirms test item hidden")
check(onscreen(icons.items.first { $0.role == .control }!.statusIcon), "control remains reachable while collapsed")
icons.show()
settle()
check(onscreen(sentinel), "real AppKit overflow restores test item")
check(hostedOnscreen("Dozer.TestSentinel"), "remote menu host confirms test item restored")

let identities = icons.items.map { ObjectIdentifier($0) }
for _ in 0..<100 { icons.toggle() }
check(identities == icons.items.map { ObjectIdentifier($0) }, "100 toggles preserve item identities")
icons.enableRemoveDozerIcon = true
settle()
check(icons.items.count == 3, "optional divider creates once")
icons.hide()
icons.handleOptionClick()
check(!icons.isHidden && !icons.isExtraHidden, "Option-click recovers both groups")
icons.handleOptionClick()
check(!icons.isHidden && icons.isExtraHidden, "Option-click toggles only extra group while shown")
icons.showAll()
for _ in 0..<10 {
    icons.enableRemoveDozerIcon = false
    icons.enableRemoveDozerIcon = true
}
check(icons.items.count == 3, "optional divider never duplicates")
icons.enableRemoveDozerIcon = false

icons.hideBothDozerIcons = true
icons.hide()
settle()
check(icons.items.first { $0.role == .control }?.statusIcon.isVisible == false, "no-icon control is removed with working shortcut")
ShortcutManager.shared.setShortcut(nil)
settle()
check(!icons.isHidden, "clearing shortcut immediately recovers hidden controls")
check(onscreen(icons.items.first { $0.role == .control }!.statusIcon), "clearing shortcut restores real control")
icons.hide()
check(icons.items.first { $0.role == .control }!.statusIcon.isVisible, "unregistered shortcut cannot hide control")
icons.hideBothDozerIcons = false
icons.showAll()

Settings.store.set(1.0, forKey: "hideAfterDelay")
icons.hideStatusBarIconsAfterDelay = true
for _ in 0..<100 { icons.showAll() }
check(icons.activeTimerCount == 1, "repeated show keeps exactly one auto-hide timer")
settle(1.6)
check(icons.isHidden, "auto-hide countdown fires")
check(icons.activeTimerCount == 0, "hidden state stops timer")
icons.showAll()
icons.hideStatusBarIconsAfterDelay = false
settle(1.5)
check(!icons.isHidden && icons.activeTimerCount == 0, "disabling auto-hide cancels pending countdown")

// Dispatch the Carbon hot-key event through the application event target, without synthesizing input.
ShortcutManager.shared.setShortcut(KeyboardShortcut(keyCode: 2, modifiers: UInt32(controlKey | optionKey), keyName: "D"))
var event: EventRef?
var identifier = EventHotKeyID(signature: 0x444F5A52, id: 2)
if CreateEvent(nil, OSType(kEventClassKeyboard), UInt32(kEventHotKeyPressed), 0, 0, &event) == noErr,
   let event {
    SetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID),
                      MemoryLayout<EventHotKeyID>.size, &identifier)
    SendEventToEventTarget(event, GetApplicationEventTarget())
    ReleaseEvent(event)
}
check(hotkeyActivations == 1, "Carbon hotkey event reaches toggle handler")

icons.prepareForTermination()
settle()
check(onscreen(sentinel), "termination restores test item")
NSStatusBar.system.removeStatusItem(sentinel)
icons.items.forEach { NSStatusBar.system.removeStatusItem($0.statusIcon) }
print("RESULT \(passed) passed, \(failures.count) failed")
if !failures.isEmpty { print("Failures: \(failures.joined(separator: ", "))") }
exit(failures.isEmpty ? 0 : 1)
}
app.run()
