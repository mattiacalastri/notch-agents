import XCTest
@testable import NotchAgentiCore

final class SessionsTests: XCTestCase {

    // ── which terminals hold a live Claude Code session ─────────────────────
    func testOnlyClaudeProcessesWithATerminalCount() {
        let ps = """
          11060 1 ttys045  claude --resume
          26830 1 ??       claude -p hello
          50001 1 ttys046  -zsh
          68492 1 ttys058  /opt/homebrew/bin/claude
          70001 1 ttys060  node /usr/local/bin/claude
          70002 1 ttys061  node /usr/local/lib/node_modules/@anthropic-ai/claude-code/cli.js
        """
        XCTAssertEqual(liveClaudeTTYs(parsePS(ps)), ["ttys045", "ttys058", "ttys060", "ttys061"])
    }

    func testTwoClaudeProcessesOnOneTerminalAreOneSession() {
        let ps = "1 0 ttys045 claude\n2 0 ttys045 claude\n"
        XCTAssertEqual(liveClaudeTTYs(parsePS(ps)), ["ttys045"])
    }

    func testANameThatOnlyContainsClaudeIsNotClaude() {
        let ps = "1 0 ttys045 claude-helper\n2 0 ttys046 notclaude\n3 0 ttys047 node server.js claude\n"
        XCTAssertEqual(liveClaudeTTYs(parsePS(ps)), [])
    }

    /// A click on a tile walks up from `claude` to the terminal app that owns it.
    func testAncestorsLeadToTheTerminalApp() {
        let ps = """
          500 1 ??       /System/Applications/Utilities/Terminal.app/Contents/MacOS/Terminal
          600 500 ttys045 login -pf user
          700 600 ttys045 -zsh
          800 700 ttys045 claude
        """
        XCTAssertEqual(ancestors(ofTTY: "ttys045", in: parsePS(ps)), [700, 600, 500])
        XCTAssertEqual(ancestors(ofTTY: "ttys099", in: parsePS(ps)), [])
    }

    // ── the state word written by the hook ──────────────────────────────
    func testStateWordsMapToStates() {
        XCTAssertEqual(SessionState(word: "working\n"), .working)
        XCTAssertEqual(SessionState(word: "notify"), .asking)
        XCTAssertEqual(SessionState(word: "idle"), .finished)
        XCTAssertEqual(SessionState(word: ""), .unknown)
        XCTAssertEqual(SessionState(word: "boh"), .unknown)
    }

    func testAskingAndFinishedBothWaitForTheUser() {
        XCTAssertTrue(SessionState.asking.waitsForUser)
        XCTAssertTrue(SessionState.finished.waitsForUser)
        XCTAssertFalse(SessionState.working.waitsForUser)
        XCTAssertFalse(SessionState.unknown.waitsForUser)
    }

    // ── reading the run dir: stale files of dead terminals are ignored ──────
    func testReadsOnlyLiveTerminalsAndFallsBackToTheTTYName() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        try "notify".write(to: dir.appendingPathComponent("state_ttys045.txt"), atomically: true, encoding: .utf8)
        try "Deploy app\n".write(to: dir.appendingPathComponent("name_ttys045.txt"), atomically: true, encoding: .utf8)
        try "working".write(to: dir.appendingPathComponent("state_ttys058.txt"), atomically: true, encoding: .utf8)
        // a dead terminal still saying notify since this morning
        try "notify".write(to: dir.appendingPathComponent("state_ttys056.txt"), atomically: true, encoding: .utf8)

        let sessions = readSessions(ttys: ["ttys045", "ttys058"], runDir: dir)
        XCTAssertEqual(sessions.count, 2)
        XCTAssertEqual(sessions.first { $0.tty == "ttys045" }?.name, "Deploy app")
        XCTAssertEqual(sessions.first { $0.tty == "ttys045" }?.state, .asking)
        XCTAssertEqual(sessions.first { $0.tty == "ttys058" }?.name, "ttys058")
        XCTAssertEqual(sessions.first { $0.tty == "ttys058" }?.state, .working)
    }

    /// A terminal just opened: Claude Code's SessionStart paints it «idle», but it has
    /// finished nothing. Until its transcript holds a reply it is new, not waiting.
    func testANewSessionIsReadyNotFinished() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        func term(_ tty: String, _ word: String, transcript: String?) throws {
            try word.write(to: dir.appendingPathComponent("state_\(tty).txt"), atomically: true, encoding: .utf8)
            let t = dir.appendingPathComponent("\(tty).jsonl")
            try t.path.write(to: dir.appendingPathComponent("transcript_\(tty).txt"), atomically: true, encoding: .utf8)
            if let transcript { try transcript.write(to: t, atomically: true, encoding: .utf8) }
        }
        try term("ttys001", "idle", transcript: #"{"type":"system"}"# + "\n" + #"{"type":"user","message":{}}"#)
        try term("ttys002", "idle", transcript: #"{"type":"user"}"# + "\n" + #"{"type":"assistant","message":{}}"#)
        try term("ttys003", "notify", transcript: nil)   // not even written yet
        let st = Dictionary(uniqueKeysWithValues: readSessions(ttys: ["ttys001", "ttys002", "ttys003"], runDir: dir).map { ($0.tty, $0.state) })
        XCTAssertEqual(st["ttys001"], .ready)
        XCTAssertEqual(st["ttys002"], .finished)
        XCTAssertEqual(st["ttys003"], .ready)
        XCTAssertFalse(SessionState.ready.waitsForUser)
    }

    func testATerminalWithoutAStateFileIsUnknownNotDropped() {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let sessions = readSessions(ttys: ["ttys099"], runDir: dir)
        XCTAssertEqual(sessions.map(\.state), [.unknown])
    }

    // ── what the notch shows ─────────────────────────────────────────────────
    private func s(_ tty: String, _ st: SessionState, minsAgo: Double) -> Session {
        Session(tty: tty, name: tty, state: st,
                since: Date(timeIntervalSince1970: 10_000 - minsAgo * 60))
    }

    func testSummaryCountsAllAndWaiting() {
        let all = [s("a", .working, minsAgo: 1), s("b", .asking, minsAgo: 2),
                   s("c", .finished, minsAgo: 3), s("d", .unknown, minsAgo: 4)]
        let sum = Summary(all)
        XCTAssertEqual(sum.total, 4)
        XCTAssertEqual(sum.waiting, 2)
    }

    func testWhoWaitsLongestComesFirstThenTheWorking() {
        let all = [s("w", .working, minsAgo: 30), s("f", .finished, minsAgo: 5),
                   s("q", .asking, minsAgo: 1), s("old", .finished, minsAgo: 40)]
        XCTAssertEqual(sortedForDisplay(all).map(\.tty), ["old", "f", "q", "w"])
    }

    func testDurationsReadLikeSpeech() {
        XCTAssertEqual(durationText(seconds: 20), "adesso")
        XCTAssertEqual(durationText(seconds: 61), "1 min")
        XCTAssertEqual(durationText(seconds: 59 * 60), "59 min")
        XCTAssertEqual(durationText(seconds: 2 * 3600 + 120), "2 h")
    }

    func testStatusLineSaysWhatTheSessionNeeds() {
        let now = Date(timeIntervalSince1970: 10_000)
        XCTAssertEqual(statusText(s("a", .asking, minsAgo: 3), now: now), "aspetta te · 3 min")
        XCTAssertEqual(statusText(s("a", .finished, minsAgo: 12), now: now), "ha finito · 12 min")
        XCTAssertEqual(statusText(s("a", .working, minsAgo: 4), now: now), "lavora · 4 min")
    }
}

final class SessionIconTests: XCTestCase {
    func testSessionNamesGetAPertinentIcon() {
        XCTAssertEqual(sessionIcon(for: "deploy sito"), "icloud.and.arrow.up.fill")
        XCTAssertEqual(sessionIcon(for: "report vendite"), "chart.bar.fill")
        XCTAssertEqual(sessionIcon(for: "dotfiles"), "terminal.fill")
        XCTAssertEqual(sessionIcon(for: "my-shop"), "cart.fill")
        XCTAssertEqual(sessionIcon(for: "fix login bug"), "ant.fill")
    }

    /// A word is recognised whole, never inside another word: «quindi» has no «ui».
    func testMatchesWholeWordsOnly() {
        XCTAssertEqual(sessionIcon(for: "quindi"), sessionIconFallback)
        XCTAssertEqual(sessionIcon(for: "UI della dashboard"), "chart.bar.fill")
    }

    func testUnknownNameGetsTheFallback() {
        XCTAssertEqual(sessionIcon(for: "ttys012"), sessionIconFallback)
        XCTAssertEqual(sessionIcon(for: ""), sessionIconFallback)
    }
}

final class AccountTests: XCTestCase {
    func testUsageFromTheStatuslineInput() throws {
        let json = #"{"model":{"id":"x"},"rate_limits":{"five_hour":{"used_percentage":3,"resets_at":1792515600},"seven_day":{"used_percentage":11.5,"resets_at":1793084400}}}"#
        let u = try XCTUnwrap(parseUsage(Data(json.utf8)))
        XCTAssertEqual(u.fiveHour?.used, 3)
        XCTAssertEqual(u.fiveHour?.left, 97)
        XCTAssertEqual(u.fiveHour?.resetsAt, Date(timeIntervalSince1970: 1792515600))
        XCTAssertEqual(u.sevenDay?.used, 11.5)
    }

    /// API-key sessions have no rate_limits: no usage, not a zero.
    func testNoRateLimitsMeansNoUsage() {
        XCTAssertNil(parseUsage(Data(#"{"model":{"id":"x"}}"#.utf8)))
        XCTAssertNil(parseUsage(Data("not json".utf8)))
    }

    /// `claude auth status` may print a banner before the JSON.
    func testAccountFromAuthStatus() throws {
        let out = "banner\n{\n \"loggedIn\": true,\n \"email\": \"a@b.it\",\n \"subscriptionType\": \"max\",\n \"orgName\": \"X\"\n}\n"
        let a = try XCTUnwrap(parseAccount(out))
        XCTAssertEqual(a.email, "a@b.it")
        XCTAssertEqual(a.plan, "Max")
    }

    func testLoggedOutIsNoAccount() {
        XCTAssertNil(parseAccount(#"{"loggedIn": false}"#))
        XCTAssertNil(parseAccount(""))
    }

    func testResetText() {
        let now = Date(timeIntervalSince1970: 1_000_000)
        XCTAssertEqual(resetText(now.addingTimeInterval(40 * 60), now: now), "tra 40 min")
        XCTAssertEqual(resetText(now.addingTimeInterval(3 * 3600 + 120), now: now), "tra 3 h")
        XCTAssertEqual(resetText(now.addingTimeInterval(3 * 86400 + 3600), now: now), "tra 3 g")
        XCTAssertEqual(resetText(now.addingTimeInterval(-5), now: now), "adesso")
    }
}

final class DetailTests: XCTestCase {
    func line(_ blocks: String) -> String { #"{"type":"assistant","message":{"content":["# + blocks + "]}}" }

    func testWorkingShowsTheLastTool() {
        let tail = [
            line(#"{"type":"text","text":"Ora costruisco."}"#),
            line(#"{"type":"tool_use","name":"Edit","input":{"file_path":"/a/b/main.swift"}}"#),
            #"{"type":"user","message":{"content":[{"type":"tool_result"}]}}"#,
        ].joined(separator: "\n")
        XCTAssertEqual(sessionDetail(tail: tail, waiting: false), "modifica main.swift")
    }

    func testToolsInWords() {
        XCTAssertEqual(describe(tool: "Bash", input: ["description": "Build the app", "command": "swift build"]), "Build the app")
        XCTAssertEqual(describe(tool: "Bash", input: ["command": "swift build\nswift test"]), "swift build")
        XCTAssertEqual(describe(tool: "WebFetch", input: ["url": "https://api.github.com/x"]), "legge api.github.com")
        XCTAssertEqual(describe(tool: "mcp__claude_ai_Gmail__search_threads", input: [:]), "claude ai Gmail · search threads")
    }

    func testWaitingShowsTheQuestion() {
        let text = "Test verdi, **build** pronta.\\n\\nVuoi che la pubblichi adesso? Oppure aspetto.\\n- dettaglio"
        let tail = line(#"{"type":"text","text":""# + text + #""}"#)
        XCTAssertEqual(sessionDetail(tail: tail, waiting: true), "«Vuoi che la pubblichi adesso?»")
    }

    func testWaitingWithoutQuestionShowsTheLastLine() {
        let tail = line(#"{"type":"text","text":"Fatto.\nMerge eseguito, rollback pronto."}"#)
        XCTAssertEqual(sessionDetail(tail: tail, waiting: true), "«Merge eseguito, rollback pronto.»")
    }

    func testNothingReadable() {
        XCTAssertNil(sessionDetail(tail: "", waiting: true))
        XCTAssertNil(sessionDetail(tail: "garbage\n{", waiting: false))
    }

}

final class ContinuityTests: XCTestCase {
    func s(_ tty: String, _ st: SessionState, _ t: Double) -> Session {
        Session(tty: tty, name: tty, state: st, since: Date(timeIntervalSince1970: t))
    }

    /// The hook rewrites «working» at every tool call: the file date says «adesso»
    /// forever and the tiles swap places. Same state → the time it started is kept.
    func testSameStateKeepsWhenItStarted() {
        let old = [s("a", .working, 100), s("b", .finished, 50)]
        let new = [s("a", .working, 900), s("b", .working, 950), s("c", .ready, 960)]
        let out = carrySince(old: old, new: new)
        XCTAssertEqual(out.map(\.since.timeIntervalSince1970), [100, 950, 960])
    }

    func testJustStoppedIsTheOneThatWentFromWorkingToWaiting() {
        let old = [s("a", .working, 1), s("b", .asking, 1), s("c", .ready, 1)]
        let new = [s("a", .finished, 2), s("b", .asking, 1), s("c", .finished, 3), s("d", .asking, 3)]
        // c had never replied before (ready → finished is a first reply: it counts),
        // d is a terminal we had not seen: no peek for it at the first reading
        XCTAssertEqual(justStopped(old: old, new: new).map(\.tty), ["a", "c"])
    }
}

final class CodexTests: XCTestCase {
    func testCodexUsageFromTheUsageEndpoint() throws {
        let json = """
        {"email":"chi@esempio.it","plan_type":"plus","rate_limit":{"allowed":true,
         "primary_window":{"used_percent":12,"limit_window_seconds":18000,"reset_at":1792548411},
         "secondary_window":{"used_percent":1,"limit_window_seconds":604800,"reset_at":1793084397}}}
        """
        let u = try XCTUnwrap(parseCodexUsage(Data(json.utf8)))
        XCTAssertEqual(u.account, Account(email: "chi@esempio.it", plan: "Plus"))
        XCTAssertEqual(u.fiveHour?.left, 88)
        XCTAssertEqual(u.fiveHour?.resetsAt, Date(timeIntervalSince1970: 1792548411))
        XCTAssertEqual(u.sevenDay?.used, 1)
    }

    func testCodexUsageWithoutWindowsKeepsTheAccount() throws {
        let u = try XCTUnwrap(parseCodexUsage(Data(#"{"email":"chi@esempio.it","plan_type":"free"}"#.utf8)))
        XCTAssertEqual(u.account.plan, "Free")
        XCTAssertNil(u.fiveHour); XCTAssertNil(u.sevenDay)
    }

    func testNoEmailIsNoCodexUsage() {
        XCTAssertNil(parseCodexUsage(Data(#"{"detail":"Unauthorized"}"#.utf8)))
        XCTAssertNil(parseCodexUsage(Data("not json".utf8)))
    }

    func testCodexAuthNeedsAChatGPTSession() throws {
        let ok = #"{"auth_mode":"chatgpt","tokens":{"access_token":"t","account_id":"a"}}"#
        XCTAssertEqual(parseCodexAuth(Data(ok.utf8)), CodexAuth(accessToken: "t", accountId: "a"))
        XCTAssertNil(parseCodexAuth(Data(#"{"auth_mode":"apikey","OPENAI_API_KEY":"k"}"#.utf8)))
        XCTAssertNil(parseCodexAuth(Data(#"{"auth_mode":"chatgpt","tokens":{"access_token":""}}"#.utf8)))
    }

    func testReadingCodexWithoutAnAuthFileIsNil() {
        XCTAssertNil(readCodexUsage(authFile: URL(fileURLWithPath: "/nonexistent/auth.json")))
    }
}
