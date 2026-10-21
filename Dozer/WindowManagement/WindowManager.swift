/* This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. https://mozilla.org/MPL/2.0/ */

import AppKit
import ApplicationServices

extension Notification.Name {
    static let dozerWindowStateChanged = Notification.Name("DozerWindowStateChanged")
}

/// An Accessibility window reference remains tied to its original application.
/// Dragging and delayed UI actions must never fall back to a different window.
struct ManagedWindowTarget {
    let element: AXUIElement
    let processIdentifier: pid_t
    let applicationName: String
}

final class WindowManager {
    static let shared = WindowManager()

    private(set) var isTrusted = AXIsProcessTrusted()
    private(set) var lastMessage: String?
    private var lastExternalApplication: NSRunningApplication?
    private var workspaceObserver: NSObjectProtocol?
    private var screenObserver: NSObjectProtocol?
    private var activeObserver: NSObjectProtocol?
    private var permissionTimer: Timer?
    private var started = false
    private var placementGeneration: UInt64 = 0
    private var pendingTarget: ManagedWindowTarget?
    private var queuedPlacement: QueuedPlacement?
    private var histories: [WindowHistory] = []
    private lazy var dragging = WindowDragManager(manager: self)
    private let defaults = UserDefaults.standard

    private struct WindowHistory {
        let target: ManagedWindowTarget
        var frames: [CGRect]
    }

    private struct QueuedPlacement {
        let action: WindowLayoutAction
        let target: ManagedWindowTarget
        let screen: NSScreen?
        let restoreFrame: CGRect?
    }

    private init() {
        defaults.register(defaults: ["windowManagementEnabled": true,
                                     "windowDragSnappingEnabled": true,
                                     "windowGap": 8.0])
    }

    var isEnabled: Bool {
        get { defaults.bool(forKey: "windowManagementEnabled") }
        set {
            defaults.set(newValue, forKey: "windowManagementEnabled")
            if !newValue { cancelPendingPlacement() }
            updateDragging()
            publish()
        }
    }

    var dragSnappingEnabled: Bool {
        get { defaults.bool(forKey: "windowDragSnappingEnabled") }
        set {
            defaults.set(newValue, forKey: "windowDragSnappingEnabled")
            updateDragging()
            publish()
        }
    }

    var gap: CGFloat {
        get {
            let value = defaults.double(forKey: "windowGap")
            return value.isFinite ? CGFloat(min(30, max(0, value))) : 8
        }
        set {
            let value = newValue.isFinite ? min(30, max(0, newValue)) : 8
            defaults.set(Double(value), forKey: "windowGap")
            dragging.cancelDrag()
            publish()
        }
    }

    var targetApplicationName: String? {
        let app = targetApplication
        return app?.localizedName
    }

    private var targetApplication: NSRunningApplication? {
        if let frontmost = NSWorkspace.shared.frontmostApplication,
           frontmost.processIdentifier != ProcessInfo.processInfo.processIdentifier,
           !frontmost.isTerminated {
            return frontmost
        }
        guard let previous = lastExternalApplication, !previous.isTerminated else { return nil }
        return previous
    }

    func start() {
        guard !started else { return }
        started = true
        rememberExternalApplication(NSWorkspace.shared.frontmostApplication)
        workspaceObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main
        ) { [weak self] notification in
            self?.rememberExternalApplication(notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication)
            self?.publish()
        }
        screenObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main
        ) { [weak self] _ in self?.dragging.cancelDrag() }
        activeObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main
        ) { [weak self] _ in self?.refreshPermission() }
        permissionTimer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
            self?.refreshPermission()
        }
        permissionTimer?.tolerance = 0.5
        refreshPermission()
        updateDragging()
    }

    func stop() {
        started = false
        cancelPendingPlacement()
        dragging.stop()
        permissionTimer?.invalidate()
        permissionTimer = nil
        if let workspaceObserver { NSWorkspace.shared.notificationCenter.removeObserver(workspaceObserver) }
        if let screenObserver { NotificationCenter.default.removeObserver(screenObserver) }
        if let activeObserver { NotificationCenter.default.removeObserver(activeObserver) }
        workspaceObserver = nil
        screenObserver = nil
        activeObserver = nil
        histories.removeAll()
    }

    func refreshPermission() {
        let trusted = AXIsProcessTrusted()
        guard trusted != isTrusted else { return }
        isTrusted = trusted
        if !trusted {
            cancelPendingPlacement()
            lastMessage = "Allow Dozer in Accessibility to arrange windows."
        }
        else { lastMessage = "Window management is ready." }
        updateDragging()
        publish()
    }

    /// Called only from an explicit permission button in the user interface.
    func requestPermission() {
        _ = AXIsProcessTrustedWithOptions([kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary)
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
        refreshPermission()
    }

    func execute(_ action: WindowLayoutAction) {
        guard readyToArrange() else { return }
        guard let app = targetApplication, let target = focusedWindow(in: app) else {
            report("Select a normal application window, then try again.")
            return
        }
        if NSWorkspace.shared.frontmostApplication?.processIdentifier == ProcessInfo.processInfo.processIdentifier {
            app.activate(options: [.activateIgnoringOtherApps])
        }
        execute(action, target: target)
    }

    /// Used by drag snapping and fixture checks to preserve the chosen window.
    func execute(_ action: WindowLayoutAction, target: ManagedWindowTarget, screen: NSScreen? = nil,
                 restoreFrame: CGRect? = nil) {
        guard readyToArrange() else { return }
        if let pendingTarget, sameWindow(pendingTarget, target) {
            // An immediate restore must wait until an asynchronous resize has
            // settled. Keep the latest requested action rather than race AX writes.
            queuedPlacement = QueuedPlacement(action: action, target: target, screen: screen, restoreFrame: restoreFrame)
            return
        }
        pendingTarget = nil
        queuedPlacement = nil
        placementGeneration &+= 1
        let generation = placementGeneration
        guard isEligible(target), let current = frame(of: target), !NSScreen.screens.isEmpty else {
            report("This window cannot be arranged. Try a normal, non-full-screen window.")
            return
        }
        let screens = NSScreen.screens
        let index = WindowLayoutGeometry.screenIndex(for: current, screens: screens.map(\.frame)) ?? 0
        let source = screen.flatMap { requested in screens.first(where: { $0 === requested }) } ?? screens[index]
        let destination: CGRect
        var restoring = false
        switch action {
        case .restore:
            guard let historyIndex = historyIndex(for: target),
                  let previous = histories[historyIndex].frames.last else {
                report("No earlier arrangement to restore for this window.")
                return
            }
            // A disconnected display should not strand the restored window off screen.
            let visibleFrames = screens.map(\.visibleFrame)
            let titleBar = CGRect(x: previous.minX, y: previous.maxY - 30, width: previous.width, height: 30)
            if visibleFrames.contains(where: { $0.intersection(titleBar).width >= 80 && $0.intersection(titleBar).height >= 15 }) {
                destination = previous
            } else {
                destination = WindowLayoutGeometry.frame(for: .center, window: previous,
                                                          visibleFrame: source.visibleFrame, gap: 0) ?? source.visibleFrame
            }
            restoring = true
        case .nextDisplay, .previousDisplay:
            guard screens.count > 1 else {
                report("Connect another display to move this window between screens.")
                return
            }
            let offset = action == .nextDisplay ? 1 : screens.count - 1
            let next = screens[(index + offset) % screens.count]
            destination = WindowLayoutGeometry.movedFrame(window: current,
                                                          from: screens[index].visibleFrame,
                                                          to: next.visibleFrame, gap: gap)
        default:
            guard let calculated = WindowLayoutGeometry.frame(for: action, window: current,
                                                               visibleFrame: source.visibleFrame, gap: gap) else { return }
            destination = calculated
        }

        guard destination.width > 0, destination.height > 0,
              [destination.minX, destination.minY, destination.width, destination.height].allSatisfy(\.isFinite) else {
            report("The display layout is unavailable. Try again after the display reconnects.")
            return
        }
        let changesSize = abs(current.width - destination.width) > 1 || abs(current.height - destination.height) > 1
        if changesSize && !isSettable(kAXSizeAttribute, on: target.element) {
            report("\(target.applicationName) does not allow this window to resize.")
            return
        }
        guard isSettable(kAXPositionAttribute, on: target.element) else {
            report("\(target.applicationName) does not allow this window to move.")
            return
        }
        if framesMatch(current, destination) {
            if restoring, let historyIndex = historyIndex(for: target) {
                histories[historyIndex].frames.removeLast()
            } else if let restoreFrame, !framesMatch(restoreFrame, current) {
                remember(restoreFrame, for: target)
            }
            report("\(action.title) · \(target.applicationName)")
            return
        }

        let baseline = restoreFrame ?? current
        // Capture the original before issuing AX writes. Some applications apply
        // them asynchronously; the window must remain recoverable in the meantime.
        let appendedHistory = !restoring && remember(baseline, for: target)
        _ = setFrame(destination, of: target, resize: changesSize)
        if let actual = frame(of: target), framesMatch(actual, destination, tolerance: 3) {
            finishPlacement(action, target: target, restoring: restoring)
            return
        }
        // AX setters can acknowledge before a toolkit updates its reported frame.
        // A newer command owns the status message and history once it is issued.
        pendingTarget = target
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [weak self] in
            guard let self, self.placementGeneration == generation else { return }
            self.pendingTarget = nil
            if let actual = self.frame(of: target), self.framesMatch(actual, destination, tolerance: 3) {
                self.finishPlacement(action, target: target, restoring: restoring)
            } else {
                if appendedHistory, let actual = self.frame(of: target),
                   self.framesMatch(actual, baseline), let index = self.historyIndex(for: target),
                   self.histories[index].frames.last == baseline {
                    self.histories[index].frames.removeLast()
                }
                // A partial restore keeps its original history entry so retrying
                // restore never replaces the desired frame with a partial result.
                self.report("\(target.applicationName) limited the requested size or position.")
            }
            if let next = self.queuedPlacement {
                self.queuedPlacement = nil
                self.execute(next.action, target: next.target, screen: next.screen, restoreFrame: next.restoreFrame)
            }
        }
    }

    func focusedWindow(in app: NSRunningApplication) -> ManagedWindowTarget? {
        guard app.processIdentifier != ProcessInfo.processInfo.processIdentifier, !app.isTerminated else { return nil }
        let application = AXUIElementCreateApplication(app.processIdentifier)
        AXUIElementSetMessagingTimeout(application, 0.25)
        guard let value = copyAttribute(kAXFocusedWindowAttribute, from: application),
              CFGetTypeID(value) == AXUIElementGetTypeID() else { return nil }
        let target = ManagedWindowTarget(element: value as! AXUIElement,
                                         processIdentifier: app.processIdentifier,
                                         applicationName: app.localizedName ?? "Application")
        AXUIElementSetMessagingTimeout(target.element, 0.25)
        return isEligible(target) ? target : nil
    }

    func window(at point: CGPoint) -> ManagedWindowTarget? {
        guard isTrusted else { return nil }
        let system = AXUIElementCreateSystemWide()
        AXUIElementSetMessagingTimeout(system, 0.2)
        let position = accessibilityPoint(point)
        var hit: AXUIElement?
        guard AXUIElementCopyElementAtPosition(system, Float(position.x), Float(position.y), &hit) == .success,
              var element = hit else { return nil }
        for _ in 0..<16 {
            if copyAttribute(kAXRoleAttribute, from: element) as? String == kAXWindowRole {
                var pid: pid_t = 0
                guard AXUIElementGetPid(element, &pid) == .success,
                      pid != ProcessInfo.processInfo.processIdentifier,
                      let app = NSRunningApplication(processIdentifier: pid), !app.isTerminated else { return nil }
                AXUIElementSetMessagingTimeout(element, 0.2)
                let target = ManagedWindowTarget(element: element, processIdentifier: pid,
                                                 applicationName: app.localizedName ?? "Application")
                return isEligible(target) ? target : nil
            }
            guard let parent = copyAttribute(kAXParentAttribute, from: element),
                  CFGetTypeID(parent) == AXUIElementGetTypeID() else { return nil }
            element = parent as! AXUIElement
        }
        return nil
    }

    func isEligible(_ target: ManagedWindowTarget) -> Bool {
        let subrole = copyAttribute(kAXSubroleAttribute, from: target.element) as? String
        guard let app = NSRunningApplication(processIdentifier: target.processIdentifier),
              !app.isTerminated, target.processIdentifier != ProcessInfo.processInfo.processIdentifier,
              copyAttribute(kAXRoleAttribute, from: target.element) as? String == kAXWindowRole,
              subrole == nil || subrole == kAXStandardWindowSubrole,
              (copyAttribute(kAXMinimizedAttribute, from: target.element) as? Bool) != true,
              (copyAttribute("AXFullScreen", from: target.element) as? Bool) != true else { return false }
        return frame(of: target) != nil
    }

    func frame(of target: ManagedWindowTarget) -> CGRect? {
        guard let positionValue = copyAttribute(kAXPositionAttribute, from: target.element),
              let sizeValue = copyAttribute(kAXSizeAttribute, from: target.element),
              CFGetTypeID(positionValue) == AXValueGetTypeID(), CFGetTypeID(sizeValue) == AXValueGetTypeID() else { return nil }
        let axPosition = positionValue as! AXValue
        let axSize = sizeValue as! AXValue
        guard AXValueGetType(axPosition) == .cgPoint, AXValueGetType(axSize) == .cgSize else { return nil }
        var point = CGPoint.zero
        var size = CGSize.zero
        guard AXValueGetValue(axPosition, .cgPoint, &point), AXValueGetValue(axSize, .cgSize, &size),
              size.width > 0, size.height > 0,
              [point.x, point.y, size.width, size.height].allSatisfy(\.isFinite) else { return nil }
        return CGRect(x: point.x, y: desktopTop - point.y - size.height, width: size.width, height: size.height)
    }

    private var desktopTop: CGFloat { NSScreen.screens.first?.frame.maxY ?? 0 }
    private func accessibilityPoint(_ point: CGPoint) -> CGPoint { CGPoint(x: point.x, y: desktopTop - point.y) }

    private func setFrame(_ frame: CGRect, of target: ManagedWindowTarget, resize: Bool) -> Bool {
        var point = CGPoint(x: frame.minX, y: desktopTop - frame.maxY)
        var size = frame.size
        guard let position = AXValueCreate(.cgPoint, &point), let dimensions = AXValueCreate(.cgSize, &size) else { return false }
        // Some applications constrain movement using their old size. Resize both
        // before and after positioning so a smaller destination screen works too.
        let firstResize = resize ? AXUIElementSetAttributeValue(target.element, kAXSizeAttribute as CFString, dimensions) : .success
        let movement = AXUIElementSetAttributeValue(target.element, kAXPositionAttribute as CFString, position)
        let secondResize = resize ? AXUIElementSetAttributeValue(target.element, kAXSizeAttribute as CFString, dimensions) : .success
        return firstResize == .success && movement == .success && secondResize == .success
    }

    private func copyAttribute(_ attribute: String, from element: AXUIElement) -> CFTypeRef? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success else { return nil }
        return value
    }

    private func isSettable(_ attribute: String, on element: AXUIElement) -> Bool {
        var settable = DarwinBoolean(false)
        return AXUIElementIsAttributeSettable(element, attribute as CFString, &settable) == .success && settable.boolValue
    }

    private func framesMatch(_ lhs: CGRect, _ rhs: CGRect, tolerance: CGFloat = 1) -> Bool {
        abs(lhs.minX - rhs.minX) <= tolerance && abs(lhs.minY - rhs.minY) <= tolerance &&
        abs(lhs.width - rhs.width) <= tolerance && abs(lhs.height - rhs.height) <= tolerance
    }

    private func historyIndex(for target: ManagedWindowTarget) -> Int? {
        histories.firstIndex { sameWindow($0.target, target) }
    }

    private func sameWindow(_ lhs: ManagedWindowTarget, _ rhs: ManagedWindowTarget) -> Bool {
        lhs.processIdentifier == rhs.processIdentifier && CFEqual(lhs.element, rhs.element)
    }

    private func cancelPendingPlacement() {
        placementGeneration &+= 1
        pendingTarget = nil
        queuedPlacement = nil
    }

    @discardableResult
    private func remember(_ frame: CGRect, for target: ManagedWindowTarget) -> Bool {
        if let index = historyIndex(for: target) {
            guard histories[index].frames.last != frame else { return false }
            histories[index].frames.append(frame)
            if histories[index].frames.count > 20 { histories[index].frames.removeFirst() }
        } else {
            histories.append(WindowHistory(target: target, frames: [frame]))
            if histories.count > 40 { histories.removeFirst() }
        }
        return true
    }

    private func finishPlacement(_ action: WindowLayoutAction, target: ManagedWindowTarget, restoring: Bool) {
        if restoring, let index = historyIndex(for: target), !histories[index].frames.isEmpty {
            histories[index].frames.removeLast()
        }
        report("\(action.title) · \(target.applicationName)")
    }

    private func readyToArrange() -> Bool {
        refreshPermission()
        guard isEnabled else { report("Turn on window management in Dozer’s Windows settings."); return false }
        guard isTrusted else { report("Allow Dozer in Accessibility to arrange windows."); return false }
        return true
    }

    private func rememberExternalApplication(_ app: NSRunningApplication?) {
        guard let app, app.processIdentifier != ProcessInfo.processInfo.processIdentifier,
              app.activationPolicy == .regular, !app.isTerminated else { return }
        lastExternalApplication = app
    }

    private func updateDragging() {
        if started && isTrusted && isEnabled && dragSnappingEnabled { dragging.start() }
        else { dragging.stop() }
    }

    private func report(_ message: String) { lastMessage = message; publish() }
    private func publish() { NotificationCenter.default.post(name: .dozerWindowStateChanged, object: self) }
}
