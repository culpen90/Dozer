/* This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/. */

import Cocoa
import Sparkle
import Settings

final class BarHide: NSViewController, SettingsPane {
    let paneIdentifier = Settings.PaneIdentifier.barHide
    let paneTitle: String = "BarHide"
    let toolbarItemIcon = NSImage(named: "AppIcon")!

    override var nibName: NSNib.Name? { "BarHide" }

    @IBOutlet private var versionLabel: NSTextField!
    @IBOutlet private var checkForUpdates: NSButton!
    @IBOutlet private var quit: NSButton!

    override func viewDidLoad() {
        super.viewDidLoad()

        if let releaseVersionNumber = AppInfo.releaseVersionNumber,
            let buildVersionNumber = AppInfo.buildVersionNumber {
            versionLabel.stringValue = "\(releaseVersionNumber) (\(buildVersionNumber))"
        }

        if AppInfo.hasUpdateFeed, let appDelegate = NSApp.delegate as? AppDelegate {
            checkForUpdates.target = appDelegate.updaterController
            checkForUpdates.action = #selector(SPUStandardUpdaterController.checkForUpdates(_:))
            checkForUpdates.isEnabled = true
        } else {
            checkForUpdates.isEnabled = false
        }

        quit.action = #selector(NSApp.terminate(_:))
    }
}
