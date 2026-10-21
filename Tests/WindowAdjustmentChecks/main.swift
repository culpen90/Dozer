// Native, permission-free regression checks for Rectangle's scoped AX mitigation.
import Foundation

var passed = 0
func check(_ condition: @autoclosure () -> Bool, _ message: String) {
    guard condition() else { fatalError("FAIL: \(message)") }
    passed += 1
    print("PASS: \(message)")
}

for initial in [Optional<Bool>.none, false] {
    var writes: [Bool] = []
    let result = RectangleWindowAdjustment.perform(assistiveTechnologyActive: false,
        readEnhancedUI: { initial }, writeEnhancedUI: { writes.append($0); return true }, adjustment: { 42 })
    check(writes.isEmpty && result == 42, "unknown and disabled states are unchanged; result is preserved")
}

var enabled = true
var sequence: [String] = []
RectangleWindowAdjustment.perform(assistiveTechnologyActive: false,
    readEnhancedUI: { enabled }, writeEnhancedUI: { enabled = $0; sequence.append($0 ? "restore" : "disable"); return true },
    adjustment: { sequence.append("adjust"); check(!enabled, "adjustment runs with Enhanced UI temporarily disabled") })
check(enabled && sequence == ["disable", "adjust", "restore"], "original true state is restored in order")

var failedWrites: [Bool] = []
var adjustedAfterFailure = false
RectangleWindowAdjustment.perform(assistiveTechnologyActive: false, readEnhancedUI: { true },
    writeEnhancedUI: { failedWrites.append($0); return false }, adjustment: { adjustedAfterFailure = true })
check(adjustedAfterFailure && failedWrites == [false, true], "failed disable still adjusts and attempts restoration")

enum ExpectedFailure: Error { case adjustment }
var restoredAfterThrow: [Bool] = []
do {
    try RectangleWindowAdjustment.perform(assistiveTechnologyActive: false, readEnhancedUI: { true },
        writeEnhancedUI: { restoredAfterThrow.append($0); return true },
        adjustment: { throw ExpectedFailure.adjustment })
    fatalError("Expected the adjustment error")
} catch ExpectedFailure.adjustment {
    check(restoredAfterThrow == [false, true], "throwing adjustment restores state before propagating its error")
} catch { fatalError("Unexpected error: \(error)") }

var assistiveRead = false
var assistiveWrite = false
let protectedResult = RectangleWindowAdjustment.perform(assistiveTechnologyActive: true,
    readEnhancedUI: { assistiveRead = true; return true }, writeEnhancedUI: { _ in assistiveWrite = true; return true },
    adjustment: { 7 })
check(!assistiveRead && !assistiveWrite && protectedResult == 7, "active assistive technology bypasses all flag changes")
print("\(passed)/\(passed) window adjustment checks passed")
