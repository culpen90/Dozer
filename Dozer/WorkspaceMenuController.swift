/* This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. https://mozilla.org/MPL/2.0/ */
import AppKit

final class WorkspaceMenuController: NSObject, NSMenuDelegate {
    func makeMenu() -> NSMenu {
        let menu = NSMenu(title: "Dozer")
        menu.autoenablesItems = false
        add("Open Dozer Workspace…", action: #selector(openWorkspace), to: menu)
        add(DozerIcons.shared.isHidden ? "Show Menu Bar Icons" : "Hide Menu Bar Icons", action: #selector(toggleIcons), to: menu)
        if DozerIcons.shared.enableRemoveDozerIcon {
            add("Show All Icon Groups", action: #selector(showAll), to: menu)
        }
        menu.addItem(.separator())
        let windows = NSMenuItem(title: "Arrange Window", action: nil, keyEquivalent: "")
        windows.image = NSImage(systemSymbolName: "macwindow", accessibilityDescription: nil)
        windows.submenu = makeWindowMenu()
        menu.addItem(windows)
        if !WindowManager.shared.isTrusted {
            add("Enable Window Management…", action: #selector(requestPermission), to: menu)
        }
        menu.addItem(.separator())
        add("Quit Dozer", action: #selector(quit), to: menu)
        return menu
    }

    func makeWindowMenu() -> NSMenu {
        let menu = NSMenu(title: "Windows")
        menu.delegate = self
        populateWindows(menu)
        return menu
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        WindowManager.shared.refreshPermission()
        menu.removeAllItems()
        populateWindows(menu)
    }

    private func populateWindows(_ menu: NSMenu) {
        menu.autoenablesItems = false
        var previousGroup: String?
        for action in WindowLayoutAction.allCases {
            if previousGroup != nil, previousGroup != action.group { menu.addItem(.separator()) }
            previousGroup = action.group
            let shortcut = WindowShortcutManager.shared.shortcut(for: action)?.displayString
            let title = action.title + (shortcut.map { "     \($0)" } ?? "")
            let item = NSMenuItem(title: title, action: #selector(arrange(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = action.rawValue
            item.image = NSImage(systemSymbolName: action.symbolName, accessibilityDescription: nil)
            item.isEnabled = WindowManager.shared.isEnabled && WindowManager.shared.isTrusted
            menu.addItem(item)
        }
    }

    private func add(_ title: String, action: Selector, to menu: NSMenu) {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
        item.target = self
        menu.addItem(item)
    }

    @objc private func arrange(_ sender: NSMenuItem) {
        guard let rawValue = sender.representedObject as? String,
              let action = WindowLayoutAction(rawValue: rawValue) else { return }
        WindowManager.shared.execute(action)
    }
    @objc private func openWorkspace() { appDelegate.showSettings() }
    @objc private func toggleIcons() { DozerIcons.shared.toggle() }
    @objc private func showAll() { DozerIcons.shared.showAll() }
    @objc private func requestPermission() { WindowManager.shared.requestPermission() }
    @objc private func quit() { NSApp.terminate(nil) }
}
