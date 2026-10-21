/* This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. https://mozilla.org/MPL/2.0/ */
import AppKit

/// One home for menu bar controls and Rectangle-derived window tools.
final class SettingsWindowController: NSWindowController, NSWindowDelegate {
    private let menuBarSettings = MenuBarSettingsViewController()
    private let tabs = NSTabView()
    private var navigation: [NSButton] = []
    private var observers: [NSObjectProtocol] = []
    private var recorders: [WindowShortcutRecorder] = []
    private var shortcutErrors: [WindowLayoutAction: NSTextField] = [:]
    private let menuStatus = NSTextField(labelWithString: "")
    private let windowStatus = NSTextField(labelWithString: "")
    private let targetLabel = NSTextField(labelWithString: "")
    private let resultLabel = NSTextField(wrappingLabelWithString: "")
    private let permissionStatus = NSTextField(wrappingLabelWithString: "")
    private let permissionButton = NSButton(title: "Enable Accessibility…", target: nil, action: nil)
    private let toggleIconsButton = NSButton(title: "", target: nil, action: nil)
    private let enabledCheckbox = NSButton(checkboxWithTitle: "Enable window management", target: nil, action: nil)
    private let dragCheckbox = NSButton(checkboxWithTitle: "Snap windows when dragged to screen edges", target: nil, action: nil)
    private let gapPopup = NSPopUpButton()

    init() {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 900, height: 730),
                              styleMask: [.titled, .closable, .miniaturizable, .resizable],
                              backing: .buffered, defer: false)
        super.init(window: window)
        window.title = "Dozer"
        window.subtitle = "A calmer desktop."
        window.identifier = NSUserInterfaceItemIdentifier("DozerSettingsWindow")
        window.setAccessibilityIdentifier("DozerSettingsWindow")
        window.minSize = NSSize(width: 850, height: 600)
        window.setFrameAutosaveName("DozerWorkspace")
        window.isReleasedWhenClosed = false
        window.delegate = self
        buildContent(in: window)
        if !window.setFrameUsingName("DozerWorkspace") { window.center() }
        for name in [Notification.Name.dozerStateChanged, .dozerWindowStateChanged,
                     .dozerWindowShortcutsChanged, NSApplication.didBecomeActiveNotification] {
            observers.append(NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                self?.refresh()
            })
        }
        selectPage(0)
        refresh()
    }

    required init?(coder: NSCoder) { fatalError("Use init()") }
    deinit { observers.forEach(NotificationCenter.default.removeObserver) }

    override func showWindow(_ sender: Any?) {
        WindowManager.shared.refreshPermission()
        super.showWindow(sender)
        refresh()
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(sender)
    }

    func windowWillClose(_ notification: Notification) {
        stopRecording()
    }

    private func stopRecording() {
        menuBarSettings.stopRecording()
        recorders.forEach { $0.stopRecording() }
    }

    private func buildContent(in window: NSWindow) {
        let root = NSView()
        window.contentView = root
        let sidebar = NSVisualEffectView()
        sidebar.material = .sidebar
        sidebar.blendingMode = .behindWindow
        sidebar.translatesAutoresizingMaskIntoConstraints = false
        root.addSubview(sidebar)
        tabs.tabViewType = .noTabsNoBorder
        tabs.translatesAutoresizingMaskIntoConstraints = false
        root.addSubview(tabs)
        NSLayoutConstraint.activate([
            sidebar.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            sidebar.topAnchor.constraint(equalTo: root.topAnchor),
            sidebar.bottomAnchor.constraint(equalTo: root.bottomAnchor),
            sidebar.widthAnchor.constraint(equalToConstant: 178),
            tabs.leadingAnchor.constraint(equalTo: sidebar.trailingAnchor),
            tabs.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            tabs.topAnchor.constraint(equalTo: root.topAnchor),
            tabs.bottomAnchor.constraint(equalTo: root.bottomAnchor)
        ])
        let nav = vertical(spacing: 8)
        sidebar.addSubview(nav)
        let brand = label("Dozer", size: 25, weight: .bold)
        nav.addArrangedSubview(brand)
        nav.addArrangedSubview(caption("Make a little room."))
        let spacer = NSView()
        spacer.heightAnchor.constraint(equalToConstant: 18).isActive = true
        nav.addArrangedSubview(spacer)
        let names = ["Workspace", "Menu Bar", "Windows", "About"]
        let symbols = ["square.grid.2x2", "menubar.rectangle", "macwindow", "info.circle"]
        for index in names.indices {
            let button = NSButton(title: names[index], target: self, action: #selector(navigate(_:)))
            button.tag = index
            button.bezelStyle = .recessed
            button.setButtonType(.pushOnPushOff)
            button.alignment = .left
            button.image = NSImage(systemSymbolName: symbols[index], accessibilityDescription: nil)
            button.imagePosition = .imageLeading
            button.font = .systemFont(ofSize: 14, weight: .medium)
            button.setAccessibilityIdentifier("dozer.page.\(index)")
            nav.addArrangedSubview(button)
            button.widthAnchor.constraint(equalTo: nav.widthAnchor).isActive = true
            button.heightAnchor.constraint(equalToConstant: 34).isActive = true
            navigation.append(button)
        }
        let footer = caption("Menu bar + windows\nOne small app.")
        sidebar.addSubview(footer)
        footer.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            nav.leadingAnchor.constraint(equalTo: sidebar.leadingAnchor, constant: 16),
            nav.trailingAnchor.constraint(equalTo: sidebar.trailingAnchor, constant: -16),
            nav.topAnchor.constraint(equalTo: sidebar.topAnchor, constant: 28),
            footer.leadingAnchor.constraint(equalTo: sidebar.leadingAnchor, constant: 18),
            footer.trailingAnchor.constraint(equalTo: sidebar.trailingAnchor, constant: -14),
            footer.bottomAnchor.constraint(equalTo: sidebar.bottomAnchor, constant: -22)
        ])
        let pages = [workspacePage(), menuBarSettings.view, windowsPage(), aboutPage()]
        for (index, page) in pages.enumerated() {
            let item = NSTabViewItem(identifier: index)
            item.view = page
            tabs.addTabViewItem(item)
        }
    }

    private func workspacePage() -> NSView {
        let stack = pageStack()
        stack.addArrangedSubview(label("Make room for\nwhat matters.", size: 32, weight: .bold))
        stack.addArrangedSubview(caption("A tidy menu bar. Windows right where you want them."))

        let statusRow = NSStackView()
        statusRow.orientation = .horizontal
        statusRow.distribution = .fillEqually
        statusRow.spacing = 14
        let menuCard = vertical(spacing: 10)
        menuCard.addArrangedSubview(eyebrow("MENU BAR", symbol: "menubar.rectangle"))
        menuStatus.font = .systemFont(ofSize: 21, weight: .semibold)
        menuCard.addArrangedSubview(menuStatus)
        configure(toggleIconsButton, action: #selector(toggleIcons))
        toggleIconsButton.setAccessibilityIdentifier("workspace.toggleIcons")
        menuCard.addArrangedSubview(toggleIconsButton)
        statusRow.addArrangedSubview(card(menuCard))
        let windowCard = vertical(spacing: 10)
        windowCard.addArrangedSubview(eyebrow("WINDOWS", symbol: "macwindow"))
        windowStatus.font = .systemFont(ofSize: 21, weight: .semibold)
        windowCard.addArrangedSubview(windowStatus)
        let configureWindows = NSButton(title: "Window Settings…", target: self, action: #selector(openWindows))
        configureWindows.bezelStyle = .rounded
        windowCard.addArrangedSubview(configureWindows)
        statusRow.addArrangedSubview(card(windowCard))
        addFullWidth(statusRow, to: stack)
        targetLabel.font = .systemFont(ofSize: 17, weight: .semibold)
        stack.addArrangedSubview(targetLabel)
        stack.addArrangedSubview(caption("Pick a layout for your last active app, or use a shortcut from anywhere."))
        let actions: [WindowLayoutAction] = [.leftHalf, .maximize, .rightHalf,
                                           .topLeft, .center, .topRight,
                                           .bottomLeft, .restore, .bottomRight,
                                           .firstThird, .centerThird, .lastThird]
        for rowIndex in 0..<4 {
            let row = NSStackView()
            row.orientation = .horizontal
            row.distribution = .fillEqually
            row.spacing = 10
            for action in actions[(rowIndex * 3)..<(rowIndex * 3 + 3)] {
                let button = LayoutTileButton(action: action)
                button.target = self
                button.action = #selector(runLayout(_:))
                row.addArrangedSubview(button)
            }
            addFullWidth(row, to: stack)
        }
        resultLabel.font = .systemFont(ofSize: 12)
        resultLabel.textColor = .secondaryLabelColor
        addFullWidth(resultLabel, to: stack)
        stack.addArrangedSubview(caption("Tip: drag a window to an edge to snap it. Hold Option to bypass snapping."))
        return scrollPage(stack)
    }

    private func windowsPage() -> NSView {
        let stack = pageStack()
        stack.addArrangedSubview(label("Windows", size: 28, weight: .bold))
        stack.addArrangedSubview(caption("Rectangle-inspired layouts, built into Dozer."))
        enabledCheckbox.target = self
        enabledCheckbox.action = #selector(toggleWindowManagement)
        enabledCheckbox.setAccessibilityIdentifier("windows.enabled")
        stack.addArrangedSubview(enabledCheckbox)
        let permission = vertical(spacing: 10)
        permission.addArrangedSubview(label("Let Dozer arrange your windows", size: 15, weight: .semibold))
        permissionStatus.preferredMaxLayoutWidth = 540
        permissionStatus.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        permission.addArrangedSubview(permissionStatus)
        configure(permissionButton, action: #selector(requestPermission))
        permissionButton.setAccessibilityIdentifier("windows.accessibility")
        permission.addArrangedSubview(permissionButton)
        addFullWidth(card(permission), to: stack)
        dragCheckbox.target = self
        dragCheckbox.action = #selector(toggleDrag)
        dragCheckbox.setAccessibilityIdentifier("windows.dragSnapping")
        stack.addArrangedSubview(dragCheckbox)
        stack.addArrangedSubview(caption("Edges make halves, corners make quarters, and the top edge maximizes. A preview shows the destination. Hold Option to cancel a snap."))
        gapPopup.addItems(withTitles: ["No gap", "4 pt", "8 pt", "12 pt", "16 pt", "24 pt", "30 pt"])
        for (index, gap) in [0, 4, 8, 12, 16, 24, 30].enumerated() { gapPopup.item(at: index)?.tag = gap }
        let gap = Int(WindowManager.shared.gap)
        if gapPopup.itemArray.allSatisfy({ $0.tag != gap }) {
            gapPopup.addItem(withTitle: "\(gap) pt")
            gapPopup.lastItem?.tag = gap
        }
        gapPopup.target = self
        gapPopup.action = #selector(changeGap)
        gapPopup.setAccessibilityIdentifier("windows.gap")
        stack.addArrangedSubview(horizontal([label("Window spacing", size: 13), gapPopup]))
        stack.addArrangedSubview(caption("Quit Rectangle or other window managers while using Dozer to avoid competing shortcuts and snap previews."))
        stack.addArrangedSubview(label("Keyboard shortcuts", size: 18, weight: .semibold))
        stack.addArrangedSubview(caption("Click a shortcut to record. Escape cancels; Delete clears. Conflicts keep your previous shortcut working."))
        var previousGroup: String?
        for action in WindowLayoutAction.allCases {
            if previousGroup != action.group {
                stack.addArrangedSubview(label(action.group, size: 13, weight: .semibold))
                previousGroup = action.group
            }
            let title = label(action.title, size: 13)
            title.setContentHuggingPriority(.defaultLow, for: .horizontal)
            let recorder = WindowShortcutRecorder(action: action)
            recorder.onChange = { [weak self] in self?.refresh() }
            recorder.widthAnchor.constraint(equalToConstant: 148).isActive = true
            recorders.append(recorder)
            let row = horizontal([title, recorder])
            addFullWidth(row, to: stack)
            let error = caption("")
            error.textColor = .systemOrange
            shortcutErrors[action] = error
            addFullWidth(error, to: stack)
        }
        let reset = NSButton(title: "Restore Default Shortcuts", target: self, action: #selector(resetShortcuts))
        reset.bezelStyle = .rounded
        stack.addArrangedSubview(reset)
        stack.addArrangedSubview(caption("Standard shortcuts use Control–Option. Menu bar visibility keeps its own shortcut in Menu Bar settings."))
        return scrollPage(stack)
    }

    private func aboutPage() -> NSView {
        let stack = pageStack()
        if let image = NSImage(named: "AppIcon") {
            let icon = NSImageView(image: image)
            icon.widthAnchor.constraint(equalToConstant: 80).isActive = true
            icon.heightAnchor.constraint(equalToConstant: 80).isActive = true
            stack.addArrangedSubview(icon)
        }
        stack.addArrangedSubview(label("Dozer", size: 30, weight: .bold))
        stack.addArrangedSubview(caption("Menu bar + windows. One small app."))
        let version = AppInfo.releaseVersionNumber ?? ""
        stack.addArrangedSubview(caption("Version \(version) · Local build"))
        stack.addArrangedSubview(label("Two great ideas, together", size: 18, weight: .semibold))
        stack.addArrangedSubview(copy("Dozer’s menu bar hiding is combined with window layout geometry adapted from Rectangle. Window movement, shortcuts, previews, and settings run inside this app."))
        stack.addArrangedSubview(copy("Original Dozer by Mortennn, licensed under MPL 2.0. Rectangle by Ryan Hanson, based on Spectacle by Eric Czarny, licensed under MIT. This combined app is an independent project."))
        for (title, url) in [("Dozer Source", "https://github.com/culpen90/Dozer"),
                             ("Rectangle Source", "https://github.com/rxhanson/Rectangle")] {
            let button = NSButton(title: title, target: self, action: #selector(openLink(_:)))
            button.identifier = NSUserInterfaceItemIdentifier(url)
            button.bezelStyle = .rounded
            stack.addArrangedSubview(button)
        }
        let notices = NSButton(title: "Open Source Licenses…", target: self, action: #selector(openLicenses))
        notices.bezelStyle = .rounded
        stack.addArrangedSubview(notices)
        stack.addArrangedSubview(caption("Menu bar hiding needs no Accessibility access. Window management uses macOS Accessibility. No account, network service, or separate Rectangle installation is required."))
        let quit = NSButton(title: "Quit Dozer", target: NSApp, action: #selector(NSApplication.terminate(_:)))
        quit.bezelStyle = .rounded
        stack.addArrangedSubview(quit)
        return scrollPage(stack)
    }

    private func refresh() {
        let manager = WindowManager.shared
        menuStatus.stringValue = DozerIcons.shared.isHidden ? "Tucked away" : DozerIcons.shared.isExtraHidden ? "Main group visible" : "All visible"
        toggleIconsButton.title = DozerIcons.shared.isHidden ? "Show Icons" : "Hide Icons"
        windowStatus.stringValue = !manager.isEnabled ? "Paused" : manager.isTrusted ? "Ready to arrange" : "Access needed"
        targetLabel.stringValue = manager.targetApplicationName.map { "Arrange \($0)" } ?? "Your favorite layouts"
        resultLabel.stringValue = manager.lastMessage ?? "Start with ⌃⌥← and ⌃⌥→ for side-by-side windows."
        permissionStatus.stringValue = manager.isTrusted
            ? (manager.isEnabled ? "Accessibility is enabled. Your window layouts and drag snapping are ready." : "Accessibility is enabled. Window management is paused.")
            : "Enable Dozer in System Settings → Privacy & Security → Accessibility. Menu bar hiding works without this permission."
        permissionButton.title = manager.isTrusted ? "Open Accessibility Settings…" : "Enable Accessibility…"
        enabledCheckbox.state = manager.isEnabled ? .on : .off
        dragCheckbox.state = manager.dragSnappingEnabled ? .on : .off
        dragCheckbox.isEnabled = manager.isEnabled
        gapPopup.isEnabled = manager.isEnabled
        gapPopup.selectItem(withTag: Int(manager.gap))
        recorders.forEach { $0.refreshTitle() }
        for (action, label) in shortcutErrors {
            let message = WindowShortcutManager.shared.errors[action] ?? ""
            label.stringValue = message
            label.isHidden = message.isEmpty
        }
    }

    @objc private func navigate(_ sender: NSButton) { selectPage(sender.tag) }
    private func selectPage(_ index: Int) {
        stopRecording()
        tabs.selectTabViewItem(at: index)
        for button in navigation { button.state = button.tag == index ? .on : .off }
        refresh()
    }
    @objc private func toggleIcons() { DozerIcons.shared.toggle() }
    @objc private func openWindows() { selectPage(2) }
    @objc private func runLayout(_ sender: LayoutTileButton) { stopRecording(); WindowManager.shared.execute(sender.layoutAction) }
    @objc private func requestPermission() { WindowManager.shared.requestPermission() }
    @objc private func toggleWindowManagement() {
        stopRecording()
        WindowManager.shared.isEnabled = enabledCheckbox.state == .on
        if WindowManager.shared.isEnabled { WindowShortcutManager.shared.start() }
        else { WindowShortcutManager.shared.stop() }
        refresh()
    }
    @objc private func toggleDrag() { WindowManager.shared.dragSnappingEnabled = dragCheckbox.state == .on; refresh() }
    @objc private func changeGap() { WindowManager.shared.gap = CGFloat(gapPopup.selectedTag()) }
    @objc private func resetShortcuts() { stopRecording(); WindowShortcutManager.shared.restoreDefaults(); refresh() }
    @objc private func openLink(_ sender: NSButton) {
        if let value = sender.identifier?.rawValue, let url = URL(string: value) { NSWorkspace.shared.open(url) }
    }
    @objc private func openLicenses() {
        if let url = Bundle.main.url(forResource: "ThirdPartyNotices", withExtension: "txt") { NSWorkspace.shared.open(url) }
    }

    private func configure(_ button: NSButton, action: Selector) { button.target = self; button.action = action; button.bezelStyle = .rounded }
    private func label(_ text: String, size: CGFloat, weight: NSFont.Weight = .regular) -> NSTextField {
        let field = NSTextField(labelWithString: text)
        field.font = .systemFont(ofSize: size, weight: weight)
        return field
    }
    private func copy(_ text: String) -> NSTextField {
        let field = NSTextField(wrappingLabelWithString: text)
        field.preferredMaxLayoutWidth = 620
        field.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        return field
    }
    private func caption(_ text: String) -> NSTextField {
        let field = copy(text)
        field.font = .systemFont(ofSize: 12)
        field.textColor = .secondaryLabelColor
        return field
    }
    private func eyebrow(_ text: String, symbol: String) -> NSView {
        let image = NSImageView(image: NSImage(systemSymbolName: symbol, accessibilityDescription: nil) ?? NSImage())
        image.contentTintColor = .controlAccentColor
        return horizontal([image, label(text, size: 11, weight: .semibold)])
    }
    private func vertical(spacing: CGFloat = 16) -> NSStackView {
        let stack = NSStackView()
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = spacing
        return stack
    }
    private func horizontal(_ views: [NSView]) -> NSStackView {
        let stack = NSStackView(views: views)
        stack.orientation = .horizontal
        stack.distribution = .fill
        stack.alignment = .centerY
        stack.spacing = 10
        return stack
    }
    private func pageStack() -> NSStackView { vertical(spacing: 16) }
    private func addFullWidth(_ view: NSView, to stack: NSStackView) {
        stack.addArrangedSubview(view)
        view.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
    }
    private func card(_ content: NSView) -> NSView {
        let box = WorkspaceCardView()
        content.translatesAutoresizingMaskIntoConstraints = false
        box.addSubview(content)
        NSLayoutConstraint.activate([
            content.leadingAnchor.constraint(equalTo: box.leadingAnchor, constant: 18),
            content.trailingAnchor.constraint(equalTo: box.trailingAnchor, constant: -18),
            content.topAnchor.constraint(equalTo: box.topAnchor, constant: 18),
            content.bottomAnchor.constraint(equalTo: box.bottomAnchor, constant: -18)
        ])
        return box
    }
    private func scrollPage(_ stack: NSStackView) -> NSScrollView {
        let scroll = NSScrollView()
        scroll.drawsBackground = false
        scroll.hasVerticalScroller = true
        let document = FlippedSettingsView()
        document.translatesAutoresizingMaskIntoConstraints = false
        scroll.documentView = document
        document.addSubview(stack)
        NSLayoutConstraint.activate([
            document.widthAnchor.constraint(equalTo: scroll.contentView.widthAnchor),
            stack.leadingAnchor.constraint(equalTo: document.leadingAnchor, constant: 30),
            stack.trailingAnchor.constraint(equalTo: document.trailingAnchor, constant: -30),
            stack.topAnchor.constraint(equalTo: document.topAnchor, constant: 28),
            stack.bottomAnchor.constraint(equalTo: document.bottomAnchor, constant: -28)
        ])
        for view in stack.arrangedSubviews {
            view.widthAnchor.constraint(lessThanOrEqualTo: stack.widthAnchor).isActive = true
        }
        return scroll
    }
}

private final class WorkspaceCardView: NSView {
    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.cornerRadius = 12
        layer?.borderWidth = 0.5
    }
    required init?(coder: NSCoder) { fatalError("Use init(frame:)") }
    override var wantsUpdateLayer: Bool { true }
    override func updateLayer() {
        layer?.backgroundColor = NSColor.controlBackgroundColor.cgColor
        layer?.borderColor = NSColor.separatorColor.withAlphaComponent(0.5).cgColor
    }
}

private final class LayoutTileButton: NSButton {
    let layoutAction: WindowLayoutAction
    init(action: WindowLayoutAction) {
        layoutAction = action
        super.init(frame: .zero)
        title = action.title
        image = NSImage(systemSymbolName: action.symbolName, accessibilityDescription: nil)?
            .withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: 22, weight: .regular))
        imagePosition = .imageAbove
        imageScaling = .scaleProportionallyDown
        bezelStyle = .regularSquare
        isBordered = false
        wantsLayer = true
        layer?.cornerRadius = 10
        layer?.backgroundColor = NSColor.controlBackgroundColor.cgColor
        layer?.borderWidth = 0.5
        layer?.borderColor = NSColor.separatorColor.cgColor
        font = .systemFont(ofSize: 12, weight: .medium)
        heightAnchor.constraint(equalToConstant: 68).isActive = true
        setAccessibilityIdentifier("layout.\(action.rawValue)")
        setAccessibilityLabel(action.title)
        toolTip = action.title
    }
    required init?(coder: NSCoder) { fatalError("Use init(action:)") }
    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        effectiveAppearance.performAsCurrentDrawingAppearance {
            layer?.backgroundColor = NSColor.controlBackgroundColor.cgColor
            layer?.borderColor = NSColor.separatorColor.cgColor
        }
    }
}
