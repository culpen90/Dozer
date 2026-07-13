/* This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/. */

import Cocoa
import KeyboardShortcuts
import Sparkle
import Defaults
import Settings


final class AppDelegate: NSObject, NSApplicationDelegate {
    // Sparkle 2 updater. Only start it when this build has an update feed.
    let updaterController = SPUStandardUpdaterController(
        startingUpdater: AppInfo.hasUpdateFeed,
        updaterDelegate: nil,
        userDriverDelegate: nil
    )

    func applicationDidFinishLaunching(_: Notification) {
        // Preserve settings and shortcuts from installations made before the
        // app and bundle identifier were renamed to BarHide.
        migrateLegacyApplicationPreferencesIfNeeded()

        // Carry over a shortcut saved by the old MASShortcut integration.
        migrateLegacyShortcutIfNeeded()

        // Trigger on key-down to match MASShortcut's original behavior.
        KeyboardShortcuts.onKeyDown(for: .toggleMenuItems) {
            BarHideIcons.shared.toggle()
        }

        // Initalize BarHide Icons
        _ = BarHideIcons.shared

        // If enabled hide menu bar icons at launch
        BarHideIcons.shared.hideAtLaunch()

        _ = BarHideIcons.toggleDockIcon(showIcon: false)
    }

    /// Copy persisted preferences from the original Dozer bundle domain once.
    /// Existing BarHide values win so a later launch cannot overwrite changes
    /// made after the rename.
    private func migrateLegacyApplicationPreferencesIfNeeded() {
        let defaults = UserDefaults.standard
        let migrationKey = "didMigrateDozerPreferencesToBarHide"

        guard defaults.object(forKey: migrationKey) == nil else {
            return
        }

        let currentDomain = defaults.persistentDomain(forName: AppInfo.bundleIdentifier) ?? [:]
        let legacyDomain = defaults.persistentDomain(forName: "com.mortennn.Dozer") ?? [:]

        for (key, value) in legacyDomain where currentDomain[key] == nil {
            defaults.set(value, forKey: key)
        }

        defaults.set(true, forKey: migrationKey)
    }

    // Show all BarHide icons when opening BarHide from Finder etc.
    func applicationOpenUntitledFile(_ sender: NSApplication) -> Bool {
        BarHideIcons.shared.showAll()
        return true
    }

    /// Import a shortcut saved by the previous MASShortcut integration so
    /// existing users keep their toggle hotkey after upgrading.
    ///
    /// MASShortcut (via `MASShortcutBinder`) stored the shortcut under the
    /// `"toggleMenuItems"` UserDefaults key as a `{keyCode, modifierFlags}`
    /// dictionary, where `modifierFlags` are Cocoa `NSEvent.ModifierFlags`.
    /// KeyboardShortcuts uses its own `"KeyboardShortcuts_"`-prefixed storage,
    /// so without this the saved shortcut would silently disappear.
    @MainActor
    private func migrateLegacyShortcutIfNeeded() {
        let legacyKey = "toggleMenuItems"
        let defaults = UserDefaults.standard

        guard let legacy = defaults.dictionary(forKey: legacyKey) else {
            return
        }

        // Only import if the user has not already recorded one with the new API.
        if KeyboardShortcuts.getShortcut(for: .toggleMenuItems) == nil,
            let keyCode = (legacy["keyCode"] as? NSNumber)?.intValue,
            let modifierFlags = (legacy["modifierFlags"] as? NSNumber)?.uintValue {
            let shortcut = KeyboardShortcuts.Shortcut(
                KeyboardShortcuts.Key(rawValue: keyCode),
                modifiers: NSEvent.ModifierFlags(rawValue: modifierFlags)
            )
            KeyboardShortcuts.setShortcut(shortcut, for: .toggleMenuItems)
            Defaults[.isShortcutSet] = true
        }

        // Drop the obsolete key so this only runs once.
        defaults.removeObject(forKey: legacyKey)
    }

    lazy var preferences: [SettingsPane] = [
        BarHide(),
        General()
    ]

    lazy var preferencesWindowController = SettingsWindowController(
        panes: preferences,
        style: .toolbarItems,
        animated: true,
        hidesToolbarForSingleItem: true
    )

    /// Open the settings window, reliably in front of other apps.
    ///
    /// The Settings library relies on the cooperative `NSApp.activate()` on
    /// macOS 14+, which does not reliably bring an accessory (menu-bar) app's
    /// window forward, so the window can open behind the frontmost app.
    /// `orderFrontRegardless()` forces it above other apps' windows.
    func showPreferences() {
        preferencesWindowController.show(pane: .general)
        preferencesWindowController.window?.orderFrontRegardless()
    }
}
