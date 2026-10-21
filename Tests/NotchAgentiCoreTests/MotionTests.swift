import XCTest
@testable import NotchAgentiCore

final class MotionTests: XCTestCase {
    // Closing, the blob shrank past the closed notch, sank inside the
    // hardware notch as a small block, then grew back. A spring that lands on a
    // physical edge must not overshoot it.
    func testClosingDoesNotSinkIntoTheNotch() {
        XCTAssertEqual(Motion.overshoot(damping: Motion.close.damping), 0)
        XCTAssertEqual(Motion.overshoot(damping: Motion.peekOut.damping), 0)
    }

    func testOpeningKeepsItsBounce() {
        XCTAssertGreaterThan(Motion.overshoot(damping: Motion.open.damping), 0)
    }

    func testOvershootOfAnUnderdampedSpring() {
        // ζ = 0.82 overshoots ~1.1 % of the travel: ~4 pt on a 380 pt close.
        XCTAssertEqual(Motion.overshoot(damping: 0.82), 0.011, accuracy: 0.001)
    }
}
