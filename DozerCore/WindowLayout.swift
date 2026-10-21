// Portions adapted from Rectangle, Copyright (c) 2019–2026 Ryan Hanson,
// based on Spectacle, Copyright (c) 2017 Eric Czarny. MIT license.
// See ThirdParty/Rectangle/LICENSE and PROVENANCE.md for sources and modifications.
import Foundation
import CoreGraphics

enum WindowLayoutAction: String, CaseIterable {
    case leftHalf, rightHalf, topHalf, bottomHalf
    case topLeft, topRight, bottomLeft, bottomRight
    case firstThird, centerThird, lastThird, firstTwoThirds, lastTwoThirds
    case firstVerticalSixth, secondVerticalSixth, thirdVerticalSixth, fourthVerticalSixth, fifthVerticalSixth, lastVerticalSixth
    case maximize, almostMaximize, center, larger, smaller
    case nextDisplay, previousDisplay, restore

    var title: String {
        switch self {
        case .leftHalf: return "Left Half"
        case .rightHalf: return "Right Half"
        case .topHalf: return "Top Half"
        case .bottomHalf: return "Bottom Half"
        case .topLeft: return "Top Left"
        case .topRight: return "Top Right"
        case .bottomLeft: return "Bottom Left"
        case .bottomRight: return "Bottom Right"
        case .firstThird: return "First Third"
        case .centerThird: return "Center Third"
        case .lastThird: return "Last Third"
        case .firstTwoThirds: return "First Two Thirds"
        case .lastTwoThirds: return "Last Two Thirds"
        case .firstVerticalSixth: return "First Sixth"
        case .secondVerticalSixth: return "Second Sixth"
        case .thirdVerticalSixth: return "Third Sixth"
        case .fourthVerticalSixth: return "Fourth Sixth"
        case .fifthVerticalSixth: return "Fifth Sixth"
        case .lastVerticalSixth: return "Last Sixth"
        case .maximize: return "Maximize"
        case .almostMaximize: return "Almost Maximize"
        case .center: return "Center"
        case .larger: return "Make Larger"
        case .smaller: return "Make Smaller"
        case .nextDisplay: return "Next Display"
        case .previousDisplay: return "Previous Display"
        case .restore: return "Restore"
        }
    }

    var symbolName: String {
        switch self {
        case .leftHalf: return "rectangle.lefthalf.inset.filled"
        case .rightHalf: return "rectangle.righthalf.inset.filled"
        case .topHalf: return "rectangle.tophalf.inset.filled"
        case .bottomHalf: return "rectangle.bottomhalf.inset.filled"
        case .topLeft: return "rectangle.inset.topleft.filled"
        case .topRight: return "rectangle.inset.topright.filled"
        case .bottomLeft: return "rectangle.inset.bottomleft.filled"
        case .bottomRight: return "rectangle.inset.bottomright.filled"
        case .firstThird, .firstTwoThirds: return "rectangle.leadingthird.inset.filled"
        case .centerThird: return "rectangle.center.inset.filled"
        case .lastThird, .lastTwoThirds: return "rectangle.trailingthird.inset.filled"
        case .firstVerticalSixth, .secondVerticalSixth, .thirdVerticalSixth,
             .fourthVerticalSixth, .fifthVerticalSixth, .lastVerticalSixth: return "rectangle.split.3x1"
        case .maximize: return "arrow.up.left.and.arrow.down.right"
        case .almostMaximize: return "arrow.up.left.and.down.right.and.arrow.up.right.and.down.left"
        case .center: return "arrow.up.and.down.and.arrow.left.and.right"
        case .larger: return "plus.magnifyingglass"
        case .smaller: return "minus.magnifyingglass"
        case .nextDisplay, .previousDisplay: return "rectangle.on.rectangle"
        case .restore: return "arrow.uturn.backward"
        }
    }

    static let verticalSixths: [WindowLayoutAction] = [.firstVerticalSixth, .secondVerticalSixth,
        .thirdVerticalSixth, .fourthVerticalSixth, .fifthVerticalSixth, .lastVerticalSixth]

    var group: String {
        switch self {
        case .leftHalf, .rightHalf, .topHalf, .bottomHalf: return "Halves"
        case .topLeft, .topRight, .bottomLeft, .bottomRight: return "Quarters"
        case .firstThird, .centerThird, .lastThird, .firstTwoThirds, .lastTwoThirds: return "Thirds"
        case .firstVerticalSixth, .secondVerticalSixth, .thirdVerticalSixth,
             .fourthVerticalSixth, .fifthVerticalSixth, .lastVerticalSixth: return "Sixths"
        case .maximize, .almostMaximize, .center, .larger, .smaller: return "Size & Position"
        case .nextDisplay, .previousDisplay: return "Displays"
        case .restore: return "History"
        }
    }
}

/// Rectangle stores the resulting half action, or the requested sixth action
/// plus its resolved ordinal, only after the window has reached the layout.
struct WindowLayoutRepeatState {
    let action: WindowLayoutAction
    let layout: WindowLayoutAction
    let frame: CGRect

    init(command: WindowLayoutAction, layout: WindowLayoutAction, frame: CGRect) {
        switch command {
        case .leftHalf, .rightHalf, .topHalf, .bottomHalf: action = layout
        default: action = command
        }
        self.layout = layout
        self.frame = frame
    }
}

/// Some toolkits identify their top-level window through its standard-window
/// subrole while exposing a text-field role (notably Emacs 28).
enum WindowAccessibilityClassification {
    static func isWindow(role: String?, subrole: String?) -> Bool {
        role == "AXWindow" || subrole == "AXStandardWindow"
    }
}

/// Pure geometry in AppKit coordinates: y increases upward. Accessibility coordinates
/// must be converted by the caller using the primary display's height.
enum WindowLayoutGeometry {
    /// Adapted from Rectangle 2.0.4's switchSides and VerticalSixthCalculation.
    /// Half switching requires the exact last frame. Sixth cycling follows the
    /// previous ordinal even if the window has moved, as in upstream.
    static func repeatedAction(for action: WindowLayoutAction, window: CGRect,
                               previous: WindowLayoutRepeatState?, enabled: Bool) -> WindowLayoutAction {
        guard enabled, let previous, previous.action == action, isUsable(window) else { return action }
        switch action {
        case .leftHalf: return previous.frame == window ? .rightHalf : action
        case .rightHalf: return previous.frame == window ? .leftHalf : action
        case .topHalf: return previous.frame == window ? .bottomHalf : action
        case .bottomHalf: return previous.frame == window ? .topHalf : action
        case .firstVerticalSixth, .lastVerticalSixth:
            guard let ordinal = WindowLayoutAction.verticalSixths.firstIndex(of: previous.layout) else { return action }
            let step = action == .firstVerticalSixth ? 1 : 5
            return WindowLayoutAction.verticalSixths[(ordinal + step) % 6]
        default: return action
        }
    }

    static func frame(for action: WindowLayoutAction, window: CGRect,
                      visibleFrame screen: CGRect, gap: CGFloat) -> CGRect? {
        guard isUsable(screen), isUsable(window) else { return nil }
        var rect = screen
        switch action {
        case .leftHalf: rect = tile(in: screen, x: 0, y: 0, columns: 2, rows: 1)
        case .rightHalf: rect = tile(in: screen, x: 1, y: 0, columns: 2, rows: 1)
        case .topHalf: rect = tile(in: screen, x: 0, y: 1, columns: 1, rows: 2)
        case .bottomHalf: rect = tile(in: screen, x: 0, y: 0, columns: 1, rows: 2)
        case .topLeft: rect = tile(in: screen, x: 0, y: 1, columns: 2, rows: 2)
        case .topRight: rect = tile(in: screen, x: 1, y: 1, columns: 2, rows: 2)
        case .bottomLeft: rect = tile(in: screen, x: 0, y: 0, columns: 2, rows: 2)
        case .bottomRight: rect = tile(in: screen, x: 1, y: 0, columns: 2, rows: 2)
        case .firstThird, .centerThird, .lastThird, .firstTwoThirds, .lastTwoThirds:
            // Rectangle rotates thirds on portrait displays; "first" is then the top.
            let first = action == .firstThird || action == .firstTwoThirds
            let middle = action == .centerThird
            let count = action == .firstTwoThirds || action == .lastTwoThirds ? 2 : 1
            let index = first ? 0 : middle ? 1 : 3 - count
            if screen.width >= screen.height {
                rect = tile(in: screen, x: index, y: 0, columns: 3, rows: 1, columnSpan: count)
            } else {
                rect = tile(in: screen, x: 0, y: 3 - index - count, columns: 1, rows: 3, rowSpan: count)
            }
        case .firstVerticalSixth, .secondVerticalSixth, .thirdVerticalSixth,
             .fourthVerticalSixth, .fifthVerticalSixth, .lastVerticalSixth:
            guard let ordinal = WindowLayoutAction.verticalSixths.firstIndex(of: action) else { return nil }
            if screen.width > screen.height {
                // Upstream uses floor at both sixth boundaries, including the
                // final boundary, on fractional as well as odd screen sizes.
                let start = floor(screen.width * CGFloat(ordinal) / 6)
                let end = floor(screen.width * CGFloat(ordinal + 1) / 6)
                rect = CGRect(x: screen.minX + start, y: screen.minY, width: end - start, height: screen.height)
            } else {
                let start = floor(screen.height * CGFloat(ordinal) / 6)
                let end = floor(screen.height * CGFloat(ordinal + 1) / 6)
                rect = CGRect(x: screen.minX, y: screen.maxY - end, width: screen.width, height: end - start)
            }
        case .maximize: break
        case .almostMaximize:
            rect = centered(size: CGSize(width: round(screen.width * 0.9), height: round(screen.height * 0.9)), in: screen)
        case .center: return centered(size: window.size, in: screen)
        case .larger, .smaller:
            // Rectangle's default step is 30 points, centered around the current window.
            let step: CGFloat = action == .larger ? 30 : -30
            let size = CGSize(width: min(screen.width, max(min(160, window.width), window.width + step)),
                              height: min(screen.height, max(min(100, window.height), window.height + step)))
            rect = CGRect(x: window.midX - size.width / 2, y: window.midY - size.height / 2,
                          width: size.width, height: size.height)
            return contained(rect, in: screen)
        case .nextDisplay, .previousDisplay, .restore: return nil
        }
        // Upstream's sixth subactions declare shared edges explicitly. The
        // floored final boundary can sit less than a point inside a fractional
        // display, which must still receive a full outer gap.
        let sharedEdges: (left: Bool, right: Bool, bottom: Bool, top: Bool)? =
            WindowLayoutAction.verticalSixths.firstIndex(of: action).map { ordinal in
                if screen.width > screen.height {
                    return (ordinal > 0, ordinal < 5, false, false)
                }
                return (false, false, ordinal < 5, ordinal > 0)
            }
        return applyGaps(rect, in: screen, gap: gap, sharedEdges: sharedEdges)
    }

    /// Greatest intersection wins. Fully offscreen windows use the nearest display center.
    static func screenIndex(for window: CGRect, screens: [CGRect]) -> Int? {
        guard isUsable(window) else { return nil }
        let usable = screens.indices.filter { isUsable(screens[$0]) }
        guard var best = usable.first else { return nil }
        var bestArea: CGFloat = -1
        var bestDistance = CGFloat.infinity
        for index in usable {
            let screen = screens[index]
            let overlap = window.intersection(screen)
            let area = overlap.isNull ? 0 : overlap.width * overlap.height
            let distance = hypot(window.midX - screen.midX, window.midY - screen.midY)
            if area > bestArea || (area == bestArea && distance < bestDistance) {
                best = index
                bestArea = area
                bestDistance = distance
            }
        }
        return best
    }

    /// Adapted from Rectangle's DisplayTransfer: retain edge attachment and relative
    /// centers, fit oversized windows, and handle landscape/portrait transitions.
    static func movedFrame(window: CGRect, from source: CGRect, to destination: CGRect, gap: CGFloat = 0) -> CGRect {
        guard isUsable(window), isUsable(source), isUsable(destination) else { return window }
        let tolerance: CGFloat = 4 + (gap.isFinite ? max(0, min(gap, min(source.width, source.height) / 4)) : 0)
        var horizontal = transfer(window: (window.minX, window.width), source: (source.minX, source.width),
                                  destination: (destination.minX, destination.width), edgeTolerance: tolerance)
        var vertical = transfer(window: (window.minY, window.height), source: (source.minY, source.height),
                                destination: (destination.minY, destination.height), edgeTolerance: tolerance)
        let changesOrientation = (source.width > source.height && destination.height > destination.width)
            || (source.height > source.width && destination.width > destination.height)
        if changesOrientation {
            if horizontal.contact == .both, vertical.contact.isOneEdge, window.width < horizontal.span.length {
                horizontal.span = (destination.midX - window.width / 2, window.width)
            } else if vertical.contact == .both, horizontal.contact.isOneEdge, window.height < vertical.span.length {
                vertical.span = (destination.midY - window.height / 2, window.height)
            }
        }
        let result = CGRect(x: horizontal.span.origin, y: vertical.span.origin,
                            width: horizontal.span.length, height: vertical.span.length)
        return isUsable(result) ? contained(result, in: destination) : centered(size: window.size, in: destination)
    }

    /// An application can accept a different size from the requested layout. Keep
    /// that accepted size on screen and attached to the requested edge. If the
    /// application's minimum exceeds the display, keep its title bar reachable.
    static func constrainedFrame(requested: CGRect, actualSize: CGSize,
                                 visibleFrame screen: CGRect, gap: CGFloat = 0) -> CGRect? {
        guard isUsable(requested), isUsable(screen),
              actualSize.width.isFinite, actualSize.height.isFinite,
              actualSize.width > 0, actualSize.height > 0 else { return nil }
        let tolerance: CGFloat = 4 + (gap.isFinite ? max(0, min(gap, min(screen.width, screen.height) / 4)) : 0)
        func origin(requested: Span, actualLength: CGFloat, screen: Span, keepEndWhenOversized: Bool) -> CGFloat {
            let slack = screen.length - actualLength
            guard slack >= 0 else {
                return keepEndWhenOversized ? screen.origin + screen.length - actualLength : screen.origin
            }
            let startInset = requested.origin - screen.origin
            let endInset = screen.origin + screen.length - requested.origin - requested.length
            let againstStart = startInset <= tolerance
            let againstEnd = endInset <= tolerance
            if againstStart && !againstEnd { return screen.origin + clamp(startInset, 0, slack) }
            if againstEnd && !againstStart { return screen.origin + slack - clamp(endInset, 0, slack) }
            let centeredOrigin = requested.origin + requested.length / 2 - actualLength / 2
            return clamp(centeredOrigin, screen.origin, screen.origin + slack)
        }
        let rect = CGRect(x: origin(requested: (requested.minX, requested.width), actualLength: actualSize.width,
                                    screen: (screen.minX, screen.width), keepEndWhenOversized: false),
                          y: origin(requested: (requested.minY, requested.height), actualLength: actualSize.height,
                                    screen: (screen.minY, screen.height), keepEndWhenOversized: true),
                          width: actualSize.width, height: actualSize.height)
        return isUsable(rect) ? rect : nil
    }

    static func snapAction(at point: CGPoint, in frame: CGRect,
                           threshold: CGFloat = 18) -> WindowLayoutAction? {
        guard isUsable(frame), point.x.isFinite, point.y.isFinite, threshold.isFinite, threshold > 0,
              point.x >= frame.minX, point.x <= frame.maxX,
              point.y >= frame.minY, point.y <= frame.maxY else { return nil }
        let edge = min(threshold, min(frame.width, frame.height) / 4)
        let left = point.x <= frame.minX + edge, right = point.x >= frame.maxX - edge
        let top = point.y >= frame.maxY - edge, bottom = point.y <= frame.minY + edge
        if left && top { return .topLeft }
        if right && top { return .topRight }
        if left && bottom { return .bottomLeft }
        if right && bottom { return .bottomRight }
        if left { return .leftHalf }
        if right { return .rightHalf }
        if top { return .maximize }
        if bottom { return .bottomHalf }
        return nil
    }

    private static func isUsable(_ rect: CGRect) -> Bool {
        !rect.isNull && !rect.isInfinite && rect.origin.x.isFinite && rect.origin.y.isFinite
            && rect.width.isFinite && rect.height.isFinite && rect.size.width > 0 && rect.size.height > 0
            && rect.maxX.isFinite && rect.maxY.isFinite
    }

    private static func tile(in screen: CGRect, x: Int, y: Int, columns: Int, rows: Int,
                             columnSpan: Int = 1, rowSpan: Int = 1) -> CGRect {
        // Boundaries share rounding, eliminating seams on odd-sized displays.
        let x0 = floor(screen.width * CGFloat(x) / CGFloat(columns))
        let x1 = x + columnSpan == columns ? screen.width : floor(screen.width * CGFloat(x + columnSpan) / CGFloat(columns))
        let y0 = floor(screen.height * CGFloat(y) / CGFloat(rows))
        let y1 = y + rowSpan == rows ? screen.height : floor(screen.height * CGFloat(y + rowSpan) / CGFloat(rows))
        return CGRect(x: screen.minX + x0, y: screen.minY + y0, width: x1 - x0, height: y1 - y0)
    }

    private static func centered(size: CGSize, in screen: CGRect) -> CGRect {
        let size = CGSize(width: min(size.width, screen.width), height: min(size.height, screen.height))
        return CGRect(x: screen.minX + round((screen.width - size.width) / 2),
                      y: screen.minY + round((screen.height - size.height) / 2),
                      width: size.width, height: size.height)
    }

    private static func contained(_ window: CGRect, in screen: CGRect) -> CGRect {
        let width = min(window.width, screen.width), height = min(window.height, screen.height)
        return CGRect(x: clamp(window.minX, screen.minX, screen.maxX - width),
                      y: clamp(window.minY, screen.minY, screen.maxY - height), width: width, height: height)
    }

    /// Rectangle's GapCalculation gives shared tile edges half a gap, so adjacent
    /// windows are separated by one gap while outer screen edges retain a full gap.
    private static func applyGaps(_ rect: CGRect, in screen: CGRect, gap: CGFloat,
                                  sharedEdges: (left: Bool, right: Bool, bottom: Bool, top: Bool)? = nil) -> CGRect? {
        guard isUsable(rect) else { return nil }
        let gap = gap.isFinite ? min(max(0, gap), min(rect.width, rect.height) / 4) : 0
        let left = (sharedEdges?.left ?? (rect.minX > screen.minX)) ? gap / 2 : gap
        let right = (sharedEdges?.right ?? (rect.maxX < screen.maxX)) ? gap / 2 : gap
        let bottom = (sharedEdges?.bottom ?? (rect.minY > screen.minY)) ? gap / 2 : gap
        let top = (sharedEdges?.top ?? (rect.maxY < screen.maxY)) ? gap / 2 : gap
        return CGRect(x: rect.minX + left, y: rect.minY + bottom,
                      width: rect.width - left - right, height: rect.height - bottom - top)
    }

    private typealias Span = (origin: CGFloat, length: CGFloat)
    private enum Contact {
        case neither, start, end, both
        var isOneEdge: Bool { self == .start || self == .end }
    }

    private static func transfer(window: Span, source: Span, destination: Span, edgeTolerance: CGFloat) -> (span: Span, contact: Contact) {
        let startInset = window.origin - source.origin
        let endInset = (source.origin + source.length) - (window.origin + window.length)
        let againstStart = startInset <= edgeTolerance, againstEnd = endInset <= edgeTolerance
        if againstStart, againstEnd {
            let start = clamp(startInset, 0, destination.length / 2)
            let end = clamp(endInset, 0, destination.length / 2)
            return ((destination.origin + start, destination.length - start - end), .both)
        }
        let length = min(window.length, destination.length)
        let slack = destination.length - length
        if againstStart { return ((destination.origin + clamp(startInset, 0, slack), length), .start) }
        if againstEnd { return ((destination.origin + destination.length - length - clamp(endInset, 0, slack), length), .end) }
        let centerFraction = (window.origin + window.length / 2 - source.origin) / source.length
        let origin = destination.origin + centerFraction * destination.length - length / 2
        return ((clamp(origin, destination.origin, destination.origin + slack), length), .neither)
    }

    private static func clamp(_ value: CGFloat, _ lower: CGFloat, _ upper: CGFloat) -> CGFloat {
        min(max(value, lower), upper)
    }
}
