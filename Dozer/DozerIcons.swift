/* This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. https://mozilla.org/MPL/2.0/ */
import Cocoa

final class DozerIcons {
    private static var instance: DozerIcons?
    static var sharedIfInitialized: DozerIcons? { instance }
    static var shared: DozerIcons {
        if let instance { return instance }
        let controller = DozerIcons()
        instance = controller
        controller.apply()
        controller.resetTimer()
        return controller
    }

    static var hiddenLength: CGFloat {
        PreferenceValidation.hiddenLength(screenWidths: NSScreen.screens.map { $0.frame.width })
    }

    private(set) var state = MenuBarState()
    private let control: HelperstatusIcon
    private let divider: HelperstatusIcon
    private var extraDivider: HelperstatusIcon?
    private var autoHideTimer: Timer?
    private var lastInteraction = Date()
    private var observers: [NSObjectProtocol] = []
    private var previousApp: NSRunningApplication?
    private var launchHideWork: DispatchWorkItem?
    var isHidden: Bool { state.isHidden }
    var isExtraHidden: Bool { state.isExtraHidden }
    var activeTimerCount: Int { autoHideTimer?.isValid == true ? 1 : 0 }
    var items: [HelperstatusIcon] { [control, divider] + (extraDivider.map { [$0] } ?? []) }

    private init() {
        control = NormalStatusIcon(isControl: true)
        divider = NormalStatusIcon(isControl: false)
        state.extraEnabled = Settings.store.bool(forKey: "removeStatusIconEnabled")
        state.hideControl = Settings.store.bool(forKey: "noIconMode")
        state.shortcutAvailable = ShortcutManager.shared.isRegistered
        if state.extraEnabled { extraDivider = RemoveStatusIcon() }
        state.showAll()

        let center = NotificationCenter.default
        observers.append(center.addObserver(forName: .dozerShortcutChanged, object: nil, queue: .main) { [weak self] _ in
            guard let self else { return }
            self.state.shortcutAvailable = ShortcutManager.shared.isRegistered
            if !self.state.shortcutAvailable { self.showAll() }
            self.apply()
        })
        observers.append(center.addObserver(forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main) { [weak self] _ in
            self?.refreshAfterDisplayChange()
        })
        observers.append(NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in
            self?.refreshAfterDisplayChange()
        })
        observers.append(NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.activeSpaceDidChangeNotification, object: nil, queue: .main) { [weak self] _ in
            self?.refreshAfterDisplayChange()
        })
    }

    var hideStatusBarIconsAtLaunch: Bool {
        get { Settings.store.bool(forKey: "hideAtLaunchEnabled") }
        set { Settings.store.set(newValue, forKey: "hideAtLaunchEnabled") }
    }

    var hideStatusBarIconsAfterDelay: Bool {
        get { Settings.store.bool(forKey: "hideAfterDelayEnabled") }
        set {
            Settings.store.set(newValue, forKey: "hideAfterDelayEnabled")
            resetTimer()
        }
    }

    var hideBothDozerIcons: Bool {
        get { Settings.store.bool(forKey: "noIconMode") }
        set {
            Settings.store.set(newValue, forKey: "noIconMode")
            state.hideControl = newValue
            showAll()
        }
    }

    var enableRemoveDozerIcon: Bool {
        get { state.extraEnabled }
        set {
            guard newValue != state.extraEnabled else { return }
            Settings.store.set(newValue, forKey: "removeStatusIconEnabled")
            state.extraEnabled = newValue
            if newValue {
                extraDivider = RemoveStatusIcon()
            } else if let item = extraDivider {
                // AppKit can discard a position when removing a status item.
                let key = "NSStatusItem Preferred Position Dozer.extraDivider"
                let position = UserDefaults.standard.object(forKey: key)
                item.statusIcon.length = Settings.padding
                NSStatusBar.system.removeStatusItem(item.statusIcon)
                if let position { UserDefaults.standard.set(position, forKey: key) }
                extraDivider = nil
            }
            showAll()
        }
    }

    var enableIconAndMenu: Bool {
        get { Settings.store.bool(forKey: "showIconAndMenuEnabled") }
        set {
            Settings.store.set(newValue, forKey: "showIconAndMenuEnabled")
            if !newValue { _ = Self.toggleDockIcon(showIcon: false) }
        }
    }

    var iconFontSize: Int {
        get { Settings.iconSize }
        set { Settings.store.set(PreferenceValidation.iconSize(newValue), forKey: "fontSize"); apply() }
    }

    var buttonPadding: CGFloat {
        get { Settings.padding }
        set { Settings.store.set(PreferenceValidation.padding(newValue), forKey: "buttonPadding"); apply() }
    }

    func hideAtLaunch() {
        guard hideStatusBarIconsAtLaunch else { return }
        let work = DispatchWorkItem { [weak self] in self?.hide() }
        launchHideWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 1, execute: work)
    }

    func hide() {
        cancelLaunchHide()
        state.hide()
        apply()
        stopTimer()
        hideIconAndMenu()
    }

    func show() {
        cancelLaunchHide()
        state.show()
        apply()
        resetTimer()
        showIconAndMenu()
    }

    func showAll() {
        cancelLaunchHide()
        state.showAll()
        items.forEach { $0.restoreVisibility() }
        apply()
        resetTimer()
    }

    func toggle() {
        if state.isHidden { show() } else { hide() }
    }

    func handleOptionClick() {
        cancelLaunchHide()
        state.toggleExtra()
        apply()
        resetTimer()
        showIconAndMenu()
    }

    func toggleRemove() { handleOptionClick() }

    func resetTimer() {
        stopTimer()
        lastInteraction = Date()
        guard hideStatusBarIconsAfterDelay, !state.isHidden else { return }
        let timer = Timer(timeInterval: 0.25, repeats: true) { [weak self] _ in
            self?.autoHideTick()
        }
        timer.tolerance = 0.1
        autoHideTimer = timer
        RunLoop.main.add(timer, forMode: .common)
    }

    private func autoHideTick() {
        guard hideStatusBarIconsAfterDelay, !state.isHidden else { stopTimer(); return }
        if isUserInteractingWithStatusBar() {
            lastInteraction = Date()
        } else if Date().timeIntervalSince(lastInteraction) >= Settings.delay {
            hide()
        }
    }

    private func stopTimer() { autoHideTimer?.invalidate(); autoHideTimer = nil }

    private func cancelLaunchHide() { launchHideWork?.cancel(); launchHideWork = nil }

    private func apply() {
        state.shortcutAvailable = ShortcutManager.shared.isRegistered
        for item in items {
            item.update(expanded: state.isExpanded(item.role), controlHidden: item.role == .control && !state.controlVisible)
        }
        NotificationCenter.default.post(name: .dozerStateChanged, object: self)
    }

    private func refreshAfterDisplayChange() {
        // The status-item frames settle after the display/Space notification.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { [weak self] in
            self?.items.forEach { $0.restoreVisibility() }
            self?.apply()
            self?.resetTimer()
        }
    }

    func showIconAndMenu() {
        guard enableIconAndMenu else { return }
        if let frontmost = NSWorkspace.shared.frontmostApplication,
           frontmost.bundleIdentifier != AppInfo.bundleIdentifier { previousApp = frontmost }
        _ = Self.toggleDockIcon(showIcon: true)
        NSApp.activate(ignoringOtherApps: true)
    }

    func hideIconAndMenu() {
        guard enableIconAndMenu else { return }
        _ = Self.toggleDockIcon(showIcon: false)
        if NSWorkspace.shared.frontmostApplication?.bundleIdentifier == AppInfo.bundleIdentifier {
            previousApp?.activate()
        }
    }

    @discardableResult static func toggleDockIcon(showIcon: Bool) -> Bool {
        NSApp.setActivationPolicy(showIcon ? .regular : .accessory)
    }

    /// Uses only pointer/window metadata. Core hiding needs no Accessibility or recording access.
    private func isUserInteractingWithStatusBar() -> Bool {
        if NSEvent.pressedMouseButtons != 0 { return true }
        if NSApp.windows.contains(where: { $0.isVisible && $0.canBecomeKey }) { return true }
        let mouse = NSEvent.mouseLocation
        let screens = NSScreen.screens
        if screens.contains(where: {
            let height = max(NSStatusBar.system.thickness, $0.safeAreaInsets.top)
            return NSRect(x: $0.frame.minX, y: $0.frame.maxY - height,
                          width: $0.frame.width, height: height).contains(mouse)
        }) { return true }

        guard let list = CGWindowListCopyWindowInfo(.optionOnScreenOnly, kCGNullWindowID) as? [[String: Any]],
              let primaryTop = screens.first?.frame.maxY else { return false }
        let ownPID = ProcessInfo.processInfo.processIdentifier
        struct Window {
            let pid: Int32
            let layer: Int
            let bounds: CGRect
        }
        let windows: [Window] = list.compactMap { info in
            guard let pid = info[kCGWindowOwnerPID as String] as? Int32, pid != ownPID,
                  let layer = info[kCGWindowLayer as String] as? Int,
                  let bounds = info[kCGWindowBounds as String] as? [String: CGFloat],
                  let x = bounds["X"], let y = bounds["Y"],
                  let width = bounds["Width"], let height = bounds["Height"] else { return nil }
            return Window(pid: pid, layer: layer, bounds: CGRect(x: x, y: y, width: width, height: height))
        }
        let menuFrames = screens.map {
            CGRect(x: $0.frame.minX, y: primaryTop - $0.frame.maxY, width: $0.frame.width,
                   height: max(NSStatusBar.system.thickness, $0.safeAreaInsets.top))
        }
        let owners = Set(windows.filter { window in
            window.layer == Int(CGWindowLevelForKey(.statusWindow)) &&
            menuFrames.contains { $0.intersects(window.bounds) }
        }.map(\.pid))
        return windows.contains { window in
            if window.layer == Int(CGWindowLevelForKey(.popUpMenuWindow)) { return true }
            guard owners.contains(window.pid), window.bounds.height > 32, window.bounds.width > 32 else { return false }
            return menuFrames.contains {
                window.bounds.minY >= $0.maxY - 2 && window.bounds.minY <= $0.maxY + 12 &&
                window.bounds.maxX > $0.minX && window.bounds.minX < $0.maxX
            }
        }
    }

    /// Restore other apps' icons before quitting, without activating another application.
    func prepareForTermination() {
        stopTimer()
        cancelLaunchHide()
        state.showAll()
        apply()
    }
}
