/* This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. https://mozilla.org/MPL/2.0/ */
import Cocoa

enum Settings {
    static var store = UserDefaults.standard

    static func registerDefaults() {
        store.register(defaults: [
            "hideAtLaunchEnabled": false, "hideAfterDelayEnabled": false,
            "hideAfterDelay": 10.0, "noIconMode": false,
            "removeStatusIconEnabled": false, "showIconAndMenuEnabled": false,
            "fontSize": 10, "buttonPadding": 25.0
        ])
    }

    static var delay: TimeInterval {
        PreferenceValidation.delay(store.double(forKey: "hideAfterDelay"))
    }
    static var iconSize: Int {
        PreferenceValidation.iconSize(store.integer(forKey: "fontSize"))
    }
    static var padding: CGFloat {
        PreferenceValidation.padding(store.double(forKey: "buttonPadding"))
    }
}

enum AppInfo {
    static let bundleIdentifier = Bundle.main.bundleIdentifier ?? "com.mortennn.Dozer"
    static var releaseVersionNumber: String? {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
    }
    static var buildVersionNumber: String? {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String
    }
}

extension Notification.Name {
    static let dozerStateChanged = Notification.Name("DozerStateChanged")
}
