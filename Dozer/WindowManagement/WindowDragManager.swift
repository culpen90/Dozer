/* This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. https://mozilla.org/MPL/2.0/ */

import AppKit

/// Passive mouse monitoring is active only while window management is enabled
/// and Accessibility has been granted. No keyboard event stream is observed.
final class WindowDragManager {
    private unowned let manager: WindowManager
    private var mouseMonitor: Any?
    private var session: DragSession?
    private var preview: NSPanel?
    private var candidate: (action: WindowLayoutAction, screen: NSScreen)?

    private struct DragSession {
        let target: ManagedWindowTarget
        let initialFrame: CGRect
        let initialPoint: CGPoint
        var hasMoved = false
        var cancelled = false
    }

    init(manager: WindowManager) { self.manager = manager }
    deinit { if let mouseMonitor { NSEvent.removeMonitor(mouseMonitor) } }

    func start() {
        guard mouseMonitor == nil else { return }
        mouseMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .leftMouseDragged, .leftMouseUp, .flagsChanged]) { [weak self] event in
            self?.handle(event)
        }
    }

    func stop() {
        if let mouseMonitor { NSEvent.removeMonitor(mouseMonitor) }
        mouseMonitor = nil
        cancelDrag()
    }

    func cancelDrag() {
        session = nil
        candidate = nil
        preview?.orderOut(nil)
    }

    private func handle(_ event: NSEvent) {
        guard manager.isTrusted, manager.isEnabled, manager.dragSnappingEnabled else { cancelDrag(); return }
        if event.modifierFlags.contains(.option), session != nil {
            session?.cancelled = true
            candidate = nil
            preview?.orderOut(nil)
        }
        switch event.type {
        case .leftMouseDown: begin(at: NSEvent.mouseLocation, event: event)
        case .leftMouseDragged: update(at: NSEvent.mouseLocation)
        case .leftMouseUp: finish()
        default: break
        }
    }

    private func begin(at point: CGPoint, event: NSEvent) {
        cancelDrag()
        guard !event.modifierFlags.contains(.option),
              let target = manager.window(at: point), let frame = manager.frame(of: target),
              frame.width > 40, frame.height > 40 else { return }
        // Resizing at a window border is not a move. Unified title bars can be
        // tall, so use the upper band and confirm an actual AX position change.
        guard point.x > frame.minX + 6, point.x < frame.maxX - 6,
              point.y < frame.maxY - 4, point.y > max(frame.minY + 6, frame.maxY - 100) else { return }
        session = DragSession(target: target, initialFrame: frame, initialPoint: point)
    }

    private func update(at point: CGPoint) {
        guard var session, !session.cancelled,
              manager.isEligible(session.target), let current = manager.frame(of: session.target) else {
            candidate = nil
            preview?.orderOut(nil)
            return
        }
        // Content drags never move the actual window; titlebar resizing changes
        // its dimensions. Only the same, translated window may acquire a target.
        guard abs(current.width - session.initialFrame.width) <= 3,
              abs(current.height - session.initialFrame.height) <= 3 else {
            self.session?.cancelled = true
            candidate = nil
            preview?.orderOut(nil)
            return
        }
        let windowDistance = hypot(current.minX - session.initialFrame.minX, current.minY - session.initialFrame.minY)
        let pointerDistance = hypot(point.x - session.initialPoint.x, point.y - session.initialPoint.y)
        if windowDistance > 4, pointerDistance > 6 { session.hasMoved = true }
        self.session = session
        guard session.hasMoved,
              let screen = NSScreen.screens.first(where: { containsInclusive(point, in: $0.frame) }),
              let action = WindowLayoutGeometry.snapAction(at: point, in: screen.frame),
              let destination = WindowLayoutGeometry.frame(for: action, window: current,
                                                           visibleFrame: screen.visibleFrame, gap: manager.gap) else {
            candidate = nil
            preview?.orderOut(nil)
            return
        }
        candidate = (action, screen)
        showPreview(destination)
    }

    private func finish() {
        update(at: NSEvent.mouseLocation)
        let completedSession = session
        let completedCandidate = candidate
        cancelDrag()
        guard let completedSession, completedSession.hasMoved, !completedSession.cancelled,
              let completedCandidate,
              !NSEvent.modifierFlags.contains(.option) else { return }
        manager.execute(completedCandidate.action, target: completedSession.target, screen: completedCandidate.screen,
                        restoreFrame: completedSession.initialFrame)
    }

    private func showPreview(_ frame: CGRect) {
        if preview == nil {
            let panel = SnapPreviewPanel(contentRect: frame, styleMask: [.borderless, .nonactivatingPanel],
                                         backing: .buffered, defer: false)
            panel.isOpaque = false
            panel.backgroundColor = .clear
            panel.hasShadow = false
            panel.ignoresMouseEvents = true
            panel.level = .floating
            panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle, .transient]
            panel.isReleasedWhenClosed = false
            let content = NSView()
            content.wantsLayer = true
            content.layer?.cornerRadius = 12
            content.layer?.borderWidth = 2
            content.layer?.borderColor = NSColor.controlAccentColor.withAlphaComponent(0.8).cgColor
            content.layer?.backgroundColor = NSColor.controlAccentColor.withAlphaComponent(0.16).cgColor
            panel.contentView = content
            preview = panel
        }
        preview?.setFrame(frame.insetBy(dx: 2, dy: 2), display: true)
        preview?.orderFrontRegardless()
    }

    private func containsInclusive(_ point: CGPoint, in frame: CGRect) -> Bool {
        point.x >= frame.minX && point.x <= frame.maxX && point.y >= frame.minY && point.y <= frame.maxY
    }
}

private final class SnapPreviewPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}
