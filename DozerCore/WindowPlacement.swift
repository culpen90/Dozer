// Adapted from Rectangle 2.0.4 AccessibilityElement.setImmediateFrame().
// Copyright (c) 2019–2026 Ryan Hanson; based on Spectacle,
// Copyright (c) 2017 Eric Czarny. MIT license; see ThirdParty/Rectangle/.
import Foundation
import CoreGraphics

/// Decisions shared by native placement and permission-free placement regressions.
/// Frames use AppKit coordinates; an AX move preserves the frame's upper-left point.
enum WindowPlacementAdjustment {
    struct Result {
        let writesSucceeded: Bool
        /// The last upper-left point submitted to AX, expressed as an AppKit frame.
        /// A write may be applied asynchronously even when it reports failure.
        let lastPositionFrame: CGRect?
    }

    /// Honor an application's advertised minimum before starting asynchronous
    /// placement recovery. An oversized minimum keeps the title bar reachable.
    static func feasibleFrame(requested: CGRect, minimumSize: CGSize?,
                              visibleFrame: CGRect, gap: CGFloat) -> CGRect? {
        guard usable(requested), usable(visibleFrame) else { return nil }
        func minimum(_ value: CGFloat?) -> CGFloat {
            guard let value, value.isFinite, value > 0 else { return 0 }
            return value
        }
        let size = CGSize(width: max(requested.width, minimum(minimumSize?.width)),
                          height: max(requested.height, minimum(minimumSize?.height)))
        guard size != requested.size else { return requested }
        return WindowLayoutGeometry.constrainedFrame(requested: requested, actualSize: size,
                                                     visibleFrame: visibleFrame, gap: gap)
    }

    /// Follow Rectangle's immediate-placement sequence: resize once, move only
    /// when the accepted upper-left point differs, and retry a refused size only
    /// after moving away from the old screen edge. Callers retain their delayed
    /// recovery for applications whose AX writes have not settled synchronously.
    static func perform(requested: CGRect, before: CGRect, visibleFrame: CGRect, gap: CGFloat,
                        readFrame: () -> CGRect?, resize: (CGSize) -> Bool,
                        move: (CGRect) -> Bool) -> Result {
        guard usable(requested), usable(before), usable(visibleFrame) else {
            return Result(writesSucceeded: false, lastPositionFrame: nil)
        }
        var succeeded = true
        var lastPosition: CGRect?

        func resizeWindow(_ size: CGSize) {
            // Evaluate the write even when an earlier operation has failed.
            let didWrite = resize(size)
            succeeded = didWrite && succeeded
        }
        func moveWindow(_ frame: CGRect, from current: CGRect?) {
            if let current, samePosition(current, frame) { return }
            lastPosition = frame
            let didWrite = move(frame)
            succeeded = didWrite && succeeded
        }
        func currentFrame() -> CGRect? {
            guard let frame = readFrame(), usable(frame) else { return nil }
            return frame
        }
        func anchoredFrame(for actualSize: CGSize) -> CGRect {
            WindowLayoutGeometry.constrainedFrame(requested: requested, actualSize: actualSize,
                                                  visibleFrame: visibleFrame, gap: gap) ?? requested
        }

        if sameSize(before.size, requested.size) {
            moveWindow(requested, from: before)
            return Result(writesSucceeded: succeeded, lastPositionFrame: lastPosition)
        }

        resizeWindow(requested.size)
        guard let resized = currentFrame() else {
            // A read failure cannot establish whether the first resize reached
            // the app. Preserve Rectangle's recovery move and final resize.
            moveWindow(requested, from: nil)
            resizeWindow(requested.size)
            return Result(writesSucceeded: succeeded, lastPositionFrame: lastPosition)
        }

        let placedSize = CGSize(width: max(resized.width, requested.width),
                                height: max(resized.height, requested.height))
        let destination = anchoredFrame(for: placedSize)
        if !samePosition(resized, destination) {
            moveWindow(destination, from: resized)
            if !sameSize(resized.size, requested.size) {
                if let current = currentFrame(), !sameSize(current.size, requested.size) {
                    resizeWindow(requested.size)
                    if let settled = currentFrame() {
                        moveWindow(anchoredFrame(for: settled.size), from: settled)
                    }
                }
            }
        }
        return Result(writesSucceeded: succeeded, lastPositionFrame: lastPosition)
    }

    private static func samePosition(_ lhs: CGRect, _ rhs: CGRect) -> Bool {
        abs(lhs.minX - rhs.minX) <= 1 && abs(lhs.maxY - rhs.maxY) <= 1
    }

    private static func sameSize(_ lhs: CGSize, _ rhs: CGSize) -> Bool {
        abs(lhs.width - rhs.width) <= 1 && abs(lhs.height - rhs.height) <= 1
    }

    private static func usable(_ rect: CGRect) -> Bool {
        !rect.isNull && !rect.isInfinite && rect.width > 0 && rect.height > 0
            && [rect.minX, rect.minY, rect.width, rect.height, rect.maxX, rect.maxY].allSatisfy(\.isFinite)
    }
}
