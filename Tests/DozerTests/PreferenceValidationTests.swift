import XCTest
@testable import DozerCore

final class PreferenceValidationTests: XCTestCase {
    func testCorruptDelayValuesFallBackToUsableCountdown() {
        for value in [Double.nan, .infinity, -.infinity] {
            XCTAssertEqual(PreferenceValidation.delay(value), 10)
        }
    }

    func testDelayRemainsPositiveAndBounded() {
        XCTAssertEqual(PreferenceValidation.delay(-100), 1)
        XCTAssertEqual(PreferenceValidation.delay(0), 1)
        XCTAssertEqual(PreferenceValidation.delay(3.5), 3.5)
        XCTAssertEqual(PreferenceValidation.delay(3600), 3600)
        XCTAssertEqual(PreferenceValidation.delay(.greatestFiniteMagnitude), 3600)
    }

    func testCorruptPaddingValuesFallBackToClickableWidth() {
        for value in [Double.nan, .infinity, -.infinity] {
            XCTAssertEqual(PreferenceValidation.padding(value), 25)
        }
    }

    func testPaddingCannotCreateAnInvisibleOrExcessivelyWideController() {
        XCTAssertEqual(PreferenceValidation.padding(-100), 20)
        XCTAssertEqual(PreferenceValidation.padding(0), 20)
        XCTAssertEqual(PreferenceValidation.padding(32.5), 32.5)
        XCTAssertEqual(PreferenceValidation.padding(.greatestFiniteMagnitude), 60)
    }

    func testIconSizeHandlesExtremeStoredIntegers() {
        XCTAssertEqual(PreferenceValidation.iconSize(.min), 6)
        XCTAssertEqual(PreferenceValidation.iconSize(0), 6)
        XCTAssertEqual(PreferenceValidation.iconSize(10), 10)
        XCTAssertEqual(PreferenceValidation.iconSize(.max), 18)
    }

    func testHiddenLengthCoversWidestScreenRegardlessOfOrder() {
        XCTAssertEqual(PreferenceValidation.hiddenLength(screenWidths: [1728, 3840, 1920]), 7680)
        XCTAssertEqual(PreferenceValidation.hiddenLength(screenWidths: [3840, 1920, 1728]), 7680)
        XCTAssertEqual(PreferenceValidation.hiddenLength(screenWidths: [1728]), 3456)
    }

    func testHiddenLengthIgnoresInvalidDisplayMeasurements() {
        let widths = [Double.nan, .infinity, -.infinity, -3840, 0, 1920]

        XCTAssertEqual(PreferenceValidation.hiddenLength(screenWidths: widths), 3840)
        XCTAssertEqual(PreferenceValidation.hiddenLength(screenWidths: []), 10_000)
        XCTAssertEqual(PreferenceValidation.hiddenLength(screenWidths: [.nan, 0, -1]), 10_000)
    }

    func testHiddenLengthRemainsSafeForTinyAndEnormousDisplays() {
        XCTAssertEqual(PreferenceValidation.hiddenLength(screenWidths: [1]), 500)
        XCTAssertEqual(PreferenceValidation.hiddenLength(screenWidths: [7680]), 10_000)
        XCTAssertEqual(PreferenceValidation.hiddenLength(screenWidths: [.greatestFiniteMagnitude]), 10_000)
    }
}
