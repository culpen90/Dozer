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
    private var pendingPlacements: [WindowIdentity: PendingPlacement] = [:]
    private var histories: [WindowHistory] = []
    private lazy var dragging = WindowDragManager(manager: self)
    private let defaults = UserDefaults.standard

    private struct WindowHistory {
        let target: ManagedWindowTarget
        var frames: [CGRect]
        var placementUnconfirmed = false
        var repeatState: WindowLayoutRepeatState?
    }

    private struct QueuedPlacement {
        let action: WindowLayoutAction
        let target: ManagedWindowTarget
        let screen: NSScreen?
        let restoreFrame: CGRect?
    }

    private struct WindowIdentity: Hashable {
        let target: ManagedWindowTarget
        static func == (lhs: Self, rhs: Self) -> Bool {
            lhs.target.processIdentifier == rhs.target.processIdentifier && CFEqual(lhs.target.element, rhs.target.element)
        }
        func hash(into hasher: inout Hasher) {
            hasher.combine(target.processIdentifier)
            hasher.combine(CFHash(target.element))
        }
    }

    private struct PendingPlacement {
        let generation: UInt64
        var queued: QueuedPlacement?
    }

    private struct PlacementResult {
        let generation: UInt64
        let action: WindowLayoutAction
        let layoutAction: WindowLayoutAction
        let target: ManagedWindowTarget
        let destination: CGRect
        let visibleFrame: CGRect
        let gap: CGFloat
        let restoring: Bool
        let resetsRepeat: Bool
        let baseline: CGRect
        let initialPosition: CGPoint
        var lastPosition: CGPoint
    }

    private init() {
        defaults.register(defaults: ["windowManagementEnabled": true,
                                     "windowDragSnappingEnabled": true,
                                     "windowGap": 8.0,
                                     "cycleRepeatedWindowLayouts": false])
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

    var cycleRepeatedLayouts: Bool {
        get { defaults.bool(forKey: "cycleRepeatedWindowLayouts") }
        set {
            defaults.set(newValue, forKey: "cycleRepeatedWindowLayouts")
            for index in histories.indices { histories[index].repeatState = nil }
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
        ) { [weak self] _ in
            self?.dragging.cancelDrag()
            self?.cancelPendingPlacement()
        }
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
        let identity = WindowIdentity(target: target)
        if var pending = pendingPlacements[identity] {
            // An immediate restore must wait until an asynchronous resize has
            // settled. Keep the latest requested action rather than race AX writes.
            pending.queued = QueuedPlacement(action: action, target: target, screen: screen, restoreFrame: restoreFrame)
            pendingPlacements[identity] = pending
            return
        }
        placementGeneration &+= 1
        let generation = placementGeneration
        guard isEligible(target), let current = frame(of: target), !NSScreen.screens.isEmpty else {
            report("This window cannot be arranged. Try a normal, non-full-screen window.")
            return
        }
        let previous = historyIndex(for: target).flatMap { histories[$0].repeatState }
        // Drag snapping always uses the explicit preview destination; only a
        // repeated menu, tile, or keyboard command participates in cycling.
        let layoutAction = WindowLayoutGeometry.repeatedAction(for: action, window: current,
                                      previous: previous, enabled: cycleRepeatedLayouts && restoreFrame == nil)
        let screens = NSScreen.screens
        let index = WindowLayoutGeometry.screenIndex(for: current, screens: screens.map(\.frame)) ?? 0
        let source = screen.flatMap { requested in screens.first(where: { $0 === requested }) } ?? screens[index]
        var destination: CGRect
        let destinationVisibleFrame: CGRect
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
            let restoredIndex = WindowLayoutGeometry.screenIndex(for: destination, screens: visibleFrames) ?? index
            destinationVisibleFrame = visibleFrames[restoredIndex]
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
            destinationVisibleFrame = next.visibleFrame
        default:
            guard let calculated = WindowLayoutGeometry.frame(for: layoutAction, window: current,
                                                               visibleFrame: source.visibleFrame, gap: gap) else { return }
            destination = calculated
            destinationVisibleFrame = source.visibleFrame
        }

        guard let feasible = WindowPlacementAdjustment.feasibleFrame(requested: destination,
                            minimumSize: minimumSize(of: target), visibleFrame: destinationVisibleFrame,
                            gap: restoring ? 0 : gap) else {
            report("The display layout is unavailable. Try again after the display reconnects.")
            return
        }
        destination = feasible
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
                guard !histories[historyIndex].placementUnconfirmed else {
                    report("The earlier window adjustment has not settled. Try Restore again.")
                    return
                }
                histories[historyIndex].frames.removeLast()
            } else if let restoreFrame, !framesMatch(restoreFrame, current) {
                remember(restoreFrame, for: target)
            }
            recordRepeat(action, layoutAction: layoutAction, target: target, frame: current, restoring: restoring || restoreFrame != nil)
            report("\(layoutAction.title) · \(target.applicationName)")
            return
        }

        let baseline = restoreFrame ?? current
        // Capture the original before issuing AX writes. Some applications apply
        // them asynchronously; the window must remain recoverable in the meantime.
        if !restoring { remember(baseline, for: target) }
        if let index = historyIndex(for: target) {
            histories[index].placementUnconfirmed = true
            histories[index].repeatState = nil
        }
        let edgeGap: CGFloat = restoring ? 0 : gap
        // Each window settles independently. Commands for another window must
        // not discard this window's queued restore or its history update.
        pendingPlacements[identity] = PendingPlacement(generation: generation)
        var result = PlacementResult(generation: generation, action: action, layoutAction: layoutAction, target: target,
                                     destination: destination, visibleFrame: destinationVisibleFrame,
                                     gap: edgeGap, restoring: restoring, resetsRepeat: restoreFrame != nil, baseline: baseline,
                                     initialPosition: CGPoint(x: current.minX, y: current.maxY),
                                     lastPosition: CGPoint(x: current.minX, y: current.maxY))
        if changesSize {
            // Follow upstream's immediate placement without redundant writes,
            // then retain staged recovery for deferred or constrained AX writes.
            let immediate = setFrame(destination, before: current, visibleFrame: destinationVisibleFrame,
                                     gap: edgeGap, of: target)
            if let moved = immediate.lastPositionFrame {
                result.lastPosition = CGPoint(x: moved.minX, y: moved.maxY)
            }
            if let actual = frame(of: target), framesMatch(actual, destination, tolerance: 3) {
                pendingPlacements.removeValue(forKey: identity)
                finishPlacement(action, layoutAction: layoutAction, target: target, restoring: restoring, resetRepeat: restoreFrame != nil)
                return
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [weak self] in
                self?.moveAfterResize(result)
            }
            return
        }
        _ = setPosition(destination, of: target)
        result.lastPosition = CGPoint(x: destination.minX, y: destination.maxY)
        if let actual = frame(of: target), framesMatch(actual, destination, tolerance: 3) {
            pendingPlacements.removeValue(forKey: identity)
            finishPlacement(action, layoutAction: layoutAction, target: target, restoring: restoring, resetRepeat: restoreFrame != nil)
            return
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [weak self] in
            self?.settlePlacement(result, remainingPolls: 4, correctionAttempts: 2)
        }
    }

    private func moveAfterResize(_ result: PlacementResult) {
        let identity = WindowIdentity(target: result.target)
        guard pendingPlacements[identity]?.generation == result.generation else { return }
        guard let actual = frame(of: result.target), positionIsOurs(actual, result: result) else {
            settlePlacement(result, remainingPolls: 0, correctionAttempts: 0)
            return
        }
        _ = setPosition(result.destination, of: result.target)
        var moved = result
        moved.lastPosition = CGPoint(x: result.destination.minX, y: result.destination.maxY)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [weak self] in
            self?.resizeAfterMove(moved, movementRetries: 1)
        }
    }

    private func resizeAfterMove(_ result: PlacementResult, movementRetries: Int) {
        let identity = WindowIdentity(target: result.target)
        guard pendingPlacements[identity]?.generation == result.generation else { return }
        guard let actual = frame(of: result.target), positionIsOurs(actual, result: result) else {
            settlePlacement(result, remainingPolls: 0, correctionAttempts: 0)
            return
        }
        if !positionMatches(actual, result.lastPosition), movementRetries > 0 {
            // The first move may still have coincided with the resize ending.
            // Retry only from the original or already-issued position.
            _ = setPosition(result.destination, of: result.target)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [weak self] in
                self?.resizeAfterMove(result, movementRetries: movementRetries - 1)
            }
            return
        }
        if positionMatches(actual, result.lastPosition) {
            // At the destination origin a size clipped by the previous screen
            // edge can now grow to the full requested dimensions.
            _ = setSize(result.destination.size, of: result.target)
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [weak self] in
            self?.settlePlacement(result, remainingPolls: 4, correctionAttempts: 2)
        }
    }

    private func positionMatches(_ frame: CGRect, _ position: CGPoint) -> Bool {
        abs(frame.minX - position.x) <= 3 && abs(frame.maxY - position.y) <= 3
    }

    private func positionIsOurs(_ frame: CGRect, result: PlacementResult) -> Bool {
        positionMatches(frame, result.lastPosition) || positionMatches(frame, result.initialPosition)
    }

    private func settlePlacement(_ result: PlacementResult, remainingPolls: Int, correctionAttempts: Int) {
        let identity = WindowIdentity(target: result.target)
        guard pendingPlacements[identity]?.generation == result.generation else { return }
        let actual = frame(of: result.target)
        let succeeded = actual.map { framesMatch($0, result.destination, tolerance: 3) } ?? false
        if !succeeded, correctionAttempts > 0, let actual,
           positionIsOurs(actual, result: result),
           let fitted = sizesMatch(actual.size, result.destination.size) ? result.destination
                : WindowLayoutGeometry.constrainedFrame(requested: result.destination,
                                     actualSize: actual.size, visibleFrame: result.visibleFrame, gap: result.gap),
           !framesMatch(actual, fitted) {
            // A rejected or clamped size can leave the requested origin outside
            // the usable display. Position the accepted size, then let that AX
            // write settle before a queued action starts using its frame.
            _ = setPosition(fitted, of: result.target)
            var corrected = result
            corrected.lastPosition = CGPoint(x: fitted.minX, y: fitted.maxY)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [weak self] in
                self?.settlePlacement(corrected, remainingPolls: remainingPolls,
                                       correctionAttempts: correctionAttempts - 1)
            }
            return
        }
        if !succeeded, remainingPolls > 0 {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [weak self] in
                self?.settlePlacement(result, remainingPolls: remainingPolls - 1,
                                       correctionAttempts: correctionAttempts)
            }
            return
        }
        let queued = pendingPlacements.removeValue(forKey: identity)?.queued
        if succeeded {
            finishPlacement(result.action, layoutAction: result.layoutAction, target: result.target, restoring: result.restoring, resetRepeat: result.resetsRepeat,
                            reportResult: result.generation == placementGeneration)
        } else if result.generation == placementGeneration {
            // Keep the baseline even if AX still reports the old frame: an
            // acknowledged toolkit write can apply after this observation.
            // A failed restore also retains its desired history entry for retry.
            report("\(result.target.applicationName) limited the requested size or position.")
        }
        if !succeeded, let actual, !framesMatch(actual, result.baseline),
           let index = historyIndex(for: result.target) {
            histories[index].placementUnconfirmed = false
        }
        if let queued {
            execute(queued.action, target: queued.target, screen: queued.screen, restoreFrame: queued.restoreFrame)
        }
    }

    func focusedWindow(in app: NSRunningApplication) -> ManagedWindowTarget? {
        guard app.processIdentifier != ProcessInfo.processInfo.processIdentifier, !app.isTerminated else { return nil }
        let application = AXUIElementCreateApplication(app.processIdentifier)
        AXUIElementSetMessagingTimeout(application, 0.25)
        var windowValue = copyAttribute(kAXFocusedWindowAttribute, from: application)
        if windowValue.map({ CFGetTypeID($0) != AXUIElementGetTypeID() }) ?? true {
            // A selected background application may expose only its main window.
            // The fallback stays within that application; it never selects the
            // frontmost window belonging to some other process.
            windowValue = copyAttribute(kAXMainWindowAttribute, from: application)
        }
        guard let windowValue, CFGetTypeID(windowValue) == AXUIElementGetTypeID() else { return nil }
        let element = windowValue as! AXUIElement
        var windowPID: pid_t = 0
        guard AXUIElementGetPid(element, &windowPID) == .success,
              windowPID == app.processIdentifier else { return nil }
        let target = ManagedWindowTarget(element: element,
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
            if WindowAccessibilityClassification.isWindow(role: copyAttribute(kAXRoleAttribute, from: element) as? String,
                                                           subrole: copyAttribute(kAXSubroleAttribute, from: element) as? String) {
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
              WindowAccessibilityClassification.isWindow(role: copyAttribute(kAXRoleAttribute, from: target.element) as? String,
                                                         subrole: subrole),
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

    private func minimumSize(of target: ManagedWindowTarget) -> CGSize? {
        // Rectangle supports both toolkit spellings of the AX minimum-size attribute.
        for attribute in ["AXMinSize", "AXMinimumSize"] {
            guard let value = copyAttribute(attribute, from: target.element),
                  CFGetTypeID(value) == AXValueGetTypeID() else { continue }
            let wrapped = value as! AXValue
            guard AXValueGetType(wrapped) == .cgSize else { continue }
            var size = CGSize.zero
            if AXValueGetValue(wrapped, .cgSize, &size) { return size }
        }
        return nil
    }

    private func setFrame(_ frame: CGRect, before: CGRect, visibleFrame: CGRect,
                          gap: CGFloat, of target: ManagedWindowTarget) -> WindowPlacementAdjustment.Result {
        RectangleWindowAdjustment.perform(for: target.element) {
            WindowPlacementAdjustment.perform(requested: frame, before: before, visibleFrame: visibleFrame, gap: gap,
                readFrame: { self.frame(of: target) },
                resize: { self.setSizeDirectly($0, of: target) },
                move: { self.setPositionDirectly($0, of: target) })
        }
    }

    private func setSize(_ requestedSize: CGSize, of target: ManagedWindowTarget) -> Bool {
        RectangleWindowAdjustment.perform(for: target.element) {
            setSizeDirectly(requestedSize, of: target)
        }
    }

    private func setSizeDirectly(_ requestedSize: CGSize, of target: ManagedWindowTarget) -> Bool {
        var size = requestedSize
        guard let dimensions = AXValueCreate(.cgSize, &size) else { return false }
        return AXUIElementSetAttributeValue(target.element, kAXSizeAttribute as CFString, dimensions) == .success
    }

    private func setPosition(_ frame: CGRect, of target: ManagedWindowTarget) -> Bool {
        RectangleWindowAdjustment.perform(for: target.element) {
            setPositionDirectly(frame, of: target)
        }
    }

    private func setPositionDirectly(_ frame: CGRect, of target: ManagedWindowTarget) -> Bool {
        var point = CGPoint(x: frame.minX, y: desktopTop - frame.maxY)
        guard let position = AXValueCreate(.cgPoint, &point) else { return false }
        return AXUIElementSetAttributeValue(target.element, kAXPositionAttribute as CFString, position) == .success
    }

    private func sizesMatch(_ lhs: CGSize, _ rhs: CGSize, tolerance: CGFloat = 1) -> Bool {
        abs(lhs.width - rhs.width) <= tolerance && abs(lhs.height - rhs.height) <= tolerance
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
        pendingPlacements.removeAll()
        for index in histories.indices { histories[index].repeatState = nil }
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

    private func recordRepeat(_ action: WindowLayoutAction, layoutAction: WindowLayoutAction,
                              target: ManagedWindowTarget, frame: CGRect, restoring: Bool) {
        if historyIndex(for: target) == nil {
            histories.append(WindowHistory(target: target, frames: []))
            if histories.count > 40 { histories.removeFirst() }
        }
        if let index = historyIndex(for: target) {
            histories[index].repeatState = restoring ? nil : WindowLayoutRepeatState(command: action, layout: layoutAction, frame: frame)
        }
    }

    private func finishPlacement(_ action: WindowLayoutAction, layoutAction: WindowLayoutAction,
                                 target: ManagedWindowTarget, restoring: Bool, resetRepeat: Bool = false,
                                 reportResult: Bool = true) {
        if let index = historyIndex(for: target) { histories[index].placementUnconfirmed = false }
        if restoring, let index = historyIndex(for: target), !histories[index].frames.isEmpty {
            histories[index].frames.removeLast()
        }
        if let actual = frame(of: target) {
            recordRepeat(action, layoutAction: layoutAction, target: target, frame: actual, restoring: restoring || resetRepeat)
        }
        if reportResult { report("\(layoutAction.title) · \(target.applicationName)") }
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
