// Explicitly authorized native input for the disposable fixture only.
// Usage: RunWindowInputCheck.sh --pid N --action shortcut-left|drag-left|option-drag-left --allow-native-input
import AppKit
import ApplicationServices

struct InputCheckError: Error, CustomStringConvertible { let description: String }
func require(_ condition: @autoclosure () -> Bool, _ message: String) throws {
    if !condition() { throw InputCheckError(description: message) }
}
func pause(_ seconds: TimeInterval) { RunLoop.current.run(until: Date().addingTimeInterval(seconds)) }
func frameDictionary(_ value: Any?) throws -> CGRect {
    guard let value = value as? [String: NSNumber], let x = value["x"]?.doubleValue,
          let y = value["y"]?.doubleValue, let width = value["width"]?.doubleValue,
          let height = value["height"]?.doubleValue,
          [x, y, width, height].allSatisfy(\.isFinite), width > 0, height > 0 else {
        throw InputCheckError(description: "Fixture frame log has invalid geometry.")
    }
    return CGRect(x: x, y: y, width: width, height: height)
}

func run() throws {
    let args = Array(CommandLine.arguments.dropFirst())
    try require(args.contains("--allow-native-input"), "Refusing native input without --allow-native-input.")
    var values: [String: String] = [:]
    var index = 0
    while index < args.count {
        if args[index] == "--allow-native-input" { index += 1; continue }
        try require(["--pid", "--action"].contains(args[index]) && index + 1 < args.count,
                    "Usage: --pid N --action shortcut-left|drag-left|option-drag-left --allow-native-input")
        try require(values[args[index]] == nil, "Duplicate argument: \(args[index])")
        values[args[index]] = args[index + 1]
        index += 2
    }
    guard let pidText = values["--pid"], let pid = Int32(pidText), pid > 0,
          let action = values["--action"], ["shortcut-left", "drag-left", "option-drag-left"].contains(action),
          let fixture = NSRunningApplication(processIdentifier: pid) else {
        throw InputCheckError(description: "Provide the running fixture PID and a supported action.")
    }
    let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        .deletingLastPathComponent().deletingLastPathComponent().resolvingSymlinksInPath().path
    let expectedExecutable = root + "/build/DozerWindowFixture.app/Contents/MacOS/DozerWindowFixture"
    try require(fixture.bundleIdentifier == "local.Dozer.WindowFixture" &&
                fixture.executableURL?.resolvingSymlinksInPath().path == expectedExecutable && !fixture.isTerminated,
                "Refusing input: target is not the disposable Dozer window fixture.")
    let logData = try Data(contentsOf: URL(fileURLWithPath: root + "/build/window-fixture-frame.json"))
    guard let log = try JSONSerialization.jsonObject(with: logData) as? [String: Any],
          (log["pid"] as? NSNumber)?.int32Value == pid,
          log["isVisible"] as? Bool == true, log["isMiniaturized"] as? Bool == false,
          let number = log["windowNumber"] as? NSNumber, number.int64Value > 0,
          number.uint64Value <= UInt64(UInt32.max) else {
        throw InputCheckError(description: "Frame log must identify this visible, non-minimized fixture.")
    }
    let frame = try frameDictionary(log["frame"])
    let screen = try frameDictionary(log["screenFrame"])
    let quartz = try frameDictionary(log["accessibilityFrame"])
    let windowID = CGWindowID(number.uint32Value)
    func verifyFixtureWindow() throws {
        guard !fixture.isTerminated,
              let windows = CGWindowListCopyWindowInfo(.optionIncludingWindow, windowID) as? [[String: Any]],
              let own = windows.first(where: { ($0[kCGWindowNumber as String] as? NSNumber)?.uint32Value == windowID }),
              (own[kCGWindowOwnerPID as String] as? NSNumber)?.int32Value == pid,
              (own[kCGWindowIsOnscreen as String] as? Bool) == true,
              let bounds = own[kCGWindowBounds as String] as? [String: Any],
              let actual = CGRect(dictionaryRepresentation: bounds as CFDictionary) else {
            throw InputCheckError(description: "The fixture's logged window is no longer visible.")
        }
        try require(abs(actual.minX - quartz.minX) < 3 && abs(actual.minY - quartz.minY) < 3 &&
                    abs(actual.width - quartz.width) < 3 && abs(actual.height - quartz.height) < 3,
                    "Fixture moved after its frame log was read; retry with current geometry.")
    }
    try verifyFixtureWindow()
    try require(CGPreflightPostEventAccess(), "Native event posting is unavailable; permission was not requested.")
    let held = CGEventSource.flagsState(.hidSystemState)
    try require(held.intersection([.maskControl, .maskAlternate, .maskCommand, .maskShift]).isEmpty &&
                NSEvent.pressedMouseButtons == 0, "Release modifier keys and mouse buttons before this check.")
    _ = NSApplication.shared
    fixture.activate(options: [.activateIgnoringOtherApps])
    pause(0.4)
    func verifyFrontmost() throws {
        try require(NSWorkspace.shared.frontmostApplication?.processIdentifier == pid && !fixture.isTerminated,
                    "Fixture lost focus; aborting native input.")
    }
    try verifyFrontmost()
    try verifyFixtureWindow()
    try require(NSEvent.pressedMouseButtons == 0 &&
                CGEventSource.flagsState(.hidSystemState).intersection([.maskControl, .maskAlternate, .maskCommand, .maskShift]).isEmpty,
                "Physical input began during activation; aborting this check.")
    // Apple CGEventSource.h recommends the combined table for a login-session
    // injector; the HID-only table is intended for hardware drivers and daemons.
    guard let source = CGEventSource(stateID: .combinedSessionState), let originalCursor = CGEvent(source: nil)?.location else {
        throw InputCheckError(description: "Cannot create a native event source.")
    }
    var pressedKeys: [CGKeyCode] = []
    var mouseHeld = false
    var lastPoint = originalCursor
    var postedInput = false
    func key(_ code: CGKeyCode, down: Bool, flags: CGEventFlags) throws {
        guard let event = CGEvent(keyboardEventSource: source, virtualKey: code, keyDown: down) else {
            throw InputCheckError(description: "Cannot create a keyboard event.")
        }
        // Preserve the event constructor's native Fn/numeric-pad/device flags.
        // Replacing the entire mask would turn an arrow into a non-native event.
        event.flags = event.flags.subtracting([.maskControl, .maskAlternate, .maskCommand, .maskShift]).union(flags)
        if down { pressedKeys.append(code) } else { pressedKeys.removeAll { $0 == code } }
        event.post(tap: .cghidEventTap)
        postedInput = true
    }
    func mouse(_ type: CGEventType, at point: CGPoint, flags: CGEventFlags = []) throws {
        guard let event = CGEvent(mouseEventSource: source, mouseType: type, mouseCursorPosition: point, mouseButton: .left) else {
            throw InputCheckError(description: "Cannot create a mouse event.")
        }
        event.flags = flags
        if type == .leftMouseDown { mouseHeld = true }
        if type == .leftMouseUp { mouseHeld = false }
        lastPoint = point
        event.post(tap: .cghidEventTap)
        postedInput = true
    }
    func previewWindowIDs() -> [CGWindowID] {
        let dozerPIDs = Set(NSRunningApplication.runningApplications(withBundleIdentifier: "com.mortennn.Dozer").map(\.processIdentifier))
        let windows = CGWindowListCopyWindowInfo(.optionOnScreenOnly, kCGNullWindowID) as? [[String: Any]] ?? []
        let visible = NSScreen.screens.first(where: { $0.frame == screen })?.visibleFrame
            ?? (try? frameDictionary(log["visibleFrame"])) ?? screen
        let savedGap = (UserDefaults(suiteName: "com.mortennn.Dozer")?.object(forKey: "windowGap") as? NSNumber)?.doubleValue ?? 8
        let gap = savedGap.isFinite ? CGFloat(min(30, max(0, savedGap))) : 8
        let appKit = CGRect(x: visible.minX + gap, y: visible.minY + gap,
                            width: floor(visible.width / 2) - gap * 1.5, height: visible.height - 2 * gap).insetBy(dx: 2, dy: 2)
        let expected = CGRect(x: appKit.minX, y: (NSScreen.screens.first?.frame.maxY ?? 0) - appKit.maxY,
                              width: appKit.width, height: appKit.height)
        return windows.compactMap {
            guard let pid = ($0[kCGWindowOwnerPID as String] as? NSNumber)?.int32Value,
                  dozerPIDs.contains(pid), ($0[kCGWindowLayer as String] as? NSNumber)?.intValue == 3,
                  let bounds = $0[kCGWindowBounds as String] as? [String: Any],
                  let actual = CGRect(dictionaryRepresentation: bounds as CFDictionary),
                  abs(actual.minX - expected.minX) <= 4, abs(actual.minY - expected.minY) <= 4,
                  abs(actual.width - expected.width) <= 4, abs(actual.height - expected.height) <= 4 else { return nil }
            return ($0[kCGWindowNumber as String] as? NSNumber).map { CGWindowID($0.uint32Value) }
        }
    }
    defer {
        if mouseHeld { try? mouse(.leftMouseUp, at: lastPoint) }
        for code in pressedKeys.reversed() {
            let event = CGEvent(keyboardEventSource: source, virtualKey: code, keyDown: false)
            event?.flags = []
            event?.post(tap: .cghidEventTap)
        }
        if postedInput { pause(1); try? mouse(.mouseMoved, at: originalCursor) }
    }
    if action == "shortcut-left" {
        try verifyFrontmost()
        try key(59, down: true, flags: .maskControl); pause(0.04)
        try key(58, down: true, flags: [.maskControl, .maskAlternate]); pause(0.04)
        try verifyFrontmost()
        try key(123, down: true, flags: [.maskControl, .maskAlternate]); pause(0.08)
        try key(123, down: false, flags: [.maskControl, .maskAlternate])
        try key(58, down: false, flags: .maskControl)
        try key(59, down: false, flags: [])
        print("Posted native Control–Option–Left to fixture PID \(pid).")
    } else {
        let top = NSScreen.screens.first?.frame.maxY ?? 0
        let start = CGPoint(x: frame.midX, y: top - frame.maxY + 15)
        let end = CGPoint(x: screen.minX + 2, y: top - screen.midY)
        let bypass = action == "option-drag-left"
        let flags: CGEventFlags = bypass ? .maskAlternate : []
        if bypass { try key(58, down: true, flags: flags); pause(0.05) }
        try mouse(.mouseMoved, at: start, flags: flags); pause(0.08)
        try verifyFrontmost()
        try mouse(.leftMouseDown, at: start, flags: flags); pause(0.08)
        for step in 1...30 {
            try verifyFrontmost()
            let fraction = CGFloat(step) / 30
            try mouse(.leftMouseDragged, at: CGPoint(x: start.x + (end.x - start.x) * fraction,
                                                    y: start.y + (end.y - start.y) * fraction), flags: flags)
            pause(0.02)
        }
        pause(0.3)
        try verifyFrontmost()
        let previewIDs = previewWindowIDs()
        print("previewPresent: \(!previewIDs.isEmpty)")
        try mouse(.leftMouseUp, at: end, flags: flags)
        if bypass { try key(58, down: false, flags: []) }
        pause(0.3)
        let visibleIDs = Set(previewWindowIDs())
        print("previewAfterRelease: \(previewIDs.contains(where: visibleIDs.contains))")
        print("Posted native fixture titlebar drag to left edge\(bypass ? " with Option held" : ""); PID \(pid).")
    }
}

do { try run() } catch {
    FileHandle.standardError.write(Data("Window input check: \(error)\n".utf8))
    exit(1)
}
