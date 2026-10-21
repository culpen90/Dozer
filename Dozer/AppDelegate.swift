/* This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. https://mozilla.org/MPL/2.0/ */
import Cocoa

final class AppDelegate: NSObject, NSApplicationDelegate {
    lazy var settingsWindowController = SettingsWindowController()
    private var didFinishLaunching = false
    private var reopenObserver: NSObjectProtocol?

    func applicationDidFinishLaunching(_ notification: Notification) {
        Settings.registerDefaults()
        // Keep one process, including if Finder opens another copy of the application.
        let duplicates = NSRunningApplication.runningApplications(withBundleIdentifier: AppInfo.bundleIdentifier)
            .filter { $0.processIdentifier != ProcessInfo.processInfo.processIdentifier }
        if !duplicates.isEmpty {
            DistributedNotificationCenter.default().postNotificationName(
                Notification.Name("com.mortennn.Dozer.reveal"), object: nil,
                userInfo: nil, deliverImmediately: true)
            NSApp.terminate(nil)
            return
        }
        reopenObserver = DistributedNotificationCenter.default().addObserver(
            forName: Notification.Name("com.mortennn.Dozer.reveal"), object: nil, queue: .main
        ) { [weak self] _ in self?.showSettings() }
        configureMainMenu()
        _ = DozerIcons.toggleDockIcon(showIcon: false)
        ShortcutManager.shared.start(handler: { DozerIcons.shared.toggle() })
        _ = DozerIcons.shared
        didFinishLaunching = true
        let firstLaunch = !UserDefaults.standard.bool(forKey: "hasCompletedRevivalSetup")
        if firstLaunch {
            UserDefaults.standard.set(true, forKey: "hasCompletedRevivalSetup")
            showSettings()
        } else {
            DozerIcons.shared.hideAtLaunch()
        }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showSettings()
        return true
    }

    func applicationOpenUntitledFile(_ sender: NSApplication) -> Bool {
        if didFinishLaunching { showSettings() }
        return true
    }

    @objc func showSettings() {
        DozerIcons.shared.showAll()
        settingsWindowController.showWindow(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func applicationWillTerminate(_ notification: Notification) {
        DozerIcons.sharedIfInitialized?.prepareForTermination()
    }

    private func configureMainMenu() {
        let main = NSMenu()
        let appItem = NSMenuItem()
        let appMenu = NSMenu()
        appMenu.addItem(withTitle: "About Dozer", action: #selector(showSettings), keyEquivalent: "").target = self
        let settings = appMenu.addItem(withTitle: "Settings…", action: #selector(showSettings), keyEquivalent: ",")
        settings.target = self
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "Quit Dozer", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        appItem.submenu = appMenu
        main.addItem(appItem)
        let editItem = NSMenuItem()
        let edit = NSMenu(title: "Edit")
        edit.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        edit.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        edit.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        edit.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        editItem.submenu = edit
        main.addItem(editItem)
        NSApp.mainMenu = main
    }
}
