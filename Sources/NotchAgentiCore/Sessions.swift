import Foundation

// Where the state comes from: the Claude Code hook installed with the app
// (hooks/notch-agenti-hook.sh) writes, on every hook event, one word per
// terminal into ~/.notch-agenti/run/state_<tty>.txt — working | notify | idle —,
// the session name into name_<tty>.txt and the transcript path into
// transcript_<tty>.txt. A crashed terminal may leave its files behind, so a
// session counts only while a live `claude` process still sits on that terminal.

public enum SessionState: Equatable {
    case working    // the hook wrote "working"
    case asking     // "notify": Claude Code notified the user (a permission, a question)
    case finished   // "idle": the turn is over, it goes on only with the user
    case unknown    // no state file yet, or a word we don't know
    case ready      // just opened: «idle» from SessionStart, but no reply in its transcript yet

    public init(word: String) {
        switch word.trimmingCharacters(in: .whitespacesAndNewlines) {
        case "working": self = .working
        case "notify": self = .asking
        case "idle": self = .finished
        default: self = .unknown
        }
    }

    /// Both a question and a finished turn stop until the user writes.
    public var waitsForUser: Bool { self == .asking || self == .finished }
}

public struct Session: Equatable, Identifiable {
    public let tty: String
    public let name: String
    public let state: SessionState
    public let since: Date
    public var id: String { tty }

    public init(tty: String, name: String, state: SessionState, since: Date) {
        self.tty = tty
        self.name = name
        self.state = state
        self.since = since
    }
}

/// The run dir the hook writes into. `NOTCH_AGENTI_RUN` moves it (tests, a second copy).
public let defaultRunDir: URL = ProcessInfo.processInfo.environment["NOTCH_AGENTI_RUN"]
    .map { URL(fileURLWithPath: $0) }
    ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".notch-agenti/run")

/// One process from `ps -axo pid=,ppid=,tty=,args=`.
public struct Proc: Equatable {
    public let pid: Int32
    public let ppid: Int32
    public let tty: String
    public let args: String
}

public func parsePS(_ output: String) -> [Proc] {
    output.split(separator: "\n").compactMap { line in
        let cols = line.split(maxSplits: 3, whereSeparator: { $0 == " " || $0 == "\t" })
        guard cols.count == 4, let pid = Int32(cols[0]), let ppid = Int32(cols[1]) else { return nil }
        return Proc(pid: pid, ppid: ppid, tty: String(cols[2]), args: String(cols[3]))
    }
}

/// Claude Code, whichever way it was installed: the native binary (`claude …`) or the
/// npm package run by node or bun (`node /usr/local/bin/claude …`).
public func isClaude(args: String) -> Bool {
    let words = args.split(separator: " ").map { ($0 as NSString).lastPathComponent }
    guard let first = words.first else { return false }
    if first == "claude" { return true }
    if ["node", "bun"].contains(first), words.count > 1 {
        return words[1] == "claude" || (words[1] == "cli.js" && args.contains("claude-code"))
    }
    return false
}

/// Terminals with a live `claude` process. Background runs have no terminal ("??").
public func liveClaudeTTYs(_ procs: [Proc]) -> [String] {
    var seen: [String] = []
    for p in procs where p.tty != "??" && isClaude(args: p.args) && !seen.contains(p.tty) {
        seen.append(p.tty)
    }
    return seen
}

/// The ancestors of the Claude Code process on `tty`, nearest first: the terminal app
/// that owns it is one of them (Terminal, iTerm2, VS Code, Ghostty…).
public func ancestors(ofTTY tty: String, in procs: [Proc]) -> [Int32] {
    let byPid = Dictionary(procs.map { ($0.pid, $0) }, uniquingKeysWith: { a, _ in a })
    guard var p = procs.first(where: { $0.tty == tty && isClaude(args: $0.args) }) else { return [] }
    var out: [Int32] = []
    while p.ppid > 1, let parent = byPid[p.ppid], !out.contains(parent.pid) {
        out.append(parent.pid)
        p = parent
    }
    return out
}

public func readSessions(ttys: [String], runDir: URL) -> [Session] {
    let fm = FileManager.default
    return ttys.map { tty in
        let stateURL = runDir.appendingPathComponent("state_\(tty).txt")
        let word = (try? String(contentsOf: stateURL, encoding: .utf8)) ?? ""
        let since = (try? fm.attributesOfItem(atPath: stateURL.path)[.modificationDate] as? Date) ?? Date()
        let name = (try? String(contentsOf: runDir.appendingPathComponent("name_\(tty).txt"), encoding: .utf8))?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        var state = SessionState(word: word)
        if state.waitsForUser, isNew(tty: tty, runDir: runDir) { state = .ready }
        return Session(tty: tty, name: name.isEmpty ? tty : name, state: state, since: since)
    }
}

/// True when the terminal's transcript holds no reply yet: the session was just
/// opened, or cleared. Without a transcript pointer we don't know, and the state
/// stays as the hook wrote it. A transcript past 512 KB has replies.
func isNew(tty: String, runDir: URL) -> Bool {
    let pointer = runDir.appendingPathComponent("transcript_\(tty).txt")
    guard let path = try? String(contentsOf: pointer, encoding: .utf8)
            .trimmingCharacters(in: .whitespacesAndNewlines), !path.isEmpty else { return false }
    guard let attrs = try? FileManager.default.attributesOfItem(atPath: path) else { return true }
    if let size = attrs[.size] as? Int, size > 512_000 { return false }
    guard let data = FileManager.default.contents(atPath: path) else { return false }
    return !String(decoding: data, as: UTF8.self).contains(#""type":"assistant""#)
}

/// The hook rewrites the state file at every tool call, so its date is «the last
/// tool», not «since when». A session still in the same state keeps the old start.
public func carrySince(old: [Session], new: [Session]) -> [Session] {
    let before = Dictionary(old.map { ($0.tty, $0) }, uniquingKeysWith: { a, _ in a })
    return new.map { s in
        guard let o = before[s.tty], o.state == s.state else { return s }
        return Session(tty: s.tty, name: s.name, state: s.state, since: o.since)
    }
}

/// Sessions that stopped for the user since the last reading (for the peek),
/// longest wait first. A terminal not seen before does not count.
public func justStopped(old: [Session], new: [Session]) -> [Session] {
    let before = Dictionary(old.map { ($0.tty, $0.state) }, uniquingKeysWith: { a, _ in a })
    return sortedForDisplay(new).filter { s in
        guard s.state.waitsForUser, let was = before[s.tty] else { return false }
        return !was.waitsForUser
    }
}

public struct Summary: Equatable {
    public let total: Int
    public let waiting: Int
    public init(_ sessions: [Session]) {
        total = sessions.count
        waiting = sessions.filter { $0.state.waitsForUser }.count
    }
}

/// Who waits for the user first, longest wait on top; then who works, then the
/// terminals just opened, then the ones still starting.
public func sortedForDisplay(_ sessions: [Session]) -> [Session] {
    func rank(_ s: SessionState) -> Int {
        switch s {
        case .asking, .finished: return 0
        case .working: return 1
        case .ready: return 2
        case .unknown: return 3
        }
    }
    return sessions.sorted { a, b in
        if rank(a.state) != rank(b.state) { return rank(a.state) < rank(b.state) }
        if a.since != b.since { return a.since < b.since }
        return a.tty < b.tty
    }
}

public func durationText(seconds: TimeInterval) -> String {
    let s = max(0, seconds)
    if s < 60 { return "adesso" }
    if s < 3600 { return "\(Int(s / 60)) min" }
    return "\(Int(s / 3600)) h"
}

public func statusText(_ session: Session, now: Date = Date()) -> String {
    let d = durationText(seconds: now.timeIntervalSince(session.since))
    switch session.state {
    case .asking: return "aspetta te · \(d)"
    case .finished: return "ha finito · \(d)"
    case .working: return "lavora · \(d)"
    case .unknown: return "in avvio"
    case .ready: return "nuova · pronta"
    }
}

/// `ps -axo pid=,ppid=,tty=,args=`, parsed.
public func processes() -> [Proc] {
    let p = Process()
    p.executableURL = URL(fileURLWithPath: "/bin/ps")
    p.arguments = ["-axo", "pid=,ppid=,tty=,args="]
    let pipe = Pipe()
    p.standardOutput = pipe
    p.standardError = FileHandle.nullDevice
    do { try p.run() } catch { return [] }
    let data = pipe.fileHandleForReading.readDataToEndOfFile()
    p.waitUntilExit()
    return parsePS(String(decoding: data, as: UTF8.self))
}

/// One snapshot of the machine: run `ps`, read the run dir.
public func snapshot(runDir: URL = defaultRunDir) -> [Session] {
    readSessions(ttys: liveClaudeTTYs(processes()), runDir: runDir)
}
