import XCTest
import CoreGraphics
@testable import DozerCore

final class WindowLayoutTests: XCTestCase {
    private let screen = CGRect(x: -1600, y: -240, width: 1601, height: 1001)
    private let window = CGRect(x: -1400, y: 0, width: 640, height: 480)

    private func frame(_ action: WindowLayoutAction, gap: CGFloat = 0) throws -> CGRect {
        try XCTUnwrap(WindowLayoutGeometry.frame(for: action, window: window, visibleFrame: screen, gap: gap))
    }

    func testHalvesShareTheirBoundaryOnOddDimensionsAndNegativeOrigins() throws {
        let left = try frame(.leftHalf), right = try frame(.rightHalf)
        XCTAssertEqual(left, CGRect(x: -1600, y: -240, width: 800, height: 1001))
        XCTAssertEqual(right, CGRect(x: -800, y: -240, width: 801, height: 1001))
        XCTAssertEqual(left.maxX, right.minX)
        let top = try frame(.topHalf), bottom = try frame(.bottomHalf)
        XCTAssertEqual(top.minY, bottom.maxY)
        XCTAssertEqual(top.maxY, screen.maxY)
        XCTAssertEqual(bottom.minY, screen.minY)
        XCTAssertEqual(top.height + bottom.height, screen.height)
    }

    func testQuartersUseAppKitTopAndBottomCoordinates() throws {
        let topLeft = try frame(.topLeft), topRight = try frame(.topRight)
        let bottomLeft = try frame(.bottomLeft), bottomRight = try frame(.bottomRight)
        XCTAssertEqual(topLeft.maxY, screen.maxY)
        XCTAssertEqual(topLeft.minY, bottomLeft.maxY)
        XCTAssertEqual(bottomLeft.minY, screen.minY)
        XCTAssertEqual(topLeft.maxX, topRight.minX)
        XCTAssertEqual(bottomLeft.maxX, bottomRight.minX)
        XCTAssertEqual(topRight.maxX, screen.maxX)
        XCTAssertEqual([topLeft, topRight, bottomLeft, bottomRight].reduce(CGFloat(0)) { $0 + $1.width * $1.height }, screen.width * screen.height)
    }

    func testThirdsCoverScreenAndTwoThirdsCombineTheSameBoundaries() throws {
        let first = try frame(.firstThird), center = try frame(.centerThird), last = try frame(.lastThird)
        XCTAssertEqual(first.minX, screen.minX)
        XCTAssertEqual(first.maxX, center.minX)
        XCTAssertEqual(center.maxX, last.minX)
        XCTAssertEqual(last.maxX, screen.maxX)
        XCTAssertEqual(try frame(.firstTwoThirds), first.union(center))
        XCTAssertEqual(try frame(.lastTwoThirds), center.union(last))
    }

    func testPortraitThirdsRunFromTopToBottom() throws {
        let portrait = CGRect(x: 1600, y: -800, width: 801, height: 1601)
        let first = try XCTUnwrap(WindowLayoutGeometry.frame(for: .firstThird, window: window, visibleFrame: portrait, gap: 0))
        let center = try XCTUnwrap(WindowLayoutGeometry.frame(for: .centerThird, window: window, visibleFrame: portrait, gap: 0))
        let last = try XCTUnwrap(WindowLayoutGeometry.frame(for: .lastThird, window: window, visibleFrame: portrait, gap: 0))
        XCTAssertEqual(first.maxY, portrait.maxY)
        XCTAssertEqual(first.minY, center.maxY)
        XCTAssertEqual(center.minY, last.maxY)
        XCTAssertEqual(last.minY, portrait.minY)
        XCTAssertEqual(first.width, portrait.width)
    }

    func testSharedGapsStayOneGapWideAndOuterGapsStayFullSize() throws {
        let left = try frame(.leftHalf, gap: 12), right = try frame(.rightHalf, gap: 12)
        XCTAssertEqual(left.minX - screen.minX, 12)
        XCTAssertEqual(screen.maxX - right.maxX, 12)
        XCTAssertEqual(right.minX - left.maxX, 12)
        XCTAssertEqual(left.minY - screen.minY, 12)
        XCTAssertEqual(screen.maxY - left.maxY, 12)
        XCTAssertEqual(try frame(.maximize, gap: 12), screen.insetBy(dx: 12, dy: 12))
    }

    func testCenterRetainsSizeAndFitsOversizedWindows() throws {
        let centered = try frame(.center, gap: 30)
        XCTAssertEqual(centered.size, window.size)
        XCTAssertEqual(centered.midX, screen.midX, accuracy: 0.5)
        XCTAssertEqual(centered.midY, screen.midY, accuracy: 0.5)
        let oversized = CGRect(x: -5000, y: -2000, width: 10000, height: 8000)
        XCTAssertEqual(WindowLayoutGeometry.frame(for: .center, window: oversized, visibleFrame: screen, gap: 0), screen)
    }

    func testAlmostMaximizeUsesNinetyPercentAndCenters() throws {
        let result = try frame(.almostMaximize)
        XCTAssertEqual(result.width, round(screen.width * 0.9))
        XCTAssertEqual(result.height, round(screen.height * 0.9))
        XCTAssertEqual(result.midX, screen.midX, accuracy: 0.5)
        XCTAssertEqual(result.midY, screen.midY, accuracy: 0.5)
    }

    func testLargerAndSmallerKeepCenterAndBoundedSizes() throws {
        let larger = try frame(.larger), smaller = try frame(.smaller)
        XCTAssertEqual(larger.size, CGSize(width: 670, height: 510))
        XCTAssertEqual(smaller.size, CGSize(width: 610, height: 450))
        XCTAssertEqual(larger.midX, window.midX)
        XCTAssertEqual(smaller.midY, window.midY)
        let tiny = CGRect(x: screen.minX, y: screen.minY, width: 161, height: 101)
        let result = try XCTUnwrap(WindowLayoutGeometry.frame(for: .smaller, window: tiny, visibleFrame: screen, gap: 0))
        XCTAssertEqual(result.size, CGSize(width: 160, height: 100))
        XCTAssertTrue(screen.contains(result))
    }

    func testScreenSelectionUsesLargestOverlapThenNearestForOffscreenWindow() {
        let screens = [CGRect(x: 0, y: 0, width: 1000, height: 800), CGRect(x: -1200, y: -200, width: 1200, height: 900)]
        XCTAssertEqual(WindowLayoutGeometry.screenIndex(for: CGRect(x: -200, y: 0, width: 600, height: 400), screens: screens), 0)
        XCTAssertEqual(WindowLayoutGeometry.screenIndex(for: CGRect(x: -900, y: -100, width: 1000, height: 400), screens: screens), 1)
        XCTAssertEqual(WindowLayoutGeometry.screenIndex(for: CGRect(x: -4000, y: -1000, width: 200, height: 100), screens: screens), 1)
        XCTAssertNil(WindowLayoutGeometry.screenIndex(for: window, screens: []))
        XCTAssertNil(WindowLayoutGeometry.screenIndex(for: .null, screens: screens))
        XCTAssertEqual(WindowLayoutGeometry.screenIndex(for: window, screens: [.null, screen]), 1)
    }

    func testDisplayTransferRetainsRelativeCenterAndEdges() {
        let source = CGRect(x: 0, y: 0, width: 1600, height: 1000)
        let destination = CGRect(x: -2000, y: 500, width: 2000, height: 1200)
        let centered = CGRect(x: 600, y: 350, width: 400, height: 300)
        XCTAssertEqual(WindowLayoutGeometry.movedFrame(window: centered, from: source, to: destination),
                       CGRect(x: -1200, y: 950, width: 400, height: 300))
        let topLeft = CGRect(x: 0, y: 700, width: 400, height: 300)
        XCTAssertEqual(WindowLayoutGeometry.movedFrame(window: topLeft, from: source, to: destination),
                       CGRect(x: -2000, y: 1400, width: 400, height: 300))
        XCTAssertEqual(WindowLayoutGeometry.movedFrame(window: source, from: source, to: destination), destination)
    }

    func testDisplayTransferFitsSmallerDisplayAndHandlesOrientationChange() {
        let source = CGRect(x: 0, y: 0, width: 1600, height: 1000)
        let destination = CGRect(x: 1600, y: -400, width: 900, height: 1600)
        let leftHalf = CGRect(x: 0, y: 0, width: 800, height: 1000)
        XCTAssertEqual(WindowLayoutGeometry.movedFrame(window: leftHalf, from: source, to: destination),
                       CGRect(x: 1600, y: -100, width: 800, height: 1000))
        let small = CGRect(x: -1000, y: -500, width: 500, height: 400)
        let result = WindowLayoutGeometry.movedFrame(window: source, from: source, to: small)
        XCTAssertEqual(result, small)
        XCTAssertEqual(WindowLayoutGeometry.movedFrame(window: window, from: .null, to: small), window)
    }

    func testDisplayTransferKeepsGappedHalfAttachedOnUnequalDisplays() throws {
        let source = CGRect(x: 0, y: 0, width: 1600, height: 1000)
        let destination = CGRect(x: -2000, y: 500, width: 2000, height: 1200)
        let half = try XCTUnwrap(WindowLayoutGeometry.frame(for: .leftHalf, window: window, visibleFrame: source, gap: 12))
        let result = WindowLayoutGeometry.movedFrame(window: half, from: source, to: destination, gap: 12)
        XCTAssertEqual(result.minX, destination.minX + 12)
        XCTAssertEqual(result.minY, destination.minY + 12)
        XCTAssertEqual(result.maxY, destination.maxY - 12)
        XCTAssertEqual(result.width, half.width)
        XCTAssertTrue(destination.contains(result))
    }

    func testConstrainedQuarterAlignsAcceptedMinimumSizeToRequestedEdges() throws {
        let screen = CGRect(x: -1000, y: -800, width: 1000, height: 800)
        let minimum = CGSize(width: 700, height: 600)
        let checks: [(WindowLayoutAction, CGPoint)] = [
            (.bottomRight, CGPoint(x: -708, y: -792)),
            (.bottomLeft, CGPoint(x: -992, y: -792)),
            (.topRight, CGPoint(x: -708, y: -608)),
            (.topLeft, CGPoint(x: -992, y: -608))
        ]
        for (action, origin) in checks {
            let requested = try XCTUnwrap(WindowLayoutGeometry.frame(for: action, window: window, visibleFrame: screen, gap: 8))
            let constrained = try XCTUnwrap(WindowLayoutGeometry.constrainedFrame(requested: requested,
                                                    actualSize: minimum, visibleFrame: screen, gap: 8))
            XCTAssertEqual(constrained.origin, origin, action.title)
            XCTAssertEqual(constrained.size, minimum)
            XCTAssertTrue(screen.contains(constrained))
        }
    }

    func testConstrainedCenteredWindowRetainsCenterAndOversizedTitleBarStaysReachable() throws {
        let requested = CGRect(x: -1200, y: -40, width: 400, height: 300)
        let fitted = try XCTUnwrap(WindowLayoutGeometry.constrainedFrame(requested: requested,
                                     actualSize: CGSize(width: 800, height: 500), visibleFrame: screen))
        XCTAssertEqual(fitted.midX, requested.midX)
        XCTAssertEqual(fitted.midY, requested.midY)
        XCTAssertTrue(screen.contains(fitted))
        let oversized = try XCTUnwrap(WindowLayoutGeometry.constrainedFrame(requested: requested,
                                      actualSize: CGSize(width: 2000, height: 1400), visibleFrame: screen))
        XCTAssertEqual(oversized.minX, screen.minX)
        XCTAssertEqual(oversized.maxY, screen.maxY)
        XCTAssertEqual(oversized.size, CGSize(width: 2000, height: 1400))
        XCTAssertNil(WindowLayoutGeometry.constrainedFrame(requested: requested, actualSize: .zero, visibleFrame: screen))
        XCTAssertNil(WindowLayoutGeometry.constrainedFrame(requested: requested,
                                  actualSize: CGSize(width: CGFloat.infinity, height: 100), visibleFrame: screen))
    }

    func testSnapZonesIncludeExactEdgesCornersAndNegativeCoordinates() {
        let checks: [(CGPoint, WindowLayoutAction)] = [
            (CGPoint(x: screen.minX, y: screen.maxY), .topLeft),
            (CGPoint(x: screen.maxX, y: screen.maxY), .topRight),
            (CGPoint(x: screen.minX, y: screen.minY), .bottomLeft),
            (CGPoint(x: screen.maxX, y: screen.minY), .bottomRight),
            (CGPoint(x: screen.minX, y: screen.midY), .leftHalf),
            (CGPoint(x: screen.maxX, y: screen.midY), .rightHalf),
            (CGPoint(x: screen.midX, y: screen.maxY), .maximize),
            (CGPoint(x: screen.midX, y: screen.minY), .bottomHalf)
        ]
        for (point, action) in checks {
            XCTAssertEqual(WindowLayoutGeometry.snapAction(at: point, in: screen), action)
        }
        XCTAssertNil(WindowLayoutGeometry.snapAction(at: CGPoint(x: screen.midX, y: screen.midY), in: screen))
        XCTAssertNil(WindowLayoutGeometry.snapAction(at: CGPoint(x: screen.minX - 1, y: screen.midY), in: screen))
        XCTAssertNil(WindowLayoutGeometry.snapAction(at: .zero, in: screen, threshold: -.infinity))
        XCTAssertNil(WindowLayoutGeometry.snapAction(at: CGPoint(x: CGFloat.nan, y: 0), in: screen))
    }

    func testInvalidGeometryAndGapValuesNeverCreateInvalidTargetFrames() throws {
        let invalid = [CGRect.zero, CGRect.null, CGRect.infinite,
                       CGRect(x: CGFloat.nan, y: 0, width: 100, height: 100),
                       CGRect(x: 0, y: 0, width: -10, height: 100)]
        for rect in invalid {
            XCTAssertNil(WindowLayoutGeometry.frame(for: .leftHalf, window: window, visibleFrame: rect, gap: 0))
            XCTAssertNil(WindowLayoutGeometry.frame(for: .maximize, window: rect, visibleFrame: screen, gap: 0))
        }
        for gap in [CGFloat.nan, .infinity, -.infinity, -100, 0, 12, 1_000_000] {
            for action in WindowLayoutAction.allCases where ![.restore, .nextDisplay, .previousDisplay].contains(action) {
                let result = try XCTUnwrap(WindowLayoutGeometry.frame(for: action, window: window, visibleFrame: screen, gap: gap))
                XCTAssertTrue(result.minX.isFinite && result.minY.isFinite)
                XCTAssertGreaterThan(result.width, 0)
                XCTAssertGreaterThan(result.height, 0)
                XCTAssertTrue(screen.contains(result), "\(action) with gap \(gap): \(result)")
            }
        }
        for action in [WindowLayoutAction.restore, .nextDisplay, .previousDisplay] {
            XCTAssertNil(WindowLayoutGeometry.frame(for: action, window: window, visibleFrame: screen, gap: 0))
        }
    }
    func testUpstreamVerticalSixthsUseFlooredBoundariesAcrossLandscapeDisplay() throws {
        let frames = try WindowLayoutAction.verticalSixths.map { try frame($0) }
        XCTAssertEqual(frames.count, 6)
        for index in frames.indices {
            let start = floor(screen.width * CGFloat(index) / 6)
            let end = floor(screen.width * CGFloat(index + 1) / 6)
            XCTAssertEqual(frames[index], CGRect(x: screen.minX + start, y: screen.minY,
                                                width: end - start, height: screen.height))
            if index > 0 { XCTAssertEqual(frames[index - 1].maxX, frames[index].minX) }
        }
        XCTAssertEqual(frames.first?.minX, screen.minX)
        XCTAssertEqual(frames.last?.maxX, screen.maxX)
    }

    func testUpstreamVerticalSixthsRotateFromTopToBottomOnPortraitAndSquareDisplays() throws {
        for display in [CGRect(x: -900, y: -500, width: 801, height: 1601),
                        CGRect(x: 100, y: -30, width: 1001, height: 1001)] {
            let frames = try WindowLayoutAction.verticalSixths.map {
                try XCTUnwrap(WindowLayoutGeometry.frame(for: $0, window: window, visibleFrame: display, gap: 0))
            }
            XCTAssertEqual(frames.first?.maxY, display.maxY)
            XCTAssertEqual(frames.last?.minY, display.minY)
            for index in frames.indices {
                XCTAssertEqual(frames[index].width, display.width)
                if index > 0 { XCTAssertEqual(frames[index - 1].minY, frames[index].maxY) }
            }
        }
    }

    func testSixthGapsSeparateNeighborsByOneGap() throws {
        let first = try frame(.firstVerticalSixth, gap: 12)
        let second = try frame(.secondVerticalSixth, gap: 12)
        XCTAssertEqual(first.minX - screen.minX, 12)
        XCTAssertEqual(second.minX - first.maxX, 12)
        XCTAssertEqual(first.minY - screen.minY, 12)
    }

    func testRepeatedHalfActionsSwitchSidesOnlyWhenEnabledAndFrameMatches() {
        let previous = WindowLayoutRepeatState(command: .leftHalf, layout: .leftHalf, frame: window)
        XCTAssertEqual(WindowLayoutGeometry.repeatedAction(for: .leftHalf, window: window, previous: previous, enabled: true), .rightHalf)
        XCTAssertEqual(WindowLayoutGeometry.repeatedAction(for: .leftHalf, window: window, previous: previous, enabled: false), .leftHalf)
        XCTAssertEqual(WindowLayoutGeometry.repeatedAction(for: .leftHalf, window: window.offsetBy(dx: 1, dy: 0), previous: previous, enabled: true), .leftHalf)
        XCTAssertEqual(WindowLayoutGeometry.repeatedAction(for: .leftHalf, window: window, previous: nil, enabled: true), .leftHalf)
        let switched = WindowLayoutRepeatState(command: .leftHalf, layout: .rightHalf, frame: window)
        XCTAssertEqual(WindowLayoutGeometry.repeatedAction(for: .leftHalf, window: window, previous: switched, enabled: true), .leftHalf)
        let top = WindowLayoutRepeatState(command: .topHalf, layout: .topHalf, frame: window)
        XCTAssertEqual(WindowLayoutGeometry.repeatedAction(for: .topHalf, window: window, previous: top, enabled: true), .bottomHalf)
        let bottom = WindowLayoutRepeatState(command: .bottomHalf, layout: .bottomHalf, frame: window)
        XCTAssertEqual(WindowLayoutGeometry.repeatedAction(for: .bottomHalf, window: window, previous: bottom, enabled: true), .topHalf)
    }

    func testRepeatedFirstAndLastSixthsCycleAndWrap() {
        for command in [WindowLayoutAction.firstVerticalSixth, .lastVerticalSixth] {
            var layout = command
            for step in 1...6 {
                let previous = WindowLayoutRepeatState(command: command, layout: layout, frame: window)
                layout = WindowLayoutGeometry.repeatedAction(for: command, window: window, previous: previous, enabled: true)
                let index = command == .firstVerticalSixth ? step % 6 : (5 - step % 6 + 6) % 6
                XCTAssertEqual(layout, WindowLayoutAction.verticalSixths[index])
            }
            XCTAssertEqual(layout, command)
        }
        let previous = WindowLayoutRepeatState(command: .thirdVerticalSixth, layout: .thirdVerticalSixth, frame: window)
        XCTAssertEqual(WindowLayoutGeometry.repeatedAction(for: .thirdVerticalSixth, window: window, previous: previous, enabled: true), .thirdVerticalSixth)
        let first = WindowLayoutRepeatState(command: .firstVerticalSixth, layout: .secondVerticalSixth, frame: window)
        XCTAssertEqual(WindowLayoutGeometry.repeatedAction(for: .firstVerticalSixth, window: window, previous: first, enabled: false), .firstVerticalSixth)
        XCTAssertEqual(WindowLayoutGeometry.repeatedAction(for: .firstVerticalSixth, window: window.insetBy(dx: 1, dy: 0), previous: first, enabled: true), .thirdVerticalSixth)
        XCTAssertEqual(WindowLayoutGeometry.repeatedAction(for: .lastVerticalSixth, window: window, previous: first, enabled: true), .lastVerticalSixth)
    }

    func testEmacsStandardWindowSubroleResolvesWithoutWindowRole() {
        XCTAssertTrue(WindowAccessibilityClassification.isWindow(role: "AXTextField", subrole: "AXStandardWindow"))
        XCTAssertTrue(WindowAccessibilityClassification.isWindow(role: "AXWindow", subrole: "AXStandardWindow"))
        XCTAssertTrue(WindowAccessibilityClassification.isWindow(role: "AXWindow", subrole: nil))
        XCTAssertFalse(WindowAccessibilityClassification.isWindow(role: "AXTextField", subrole: nil))
        XCTAssertFalse(WindowAccessibilityClassification.isWindow(role: "AXButton", subrole: "AXCloseButton"))
        XCTAssertFalse(WindowAccessibilityClassification.isWindow(role: nil, subrole: nil))
    }

    func testLastSixthRetainsFullOuterGapAtFlooredFractionalBoundary() throws {
        let landscape = CGRect(x: -1600, y: -100, width: 1601.5, height: 1001)
        let lastColumn = try XCTUnwrap(WindowLayoutGeometry.frame(for: .lastVerticalSixth, window: window,
                                                                 visibleFrame: landscape, gap: 12))
        XCTAssertEqual(lastColumn.maxX, landscape.minX + floor(landscape.width) - 12)
        let portrait = CGRect(x: 100, y: -800, width: 801, height: 1601.5)
        let lastRow = try XCTUnwrap(WindowLayoutGeometry.frame(for: .lastVerticalSixth, window: window,
                                                              visibleFrame: portrait, gap: 12))
        XCTAssertEqual(lastRow.minY, portrait.maxY - floor(portrait.height) + 12)
    }

}
