/* This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. https://mozilla.org/MPL/2.0/ */
import AppKit

final class WindowShortcutRecorder: NSButton {
    let layoutAction: WindowLayoutAction
    private(set) var isRecording = false
    var onChange: (() -> Void)?
    private static weak var activeRecorder: WindowShortcutRecorder?
    private var keyMonitor: Any?
    private var resignObserver: NSObjectProtocol?

    override var acceptsFirstResponder: Bool { true }

    init(action: WindowLayoutAction) {
        layoutAction = action
        super.init(frame: .zero)
        bezelStyle = .rounded
        font = .monospacedSystemFont(ofSize: 12, weight: .medium)
        target = self
        self.action = #selector(beginRecording)
        setAccessibilityLabel("Record \(action.title) shortcut")
        setAccessibilityIdentifier("windowShortcut.\(action.rawValue)")
        refreshTitle()
    }

    required init?(coder: NSCoder) { fatalError("Use init(action:)") }

    deinit {
        if isRecording {
            WindowShortcutManager.shared.recordingHandler = nil
            ShortcutManager.shared.recordingHandler = nil
        }
        if let keyMonitor { NSEvent.removeMonitor(keyMonitor) }
        if let resignObserver { NotificationCenter.default.removeObserver(resignObserver) }
    }

    func refreshTitle() {
        title = isRecording ? "Type shortcut…" : WindowShortcutManager.shared.shortcut(for: layoutAction)?.displayString ?? "Record…"
        toolTip = WindowShortcutManager.shared.errors[layoutAction] ?? "Click to record. Escape cancels; Delete clears."
        contentTintColor = WindowShortcutManager.shared.errors[layoutAction] == nil ? nil : .systemOrange
    }

    @objc private func beginRecording() {
        if isRecording { stopRecording(); return }
        Self.activeRecorder?.stopRecording()
        guard ShortcutManager.shared.recordingHandler == nil else {
            showError("Finish recording the menu bar shortcut first.")
            return
        }
        isRecording = true
        Self.activeRecorder = self
        WindowShortcutManager.shared.recordingHandler = { [weak self] shortcut in self?.save(shortcut) }
        ShortcutManager.shared.recordingHandler = { [weak self] in
            self?.showError("That shortcut is assigned to showing menu bar icons.")
        }
        window?.makeFirstResponder(self)
        refreshTitle()
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, self.isRecording, event.window === self.window else { return event }
            self.capture(event)
            return nil
        }
        resignObserver = NotificationCenter.default.addObserver(forName: NSWindow.didResignKeyNotification,
                                                                object: window, queue: .main) { [weak self] _ in
            self?.stopRecording()
        }
    }

    func stopRecording() {
        let wasRecording = isRecording
        isRecording = false
        if wasRecording {
            WindowShortcutManager.shared.recordingHandler = nil
            ShortcutManager.shared.recordingHandler = nil
        }
        if Self.activeRecorder === self { Self.activeRecorder = nil }
        if let keyMonitor { NSEvent.removeMonitor(keyMonitor) }
        keyMonitor = nil
        if let resignObserver { NotificationCenter.default.removeObserver(resignObserver) }
        resignObserver = nil
        refreshTitle()
    }

    private func capture(_ event: NSEvent) {
        if event.keyCode == 53 { stopRecording(); return }
        guard !event.isARepeat else { return }
        let modifiers = KeyboardShortcut.carbonModifiers(event.modifierFlags.intersection(.deviceIndependentFlagsMask))
        if [51, 117].contains(event.keyCode), modifiers == 0 { save(nil); return }
        save(KeyboardShortcut(keyCode: UInt32(event.keyCode), modifiers: modifiers,
                              keyName: KeyboardShortcut.name(for: event)))
    }

    private func save(_ shortcut: KeyboardShortcut?) {
        if WindowShortcutManager.shared.setShortcut(shortcut, for: layoutAction) {
            stopRecording()
            onChange?()
        } else {
            showError(WindowShortcutManager.shared.lastError ?? "Choose another shortcut.")
        }
    }

    private func showError(_ message: String) {
        stopRecording()
        let alert = NSAlert()
        alert.messageText = "Choose another shortcut"
        alert.informativeText = message
        if let window { alert.beginSheetModal(for: window) }
        onChange?()
    }
}
