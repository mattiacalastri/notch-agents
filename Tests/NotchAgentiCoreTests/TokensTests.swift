import XCTest
@testable import NotchAgentiCore

final class TokensTests: XCTestCase {
    func reply(_ id: String, _ stamp: String, input: Int, output: Int, cacheRead: Int = 0) -> String {
        #"{"type":"assistant","timestamp":""# + stamp + #"","message":{"id":""# + id
            + #"","usage":{"input_tokens":"# + "\(input)" + #","output_tokens":"# + "\(output)"
            + #","cache_read_input_tokens":"# + "\(cacheRead)" + #","cache_creation_input_tokens":0}}}"#
    }

    /// A reply split over several lines repeats its id and its usage: it counts once.
    func testEachReplyCountsOnce() {
        var t = FileTally()
        let text = [
            reply("m1", "2026-03-10T09:15:00.000Z", input: 10, output: 5, cacheRead: 100),
            reply("m1", "2026-03-10T09:15:01.000Z", input: 10, output: 5, cacheRead: 100),
            #"{"type":"user","message":{"content":"ciao"}}"#,
            reply("m2", "2026-03-10T10:00:00Z", input: 1, output: 1),
        ].joined(separator: "\n")
        tally(lines: Substring(text), into: &t)
        let h9 = Int(ISO8601DateFormatter().date(from: "2026-03-10T09:00:00Z")!.timeIntervalSince1970 / 3600)
        XCTAssertEqual(t.hours[h9], 115)
        XCTAssertEqual(t.hours[h9 + 1], 2)
        XCTAssertEqual(t.ids, ["m1", "m2"])
    }

    func testTodayYesterdayAndTheLastEightHours() {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC")!
        let now = ISO8601DateFormatter().date(from: "2026-03-10T10:30:00Z")!
        let h = Int(now.timeIntervalSince1970 / 3600)   // 10:00 today
        let hours = [h: 100, h - 2: 50, h - 24: 30, h - 20: 999, h - 11: 7]
        // h-20 is yesterday at 14:00: after the same hour, it does not count for «yesterday»
        // h-11 is yesterday at 23:00: not today, and not before 10:00 yesterday either
        let t = today(from: hours, now: now, calendar: cal)
        XCTAssertEqual(t.tokens, 150)
        XCTAssertEqual(t.yesterday, 30)
        XCTAssertEqual(t.delta, 400)
        XCTAssertEqual(t.spark, [0, 0, 0, 0, 0, 50, 0, 100])
    }

    func testTheCounterReadsOnlyWhatWasAppended() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let proj = dir.appendingPathComponent("-Users-x-proj")
        try FileManager.default.createDirectory(at: proj, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let f = proj.appendingPathComponent("s.jsonl")
        let iso = ISO8601DateFormatter()
        let now = Date()
        try (reply("a", iso.string(from: now), input: 40, output: 2) + "\n").write(to: f, atomically: true, encoding: .utf8)
        let counter = TokenCounter(root: dir)
        XCTAssertEqual(counter.read(now: now)?.tokens, 42)
        let h = try FileHandle(forWritingTo: f)
        try h.seekToEnd()
        // the second reply is still being written: no newline yet, not counted
        h.write(Data(reply("b", iso.string(from: now), input: 8, output: 0).utf8))
        XCTAssertEqual(counter.read(now: now)?.tokens, 42)
        h.write(Data("\n".utf8))
        try h.close()
        XCTAssertEqual(counter.read(now: now)?.tokens, 50)
    }

    func testTokensInShort() {
        XCTAssertEqual(tokensText(950), "950")
        XCTAssertEqual(tokensText(48_200_000), "48M")
        XCTAssertEqual(tokensText(1_200_000_000), "1,2G")
    }
}
