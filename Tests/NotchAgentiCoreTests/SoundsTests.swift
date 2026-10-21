import XCTest
@testable import NotchAgentiCore

final class SoundsTests: XCTestCase {
    let t0 = Date(timeIntervalSince1970: 1_000_000)
    func s(_ tty: String, _ st: SessionState) -> Session { Session(tty: tty, name: tty, state: st, since: t0) }

    func testAQuestionSoundsAsAsking() {
        XCTAssertEqual(cueFor(old: [s("a", .working)], new: [s("a", .asking)]), .asking)
    }

    func testAFinishedTurnSoundsAsFinished() {
        XCTAssertEqual(cueFor(old: [s("a", .working)], new: [s("a", .finished)]), .finished)
    }

    func testAQuestionWinsOverAFinishedTurnInTheSameSecond() {
        let old = [s("a", .working), s("b", .working)]
        let new = [s("a", .finished), s("b", .asking)]
        XCTAssertEqual(cueFor(old: old, new: new), .asking)
    }

    func testANewTerminalSoundsAsArrived() {
        XCTAssertEqual(cueFor(old: [s("a", .working)], new: [s("a", .working), s("b", .ready)]), .arrived)
    }

    func testAClosedTerminalSoundsAsLeft() {
        XCTAssertEqual(cueFor(old: [s("a", .working), s("b", .finished)], new: [s("a", .working)]), .left)
    }

    func testAStopWinsOverAnArrival() {
        let old = [s("a", .working)]
        let new = [s("a", .finished), s("b", .ready)]
        XCTAssertEqual(cueFor(old: old, new: new), .finished)
    }

    func testTheFirstReadingIsSilent() {
        XCTAssertNil(cueFor(old: [], new: [s("a", .asking), s("b", .working)]))
    }

    func testNothingChangedIsSilent() {
        XCTAssertNil(cueFor(old: [s("a", .working)], new: [s("a", .working)]))
        XCTAssertNil(cueFor(old: [s("a", .asking)], new: [s("a", .asking)]))
    }

    func testGoingBackToWorkIsSilent() {
        XCTAssertNil(cueFor(old: [s("a", .finished)], new: [s("a", .working)]))
    }

    func testAJustOpenedTerminalTurningReadyIsNotAStop() {
        XCTAssertNil(cueFor(old: [s("a", .unknown)], new: [s("a", .ready)]))
    }

    // ── the kits ──
    func testTheSineKitHasAFileForEveryCue() {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .appendingPathComponent("../../Sounds/sine").standardized
        for cue in SoundCue.allCases {
            let f = root.appendingPathComponent("\(cue.rawValue).wav")
            XCTAssertTrue(FileManager.default.fileExists(atPath: f.path), f.path)
        }
    }

    func testTheSystemKitUsesSoundsEveryMacHas() {
        for cue in SoundCue.allCases {
            let f = "/System/Library/Sounds/\(systemSound(for: cue).name).aiff"
            XCTAssertTrue(FileManager.default.fileExists(atPath: f), f)
        }
        XCTAssertGreaterThan(systemSound(for: .asking).volume, systemSound(for: .open).volume)
    }

    func testTheKitIsReadBackFromItsNameAndFallsBackToSine() {
        XCTAssertEqual(SoundKit(stored: "system"), .system)
        XCTAssertEqual(SoundKit(stored: nil), .sine)
        XCTAssertEqual(SoundKit(stored: "piano"), .sine)
    }
}
