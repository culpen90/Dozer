/* This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. https://mozilla.org/MPL/2.0/ */
import Cocoa

/// Keep each named item alive; its role never depends on transient screen coordinates.
class HelperstatusIcon: NSObject {
    let role: MenuBarItemRole
    let statusIcon: NSStatusItem
    private var expanded = false
    private var appearanceKey: String?

    init(role: MenuBarItemRole) {
        self.role = role
        statusIcon = NSStatusBar.system.statusItem(withLength: Settings.padding)
        super.init()
        statusIcon.autosaveName = "Dozer.\(role.rawValue)"
        statusIcon.behavior = []
        statusIcon.isVisible = true
        if let button = statusIcon.button {
            button.target = self
            button.action = #selector(statusIconClicked(_:))
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
            button.setAccessibilityIdentifier("dozer.\(role.rawValue)")
            button.setAccessibilityLabel(role == .control ? "Dozer" : role == .divider ? "Dozer hidden icons divider" : "Dozer extra hidden icons divider")
        }
        update(expanded: false, controlHidden: false)
    }

    func update(expanded: Bool, controlHidden: Bool) {
        self.expanded = expanded
        // AppKit imposes a minimum width, so zero length does not actually hide a control.
        // Preserve its preferred position while temporarily removing it from the menu bar.
        if role == .control, statusIcon.isVisible == controlHidden {
            let key = "NSStatusItem Preferred Position Dozer.control"
            let position = UserDefaults.standard.object(forKey: key)
            statusIcon.isVisible = !controlHidden
            if let position { UserDefaults.standard.set(position, forKey: key) }
        }
        let hidden = DozerIcons.sharedIfInitialized?.isHidden ?? false
        let key = "\(expanded)-\(controlHidden)-\(hidden)-\(Settings.iconSize)"
        if appearanceKey != key {
            statusIcon.button?.image = expanded || controlHidden ? nil : Icons.image(for: role, hidden: hidden)
            statusIcon.button?.isEnabled = !expanded && !controlHidden
            statusIcon.button?.alphaValue = expanded || controlHidden ? 0 : 1
            statusIcon.button?.toolTip = role == .control
                ? "Dozer: click to \(hidden ? "show" : "hide") icons. Option-click shows extra icons. Right-click for settings."
                : "Command-drag icons to the left of this dot to hide them. Right-click for settings."
            appearanceKey = key
        }
        // Update content before length: the remote menu-bar host can otherwise restore intrinsic sizing.
        let length = expanded ? DozerIcons.hiddenLength : Settings.padding
        if statusIcon.length != length { statusIcon.length = length }
    }

    func restoreVisibility() { statusIcon.isVisible = true }

    @objc func statusIconClicked(_ sender: Any?) {
        let event = NSApp.currentEvent
        guard event?.modifierFlags.contains(.command) != true else { return }
        if event?.type == .rightMouseUp || event?.modifierFlags.contains(.control) == true {
            appDelegate.showSettings()
        } else if event?.modifierFlags.contains(.option) == true || role == .extraDivider {
            DozerIcons.shared.handleOptionClick()
        } else {
            DozerIcons.shared.toggle()
        }
    }

    var frame: NSRect? { statusIcon.button?.window?.frame }
    var isShown: Bool { !expanded }
}
