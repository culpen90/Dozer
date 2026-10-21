import XCTest
import CoreGraphics
@testable import DozerCore

final class WindowPlacementTests: XCTestCase {
    private let screen = CGRect(x: 1600, y: -240, width: 1440, height: 900)

    /// AX changes size while preserving the upper-left point, unlike assigning
    /// CGRect.size in AppKit coordinates. This models that important boundary.
    private final class Window {
        var frame: CGRect
        var sizes: [CGSize] = []
        var positions: [CGPoint] = []
        var sizePolicy: ((CGSize, CGRect) -> CGSize)?
        init(_ frame: CGRect) { self.frame = frame }
        func resize(_ requested: CGSize) -> Bool {
            sizes.append(requested)
            let size = sizePolicy?(requested, frame) ?? requested
            frame = CGRect(x: frame.minX, y: frame.maxY - size.height,
                           width: size.width, height: size.height)
            return true
        }
        func move(_ requested: CGRect) -> Bool {
            positions.append(CGPoint(x: requested.minX, y: requested.maxY))
            frame.origin = CGPoint(x: requested.minX, y: requested.maxY - frame.height)
            return true
        }
    }

    private func adjust(_ window: Window, to requested: CGRect) -> WindowPlacementAdjustment.Result {
        WindowPlacementAdjustment.perform(requested: requested, before: window.frame,
            visibleFrame: screen, gap: 0, readFrame: { window.frame },
            resize: window.resize, move: window.move)
    }

    func testOrdinarySynchronousPlacementAvoidsDuplicateFinalResize() {
        let target = CGRect(x: 1600, y: -240, width: 720, height: 900)
        let window = Window(CGRect(x: 1800, y: 0, width: 600, height: 400))
        let result = adjust(window, to: target)
        XCTAssertEqual(window.frame, target)
        XCTAssertEqual(window.sizes, [target.size])
        XCTAssertEqual(window.positions.count, 1)
        XCTAssertTrue(result.writesSucceeded)
    }

    func testAlreadyPlacedWindowDoesNotRepeatAnyAXWrite() {
        let target = CGRect(x: 1600, y: -240, width: 720, height: 900)
        let window = Window(target)
        _ = adjust(window, to: target)
        XCTAssertTrue(window.sizes.isEmpty)
        XCTAssertTrue(window.positions.isEmpty)
    }

    func testCenterOnlyMovesAndSameTopLeftResizeOnlyResizes() {
        let target = CGRect(x: 1800, y: 0, width: 600, height: 400)
        let moving = Window(target.offsetBy(dx: -100, dy: -100))
        _ = adjust(moving, to: target)
        XCTAssertTrue(moving.sizes.isEmpty)
        XCTAssertEqual(moving.positions.count, 1)
        let resizing = Window(CGRect(x: target.minX, y: target.maxY - 300, width: 500, height: 300))
        _ = adjust(resizing, to: target)
        XCTAssertEqual(resizing.frame, target)
        XCTAssertEqual(resizing.sizes.count, 1)
        XCTAssertTrue(resizing.positions.isEmpty)
    }

    func testMovingFromSmallDisplayReleasesTransientSizeLimit() {
        let target = CGRect(x: 1600, y: -240, width: 1440, height: 900)
        let window = Window(CGRect(x: 0, y: 100, width: 600, height: 400))
        window.sizePolicy = { requested, current in
            // The old screen refuses large sizes until AX has moved the window.
            current.minX < 1600 ? CGSize(width: 800, height: 600) : requested
        }
        _ = adjust(window, to: target)
        XCTAssertEqual(window.frame, target)
        XCTAssertEqual(window.sizes.count, 2)
        XCTAssertEqual(window.positions.count, 1)
    }

    func testReportedMinimumKeepsRightAndTopEdgesOnOffsetDisplay() throws {
        let requested = CGRect(x: 2320, y: 210, width: 720, height: 450)
        let feasible = try XCTUnwrap(WindowPlacementAdjustment.feasibleFrame(requested: requested,
            minimumSize: CGSize(width: 1000, height: 700), visibleFrame: screen, gap: 0))
        XCTAssertEqual(feasible, CGRect(x: 2040, y: -40, width: 1000, height: 700))
        let window = Window(CGRect(x: 1700, y: 100, width: 1000, height: 700))
        window.sizePolicy = { requested, _ in CGSize(width: max(1000, requested.width), height: max(700, requested.height)) }
        _ = adjust(window, to: feasible)
        XCTAssertEqual(window.frame, feasible)
        XCTAssertTrue(window.sizes.isEmpty, "A reported minimum avoids repeatedly requesting an impossible smaller size")
    }

    func testOversizedMinimumKeepsUpperLeftAndTitleBarReachable() throws {
        let requested = CGRect(x: 2320, y: 210, width: 720, height: 450)
        let feasible = try XCTUnwrap(WindowPlacementAdjustment.feasibleFrame(requested: requested,
            minimumSize: CGSize(width: 2000, height: 1200), visibleFrame: screen, gap: 0))
        XCTAssertEqual(feasible.minX, screen.minX)
        XCTAssertEqual(feasible.maxY, screen.maxY)
        XCTAssertEqual(feasible.size, CGSize(width: 2000, height: 1200))
    }

    func testMalformedMinimumDoesNotDiscardValidOtherDimension() throws {
        let requested = CGRect(x: 1600, y: -240, width: 720, height: 900)
        let feasible = try XCTUnwrap(WindowPlacementAdjustment.feasibleFrame(requested: requested,
            minimumSize: CGSize(width: CGFloat.nan, height: 1000), visibleFrame: screen, gap: 0))
        XCTAssertEqual(feasible.width, requested.width)
        XCTAssertEqual(feasible.height, 1000)
        XCTAssertEqual(feasible.maxY, screen.maxY)
    }

    func testReadFailureRetainsRecoveryMoveAndFinalResize() {
        var writes: [String] = []
        let target = CGRect(x: 1600, y: -240, width: 1440, height: 900)
        let result = WindowPlacementAdjustment.perform(requested: target,
            before: CGRect(x: 0, y: 0, width: 600, height: 400), visibleFrame: screen, gap: 0,
            readFrame: { nil }, resize: { _ in writes.append("size"); return true },
            move: { _ in writes.append("position"); return true })
        XCTAssertEqual(writes, ["size", "position", "size"])
        XCTAssertEqual(result.lastPositionFrame, target)
    }

    func testFailedInitialWriteStillAttemptsRecoveryAndReportsFailure() {
        let target = CGRect(x: 1600, y: -240, width: 1440, height: 900)
        let window = Window(CGRect(x: 0, y: 0, width: 600, height: 400))
        var resizeCalls = 0
        let result = WindowPlacementAdjustment.perform(requested: target, before: window.frame,
            visibleFrame: screen, gap: 0, readFrame: { window.frame }, resize: { size in
                resizeCalls += 1
                return resizeCalls == 1 ? false : window.resize(size)
            }, move: window.move)
        XCTAssertFalse(result.writesSucceeded)
        XCTAssertEqual(window.frame, target)
        XCTAssertEqual(resizeCalls, 2)
    }
}
