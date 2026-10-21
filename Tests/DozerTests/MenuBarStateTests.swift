import XCTest
@testable import DozerCore

final class MenuBarStateTests: XCTestCase {
    func testFreshStateKeepsEveryGroupAccessible() {
        let state = MenuBarState()

        XCTAssertTrue(state.controlVisible)
        XCTAssertFalse(state.isHidden)
        XCTAssertFalse(state.isExtraHidden)
        XCTAssertFalse(state.isExpanded(.divider))
        XCTAssertFalse(state.isExpanded(.extraDivider))
    }

    func testHidingControllerRequiresBothPreferenceAndWorkingShortcut() {
        for hideControl in [false, true] {
            for shortcutAvailable in [false, true] {
                var state = MenuBarState()
                state.hideControl = hideControl
                state.shortcutAvailable = shortcutAvailable
                state.hide()

                XCTAssertEqual(state.controlVisible, !(hideControl && shortcutAvailable))
                state.showAll()
                XCTAssertTrue(state.controlVisible, "Recovery must always reveal the controller")
            }
        }
    }

    func testLosingShortcutImmediatelyRestoresHiddenController() {
        var state = MenuBarState()
        state.hideControl = true
        state.shortcutAvailable = true
        state.hide()
        XCTAssertFalse(state.controlVisible)

        state.shortcutAvailable = false

        XCTAssertTrue(state.controlVisible)
        XCTAssertTrue(state.isHidden, "The recovery handle can return without disturbing the hidden group")
    }

    func testDisablingNoIconModeImmediatelyRestoresController() {
        var state = MenuBarState()
        state.hideControl = true
        state.shortcutAvailable = true
        state.hide()

        state.hideControl = false

        XCTAssertTrue(state.controlVisible)
    }

    func testOptionClickRevealsBothHiddenGroups() {
        var state = MenuBarState()
        state.extraEnabled = true
        state.hide()
        XCTAssertTrue(state.isHidden)
        XCTAssertTrue(state.isExtraHidden)

        state.toggleExtra()

        XCTAssertFalse(state.isHidden)
        XCTAssertFalse(state.isExtraHidden)
        XCTAssertFalse(state.isExpanded(.divider))
        XCTAssertFalse(state.isExpanded(.extraDivider))
    }

    func testOptionClickOnVisibleGroupsOnlyTogglesOptionalGroup() {
        var state = MenuBarState()
        state.extraEnabled = true

        state.toggleExtra()
        XCTAssertFalse(state.isHidden)
        XCTAssertTrue(state.isExtraHidden)

        state.toggleExtra()
        XCTAssertFalse(state.isHidden)
        XCTAssertFalse(state.isExtraHidden)
        XCTAssertTrue(state.controlVisible)
    }

    func testOptionClickWithoutOptionalGroupRecoversPrimaryGroup() {
        var state = MenuBarState()
        state.hide()

        state.toggleExtra()

        XCTAssertFalse(state.isHidden)
        XCTAssertFalse(state.isExpanded(.extraDivider))
        XCTAssertTrue(state.controlVisible)
    }

    func testNormalRevealKeepsOptionalGroupHiddenUntilExplicitRecovery() {
        var state = MenuBarState()
        state.extraEnabled = true
        state.hide()

        state.show()

        XCTAssertFalse(state.isHidden)
        XCTAssertTrue(state.isExtraHidden)
        XCTAssertTrue(state.isExpanded(.extraDivider))

        state.showAll()
        XCTAssertFalse(state.isExtraHidden)
    }

    func testDisablingOptionalGroupCannotLeaveItsDividerExpanded() {
        var state = MenuBarState()
        state.extraEnabled = true
        state.hide()

        state.extraEnabled = false

        XCTAssertFalse(state.isExpanded(.extraDivider))
        XCTAssertTrue(state.isExpanded(.divider))
    }

    func testRepeatedToggleCyclesPreserveRecoverability() {
        var state = MenuBarState()
        state.extraEnabled = true
        state.hideControl = true

        for cycle in 1...1000 {
            state.toggle()
            XCTAssertEqual(state.isHidden, !cycle.isMultiple(of: 2))
            XCTAssertTrue(state.controlVisible, "An unavailable shortcut must never strand the user")
            XCTAssertFalse(state.isExpanded(.control))
        }

        XCTAssertFalse(state.isHidden)
        state.showAll()
        XCTAssertFalse(state.isExtraHidden)
    }

    func testRepeatedHideAndRecoveryAreIdempotent() {
        var state = MenuBarState()
        state.extraEnabled = true
        state.hide()
        let hidden = state

        state.hide()
        XCTAssertEqual(state, hidden)

        state.showAll()
        let recovered = state
        state.showAll()
        XCTAssertEqual(state, recovered)
        XCTAssertTrue(state.controlVisible)
    }
}
