/* This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/. */

import AppKit
import ServiceManagement

private final class FlippedSettingsView: NSView {
    override var isFlipped: Bool { true }
}

final class SettingsWindowController: NSWindowController, NSWindowDelegate {
    private let loginCheckbox = NSButton(checkboxWithTitle: "Launch Dozer at login", target: nil, action: nil)
    private let loginStatus = NSTextField(wrappingLabelWithString: "")
    private let autoHideCheckbox = NSButton(checkboxWithTitle: "Hide icons automatically after", target: nil, action: nil)
    private let noIconCheckbox = NSButton(checkboxWithTitle: "Hide Dozer’s controls when collapsed", target: nil, action: nil)
    private let recorder = ShortcutRecorderButton()
    private let shortcutStatus = NSTextField(wrappingLabelWithString: "")
    private let delayPopup = NSPopUpButton()
    private var observers: [NSObjectProtocol] = []

    init() {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 600, height: 720),
                              styleMask: [.titled, .closable, .miniaturizable, .resizable],
                              backing: .buffered, defer: false)
        super.init(window: window)
        window.title = "Dozer Settings"
        window.identifier = NSUserInterfaceItemIdentifier("DozerSettingsWindow")
        window.setAccessibilityIdentifier("DozerSettingsWindow")
        window.minSize = NSSize(width: 560, height: 480)
        window.setFrameAutosaveName("DozerSettings")
        window.isReleasedWhenClosed = false
        window.delegate = self
        buildContent(in: window)
        if !window.setFrameUsingName("DozerSettings") { window.center() }
        observers.append(NotificationCenter.default.addObserver(forName: .dozerShortcutChanged,
                                                                object: nil, queue: .main) { [weak self] _ in
            self?.refreshShortcut()
        })
        observers.append(NotificationCenter.default.addObserver(forName: NSApplication.didBecomeActiveNotification,
                                                                object: nil, queue: .main) { [weak self] _ in
            self?.refreshLogin()
        })
    }

    required init?(coder: NSCoder) { fatalError("Use init()") }

    deinit { observers.forEach(NotificationCenter.default.removeObserver) }

    override func showWindow(_ sender: Any?) {
        super.showWindow(sender)
        refreshLogin()
        refreshShortcut()
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(sender)
    }

    func windowWillClose(_ notification: Notification) { recorder.stopRecording() }

    private func buildContent(in window: NSWindow) {
        let scroll = NSScrollView()
        scroll.hasVerticalScroller = true
        scroll.drawsBackground = false
        let container = FlippedSettingsView()
        container.translatesAutoresizingMaskIntoConstraints = false
        scroll.documentView = container
        window.contentView = scroll

        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 16
        stack.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(stack)
        NSLayoutConstraint.activate([
            container.widthAnchor.constraint(equalTo: scroll.contentView.widthAnchor),
            stack.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 28),
            stack.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -28),
            stack.topAnchor.constraint(equalTo: container.topAnchor, constant: 24),
            stack.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -24)
        ])

        let header = NSStackView()
        header.orientation = .horizontal
        header.spacing = 14
        if let image = NSImage(named: NSImage.Name("AppIcon")) {
            let icon = NSImageView(image: image)
            icon.imageScaling = .scaleProportionallyUpOrDown
            icon.widthAnchor.constraint(equalToConstant: 52).isActive = true
            icon.heightAnchor.constraint(equalToConstant: 52).isActive = true
            header.addArrangedSubview(icon)
        }
        let heading = NSStackView()
        heading.orientation = .vertical
        heading.alignment = .leading
        heading.spacing = 4
        let title = NSTextField(labelWithString: "Dozer")
        title.font = .systemFont(ofSize: 24, weight: .semibold)
        heading.addArrangedSubview(title)
        heading.addArrangedSubview(caption("A little more room in your menu bar."))
        header.addArrangedSubview(heading)
        stack.addArrangedSubview(header)

        let setup = NSStackView()
        setup.orientation = .vertical
        setup.alignment = .leading
        setup.spacing = 7
        setup.addArrangedSubview(sectionTitle("Arrange your menu bar"))
        setup.addArrangedSubview(body("Hold ⌘ and drag the divider dot to the left of Dozer’s control. Place the icons you want to hide to the left of the divider dot. Keep the control on the right."))
        setup.addArrangedSubview(caption("Click the control or divider to show or hide icons. Right-click either for settings. Reopen Dozer from Applications to recover all controls."))
        setup.addArrangedSubview(caption("On a Mac with a camera notch, the menu bar can only show as many icons as fit on screen. Choose a larger display or reduce the visible group if needed."))
        let revealButton = NSButton(title: "Show All Icons", target: self, action: #selector(showAll))
        revealButton.setAccessibilityIdentifier("showAllIcons")
        revealButton.bezelStyle = .rounded
        setup.addArrangedSubview(revealButton)
        stack.addArrangedSubview(setup)
        stack.addArrangedSubview(separator())

        let behavior = NSStackView()
        behavior.orientation = .vertical
        behavior.alignment = .leading
        behavior.spacing = 11
        behavior.addArrangedSubview(sectionTitle("Behavior"))
        configure(loginCheckbox, action: #selector(toggleLogin))
        behavior.addArrangedSubview(loginCheckbox)
        loginStatus.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
        loginStatus.textColor = .secondaryLabelColor
        behavior.addArrangedSubview(loginStatus)
        let loginSettings = NSButton(title: "Open Login Items Settings…", target: self, action: #selector(openLoginSettings))
        loginSettings.bezelStyle = .rounded
        behavior.addArrangedSubview(loginSettings)

        let hideAtLaunch = checkbox("Hide icons when Dozer starts", key: "hideAtLaunchEnabled", action: #selector(toggleHideAtLaunch))
        behavior.addArrangedSubview(hideAtLaunch)
        configure(autoHideCheckbox, action: #selector(toggleAutoHide))
        autoHideCheckbox.state = UserDefaults.standard.bool(forKey: "hideAfterDelayEnabled") ? .on : .off
        delayPopup.target = self
        delayPopup.action = #selector(changeDelay)
        for delay in [2, 5, 10, 15, 30, 60] {
            delayPopup.addItem(withTitle: "\(delay) seconds")
            delayPopup.lastItem?.tag = delay
        }
        let currentDelay = Int(Settings.delay)
        if delayPopup.itemArray.allSatisfy({ $0.tag != currentDelay }), currentDelay > 0 {
            delayPopup.addItem(withTitle: "\(currentDelay) seconds")
            delayPopup.lastItem?.tag = currentDelay
        }
        delayPopup.selectItem(withTag: currentDelay > 0 ? currentDelay : 10)
        delayPopup.isEnabled = autoHideCheckbox.state == .on
        behavior.addArrangedSubview(row([autoHideCheckbox, delayPopup]))
        behavior.addArrangedSubview(checkbox("Enable an extra hidden group (Option-click to reveal)", key: "removeStatusIconEnabled", action: #selector(toggleExtraGroup)))
        behavior.addArrangedSubview(caption("When enabled, place icons for the extra group to the left of the smaller dot."))
        behavior.addArrangedSubview(checkbox("Use Dozer’s short app menu while icons are revealed", key: "showIconAndMenuEnabled", action: #selector(toggleAppMenu)))
        stack.addArrangedSubview(behavior)
        stack.addArrangedSubview(separator())

        let shortcuts = NSStackView()
        shortcuts.orientation = .vertical
        shortcuts.alignment = .leading
        shortcuts.spacing = 10
        shortcuts.addArrangedSubview(sectionTitle("Keyboard shortcut"))
        let clearShortcut = NSButton(title: "Clear", target: self, action: #selector(clearShortcut))
        clearShortcut.bezelStyle = .rounded
        recorder.widthAnchor.constraint(greaterThanOrEqualToConstant: 150).isActive = true
        recorder.onChange = { [weak self] in self?.refreshShortcut() }
        shortcuts.addArrangedSubview(row([NSTextField(labelWithString: "Toggle hidden icons:"), recorder, clearShortcut]))
        shortcuts.addArrangedSubview(caption("Click the shortcut field, then press a key with ⌘, ⌥, or ⌃. Escape cancels; Delete clears."))
        configure(noIconCheckbox, action: #selector(toggleNoIcon))
        shortcuts.addArrangedSubview(noIconCheckbox)
        shortcutStatus.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
        shortcutStatus.textColor = .secondaryLabelColor
        shortcuts.addArrangedSubview(shortcutStatus)
        stack.addArrangedSubview(shortcuts)
        stack.addArrangedSubview(separator())

        let appearance = NSStackView()
        appearance.orientation = .vertical
        appearance.alignment = .leading
        appearance.spacing = 10
        appearance.addArrangedSubview(sectionTitle("Appearance"))
        let sizePopup = NSPopUpButton()
        for size in [6, 8, 10, 12, 14, 16, 18] {
            sizePopup.addItem(withTitle: "\(size) pt")
            sizePopup.lastItem?.tag = size
        }
        if sizePopup.itemArray.allSatisfy({ $0.tag != DozerIcons.shared.iconFontSize }) {
            sizePopup.addItem(withTitle: "\(DozerIcons.shared.iconFontSize) pt")
            sizePopup.lastItem?.tag = DozerIcons.shared.iconFontSize
        }
        sizePopup.selectItem(withTag: DozerIcons.shared.iconFontSize)
        sizePopup.target = self
        sizePopup.action = #selector(changeSize)
        let paddingPopup = NSPopUpButton()
        for padding in [20, 25, 30, 35, 40, 50, 60] {
            paddingPopup.addItem(withTitle: "\(padding) pt")
            paddingPopup.lastItem?.tag = padding
        }
        let currentPadding = Int(DozerIcons.shared.buttonPadding)
        if paddingPopup.itemArray.allSatisfy({ $0.tag != currentPadding }) {
            paddingPopup.addItem(withTitle: "\(currentPadding) pt")
            paddingPopup.lastItem?.tag = currentPadding
        }
        paddingPopup.selectItem(withTag: currentPadding)
        paddingPopup.target = self
        paddingPopup.action = #selector(changePadding)
        appearance.addArrangedSubview(row([NSTextField(labelWithString: "Dot size:"), sizePopup,
                                          NSTextField(labelWithString: "  Spacing:"), paddingPopup]))
        stack.addArrangedSubview(appearance)
        stack.addArrangedSubview(separator())
        let footer = NSStackView()
        footer.orientation = .horizontal
        footer.spacing = 12
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? ""
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? ""
        footer.addArrangedSubview(caption("Version \(version) (\(build)) · Local build"))
        let source = NSButton(title: "Project on GitHub", target: self, action: #selector(openProject))
        source.bezelStyle = .rounded
        footer.addArrangedSubview(source)
        let quit = NSButton(title: "Quit Dozer", target: NSApp, action: #selector(NSApplication.terminate(_:)))
        quit.bezelStyle = .rounded
        footer.addArrangedSubview(quit)
        stack.addArrangedSubview(footer)
        for item in stack.arrangedSubviews {
            item.widthAnchor.constraint(lessThanOrEqualTo: stack.widthAnchor).isActive = true
        }
        refreshLogin()
        refreshShortcut()
    }

    private func sectionTitle(_ text: String) -> NSTextField {
        let label = NSTextField(labelWithString: text)
        label.font = .systemFont(ofSize: NSFont.systemFontSize, weight: .semibold)
        return label
    }

    private func body(_ text: String) -> NSTextField {
        let label = NSTextField(wrappingLabelWithString: text)
        label.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        label.preferredMaxLayoutWidth = 520
        return label
    }

    private func caption(_ text: String) -> NSTextField {
        let label = body(text)
        label.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
        label.textColor = .secondaryLabelColor
        return label
    }

    private func separator() -> NSBox {
        let box = NSBox()
        box.boxType = .separator
        box.widthAnchor.constraint(equalToConstant: 500).isActive = true
        return box
    }

    private func row(_ views: [NSView]) -> NSStackView {
        let stack = NSStackView(views: views)
        stack.orientation = .horizontal
        stack.alignment = .centerY
        stack.spacing = 8
        return stack
    }

    private func configure(_ checkbox: NSButton, action: Selector) {
        checkbox.target = self
        checkbox.action = action
        checkbox.setAccessibilityIdentifier(NSStringFromSelector(action))
    }

    private func checkbox(_ text: String, key: String, action: Selector) -> NSButton {
        let checkbox = NSButton(checkboxWithTitle: text, target: self, action: action)
        checkbox.state = UserDefaults.standard.bool(forKey: key) ? .on : .off
        checkbox.setAccessibilityIdentifier(key)
        return checkbox
    }

    private func refreshLogin() {
        loginCheckbox.state = LoginItemManager.isEnabled ? .on : .off
        switch LoginItemManager.status {
        case .enabled:
            loginStatus.stringValue = "Dozer will open automatically when you sign in."
        case .requiresApproval:
            loginCheckbox.state = .mixed
            loginStatus.stringValue = "Approval is needed in System Settings → General → Login Items."
        case .notFound:
            loginStatus.stringValue = "Keep Dozer in Applications before enabling launch at login."
        default:
            loginStatus.stringValue = "Dozer will open only when you launch it."
        }
    }

    private func refreshShortcut() {
        recorder.refreshTitle()
        noIconCheckbox.isEnabled = ShortcutManager.shared.isRegistered
        noIconCheckbox.state = DozerIcons.shared.hideBothDozerIcons ? .on : .off
        if let error = ShortcutManager.shared.lastError {
            shortcutStatus.stringValue = error
            shortcutStatus.textColor = .systemOrange
        } else {
            shortcutStatus.stringValue = ShortcutManager.shared.isRegistered
                ? "The shortcut works in any app. Reopening Dozer always restores its controls."
                : "Set a working shortcut before hiding Dozer’s controls."
            shortcutStatus.textColor = .secondaryLabelColor
        }
    }

    @objc private func toggleLogin(_ sender: NSButton) {
        do {
            try LoginItemManager.setEnabled(sender.state == .on)
        } catch {
            let alert = NSAlert()
            alert.messageText = "Launch at login could not be changed"
            alert.informativeText = error.localizedDescription
            if let window { alert.beginSheetModal(for: window) }
        }
        refreshLogin()
    }
    @objc private func openLoginSettings() { LoginItemManager.openSettings() }
    @objc private func showAll() { DozerIcons.shared.showAll() }
    @objc private func toggleHideAtLaunch(_ sender: NSButton) { DozerIcons.shared.hideStatusBarIconsAtLaunch = sender.state == .on }
    @objc private func toggleAutoHide(_ sender: NSButton) {
        DozerIcons.shared.hideStatusBarIconsAfterDelay = sender.state == .on
        delayPopup.isEnabled = sender.state == .on
    }
    @objc private func changeDelay(_ sender: NSPopUpButton) {
        UserDefaults.standard.set(Double(sender.selectedTag()), forKey: "hideAfterDelay")
        DozerIcons.shared.resetTimer()
    }
    @objc private func toggleExtraGroup(_ sender: NSButton) { DozerIcons.shared.enableRemoveDozerIcon = sender.state == .on }
    @objc private func toggleAppMenu(_ sender: NSButton) { DozerIcons.shared.enableIconAndMenu = sender.state == .on }
    @objc private func toggleNoIcon(_ sender: NSButton) { DozerIcons.shared.hideBothDozerIcons = sender.state == .on }
    @objc private func changeSize(_ sender: NSPopUpButton) { DozerIcons.shared.iconFontSize = sender.selectedTag() }
    @objc private func changePadding(_ sender: NSPopUpButton) { DozerIcons.shared.buttonPadding = CGFloat(sender.selectedTag()) }
    @objc private func clearShortcut() {
        recorder.stopRecording()
        ShortcutManager.shared.setShortcut(nil)
        refreshShortcut()
    }
    @objc private func openProject() {
        if let url = URL(string: "https://github.com/culpen90/Dozer") { NSWorkspace.shared.open(url) }
    }
}
