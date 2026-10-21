// Disposable, standalone native window for Dozer's live window-management checks.
// Build without launching: Scripts/RunWindowFixture.sh --build-only
// Build and launch: Scripts/RunWindowFixture.sh
// Close the window or press Command-Q to remove the fixture. No other app is changed.
import AppKit

final class FixtureDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    private var window: NSWindow!
    private let frameLabel = NSTextField(wrappingLabelWithString: "")
    private var timer: Timer?
    private var lastLoggedFrame: CGRect?
    private let logURL: URL

    init(logURL: URL) { self.logURL = logURL }

    func applicationDidFinishLaunching(_ notification: Notification) {
        let mainMenu = NSMenu()
        let applicationItem = NSMenuItem()
        let applicationMenu = NSMenu()
        applicationMenu.addItem(withTitle: "Quit Window Fixture", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        applicationItem.submenu = applicationMenu
        mainMenu.addItem(applicationItem)
        NSApp.mainMenu = mainMenu

        window = NSWindow(contentRect: CGRect(x: 0, y: 0, width: 700, height: 500),
                          styleMask: [.titled, .closable, .miniaturizable, .resizable],
                          backing: .buffered, defer: false)
        window.title = "Dozer Window Fixture"
        window.identifier = NSUserInterfaceItemIdentifier("DozerWindowFixture")
        window.setAccessibilityIdentifier("DozerWindowFixture")
        window.minSize = CommandLine.arguments.contains("--large-minimum")
            ? CGSize(width: 1000, height: 700) : CGSize(width: 160, height: 120)
        window.isReleasedWhenClosed = false
        window.delegate = self
        buildContent()
        resetFrame()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        recordFrame(reason: "launched", force: true)
        timer = Timer.scheduledTimer(withTimeInterval: 0.15, repeats: true) { [weak self] _ in
            self?.recordFrame(reason: "frameChanged")
        }
        timer?.tolerance = 0.03
        if let timer { RunLoop.main.add(timer, forMode: .common) }
    }

    private func buildContent() {
        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .centerX
        stack.spacing = 16
        stack.translatesAutoresizingMaskIntoConstraints = false
        let heading = NSTextField(labelWithString: "A window made for testing")
        heading.font = .systemFont(ofSize: 20, weight: .semibold)
        heading.lineBreakMode = .byTruncatingTail
        heading.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        let explanation = NSTextField(wrappingLabelWithString:
            "Use Dozer’s layouts, shortcuts, or drag this title bar to a screen edge. This disposable window is the only test target.")
        explanation.alignment = .center
        explanation.textColor = .secondaryLabelColor
        explanation.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        frameLabel.font = .monospacedSystemFont(ofSize: 12, weight: .regular)
        frameLabel.alignment = .center
        frameLabel.setAccessibilityIdentifier("fixtureFrame")
        frameLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        let resetTitle = CommandLine.arguments.contains("--large-minimum") ? "Reset to 1000 × 700" : "Reset to 700 × 500"
        let resetButton = NSButton(title: resetTitle, target: self, action: #selector(resetFrame))
        resetButton.bezelStyle = .rounded
        resetButton.setAccessibilityIdentifier("resetFixtureFrame")
        stack.addArrangedSubview(heading)
        stack.addArrangedSubview(explanation)
        stack.addArrangedSubview(frameLabel)
        stack.addArrangedSubview(resetButton)
        let content = window.contentView!
        content.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.centerXAnchor.constraint(equalTo: content.centerXAnchor),
            stack.centerYAnchor.constraint(equalTo: content.centerYAnchor),
            stack.leadingAnchor.constraint(greaterThanOrEqualTo: content.leadingAnchor, constant: 12),
            stack.trailingAnchor.constraint(lessThanOrEqualTo: content.trailingAnchor, constant: -12),
            stack.widthAnchor.constraint(lessThanOrEqualToConstant: 440),
            explanation.widthAnchor.constraint(equalTo: stack.widthAnchor),
            frameLabel.widthAnchor.constraint(equalTo: stack.widthAnchor),
            heading.widthAnchor.constraint(lessThanOrEqualTo: stack.widthAnchor)
        ])
    }

    @objc private func resetFrame() {
        let visible = (window.screen ?? NSScreen.main ?? NSScreen.screens.first)?.visibleFrame
            ?? CGRect(x: 0, y: 0, width: 1200, height: 800)
        let width = min(max(700, window.minSize.width), visible.width)
        let height = min(max(500, window.minSize.height), visible.height)
        window.setFrame(CGRect(x: visible.midX - width / 2, y: visible.midY - height / 2,
                               width: width, height: height), display: true)
        recordFrame(reason: "reset", force: true)
    }

    func windowDidMove(_ notification: Notification) { recordFrame(reason: "moved") }
    func windowDidResize(_ notification: Notification) { recordFrame(reason: "resized") }
    func windowDidEndLiveResize(_ notification: Notification) { recordFrame(reason: "endLiveResize", force: true) }
    func windowWillClose(_ notification: Notification) { recordFrame(reason: "closed", force: true) }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }

    func applicationWillTerminate(_ notification: Notification) {
        timer?.invalidate()
        recordFrame(reason: "terminated", force: true)
    }

    private func recordFrame(reason: String, force: Bool = false) {
        guard let window else { return }
        let frame = window.frame
        guard force || lastLoggedFrame != frame else { return }
        lastLoggedFrame = frame
        frameLabel.stringValue = "x: \(Int(frame.minX))   y: \(Int(frame.minY))\n\(Int(frame.width)) × \(Int(frame.height)) points"
        let primaryTop = NSScreen.screens.first?.frame.maxY ?? 0
        var document: [String: Any] = [
            "schemaVersion": 1,
            "title": window.title,
            "pid": ProcessInfo.processInfo.processIdentifier,
            "windowNumber": window.windowNumber,
            "reason": reason,
            "timestamp": ISO8601DateFormatter().string(from: Date()),
            "frame": dictionary(frame),
            "nativeAccessibilityFrame": dictionary(window.accessibilityFrame()),
            "minimumSize": ["width": window.minSize.width, "height": window.minSize.height],
            "accessibilityFrame": dictionary(CGRect(x: frame.minX, y: primaryTop - frame.maxY,
                                                       width: frame.width, height: frame.height)),
            "coordinateSystem": "AppKit points; y increases upward",
            "isVisible": window.isVisible,
            "isMiniaturized": window.isMiniaturized
        ]
        if let screen = window.screen {
            document["screenFrame"] = dictionary(screen.frame)
            document["visibleFrame"] = dictionary(screen.visibleFrame)
        }
        do {
            let data = try JSONSerialization.data(withJSONObject: document, options: [.prettyPrinted, .sortedKeys])
            try FileManager.default.createDirectory(at: logURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try data.write(to: logURL, options: .atomic)
        } catch {
            FileHandle.standardError.write(Data("Window fixture could not record its frame: \(error.localizedDescription)\n".utf8))
        }
    }

    private func dictionary(_ rect: CGRect) -> [String: Double] {
        ["x": Double(rect.minX), "y": Double(rect.minY), "width": Double(rect.width), "height": Double(rect.height)]
    }

}

let arguments = CommandLine.arguments
let logPath: String
if let index = arguments.firstIndex(of: "--frame-log"), arguments.indices.contains(index + 1) {
    logPath = arguments[index + 1]
} else {
    logPath = FileManager.default.currentDirectoryPath + "/build/window-fixture-frame.json"
}
let application = NSApplication.shared
let fixtureDelegate = FixtureDelegate(logURL: URL(fileURLWithPath: logPath))
application.delegate = fixtureDelegate
application.setActivationPolicy(.regular)
application.run()
