import XCTest
@testable import NotchAgentiCore

final class LaunchTests: XCTestCase {
    func testTheEnvFileWinsOverTheUsualPlaces() {
        let home = URL(fileURLWithPath: "/Users/x")
        let text = "CLAUDE_BIN=/opt/tools/claude\nCODEX_BIN=\nPATH=/opt/tools:/usr/bin\nCLAUDE_CONFIG_DIR=/Users/x/.claude-alt\n"
        let e = ToolEnv.parse(text, home: home, exists: { ["/opt/tools/claude", "/opt/homebrew/bin/codex"].contains($0) })
        XCTAssertEqual(e.claude, "/opt/tools/claude")
        XCTAssertEqual(e.codex, "/opt/homebrew/bin/codex")   // empty in the file: found where Homebrew puts it
        XCTAssertEqual(e.path, "/opt/tools:/usr/bin")
        XCTAssertEqual(e.claudeDir.path, "/Users/x/.claude-alt")
    }

    func testWithoutTheEnvFileTheUsualPlacesAreTried() {
        let e = ToolEnv.parse("", home: URL(fileURLWithPath: "/Users/x"), exists: { $0 == "/Users/x/.local/bin/claude" })
        XCTAssertEqual(e.claude, "/Users/x/.local/bin/claude")
        XCTAssertNil(e.codex)
        XCTAssertEqual(e.claudeDir.path, "/Users/x/.claude")
        XCTAssertTrue(e.path.contains("/opt/homebrew/bin"))
    }

    /// The prompt goes in a quoted here-document: quotes, $ and backticks stay text.
    func testTheGoalIsPassedVerbatim() throws {
        let goal = #"Scrivi "ciao" e $HOME `whoami` l'ultimo"#
        let script = launchScript(binary: "/bin/echo", goal: goal, cwd: "/tmp", path: "/usr/bin:/bin")
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let f = dir.appendingPathComponent("t.command")
        try script.replacingOccurrences(of: "clear\n", with: "").write(to: f, atomically: true, encoding: .utf8)
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/bin/zsh")
        p.arguments = [f.path]
        let pipe = Pipe()
        p.standardOutput = pipe
        try p.run()
        p.waitUntilExit()
        let out = String(decoding: pipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        XCTAssertEqual(out, goal + "\n")
        XCTAssertFalse(FileManager.default.fileExists(atPath: f.path), "the script deletes itself")
    }

    func testAnEmptyGoalOpensAFreeSession() {
        let s = launchScript(binary: "/x/claude", goal: "  ", cwd: "/tmp", path: "/bin")
        XCTAssertTrue(s.contains("exec '/x/claude'\n"))
    }

    func testTabScriptsOnlyForTerminalsThatCanSelectByTTY() {
        XCTAssertTrue(tabSelectScript(bundleID: "com.apple.Terminal", tty: "ttys012")!.contains(#""/dev/ttys012""#))
        XCTAssertNotNil(tabSelectScript(bundleID: "com.googlecode.iterm2", tty: "ttys012"))
        XCTAssertNil(tabSelectScript(bundleID: "com.microsoft.VSCode", tty: "ttys012"))
        XCTAssertNil(tabSelectScript(bundleID: "com.apple.Terminal", tty: #"x" & do shell script "y"#))
    }
}
