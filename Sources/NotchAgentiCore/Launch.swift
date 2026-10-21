import Foundation

// Where the command-line tools live. An app started from Finder or at login has a bare
// PATH (/usr/bin:/bin…), so the installer writes what the user's own shell sees into
// ~/.notch-agenti/env (CLAUDE_BIN, CODEX_BIN, PATH, CLAUDE_CONFIG_DIR). Without that
// file the usual install places are tried.

public struct ToolEnv: Equatable {
    public var claude: String?
    public var codex: String?
    public var path: String
    public var claudeDir: URL

    public static let file = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".notch-agenti/env")

    public static func parse(_ text: String, home: URL, exists: (String) -> Bool) -> ToolEnv {
        var kv: [String: String] = [:]
        for line in text.split(separator: "\n") {
            let parts = line.split(separator: "=", maxSplits: 1).map(String.init)
            if parts.count == 2 { kv[parts[0].trimmingCharacters(in: .whitespaces)] = parts[1] }
        }
        let dirs = ["\(home.path)/.local/bin", "\(home.path)/.claude/local", "/opt/homebrew/bin", "/usr/local/bin",
                    "\(home.path)/.npm-global/bin", "\(home.path)/.bun/bin", "\(home.path)/.volta/bin"]
        func find(_ key: String, _ name: String) -> String? {
            if let v = kv[key], !v.isEmpty, exists(v) { return v }
            return dirs.map { "\($0)/\(name)" }.first(where: exists)
        }
        let path = kv["PATH"].flatMap { $0.isEmpty ? nil : $0 } ?? (dirs + ["/usr/bin", "/bin", "/usr/sbin", "/sbin"]).joined(separator: ":")
        let claudeDir = kv["CLAUDE_CONFIG_DIR"].flatMap { $0.isEmpty ? nil : URL(fileURLWithPath: $0) }
            ?? home.appendingPathComponent(".claude")
        return ToolEnv(claude: find("CLAUDE_BIN", "claude"), codex: find("CODEX_BIN", "codex"), path: path, claudeDir: claudeDir)
    }

    public static func load() -> ToolEnv {
        let text = (try? String(contentsOf: file, encoding: .utf8)) ?? ""
        return parse(text, home: FileManager.default.homeDirectoryForCurrentUser,
                     exists: { FileManager.default.isExecutableFile(atPath: $0) })
    }

    /// The app's environment with the user's PATH: `claude` from npm needs `node` on it.
    public var processEnvironment: [String: String] {
        var e = ProcessInfo.processInfo.environment
        e["PATH"] = path
        return e
    }
}

// ── launching a new session in a terminal ──
// «Lancia Claude Code» / «Lancia Codex» write a small .command file and open it:
// macOS runs it in the default terminal, no permission needed. The goal typed in
// the notch becomes the first prompt; the file deletes itself when it starts.

public enum Engine: String, CaseIterable {
    case claude, codex
    public var label: String { self == .claude ? "Claude Code" : "Codex" }
}

/// The script that opens one session of `engine` in `cwd`, with `goal` as its first prompt.
public func launchScript(binary: String, goal: String, cwd: String, path: String) -> String {
    let g = goal.trimmingCharacters(in: .whitespacesAndNewlines)
    let tag = "NOTCH_GOAL_" + UUID().uuidString.replacingOccurrences(of: "-", with: "")
    var s = """
    #!/bin/zsh
    rm -f -- "$0"
    export PATH=\(shellQuote(path))
    cd \(shellQuote(cwd)) || cd ~
    clear

    """
    if g.isEmpty {
        s += "exec \(shellQuote(binary))\n"
    } else {
        s += "exec \(shellQuote(binary)) \"$(cat <<'\(tag)'\n\(g)\n\(tag)\n)\"\n"
    }
    return s
}

public func shellQuote(_ s: String) -> String {
    "'" + s.replacingOccurrences(of: "'", with: "'\\''") + "'"
}

// ── bringing a session's terminal to the front ──
// The app that owns the terminal is found among the ancestors of the `claude` process
// and activated. Terminal and iTerm2 can also select the exact tab by its tty, through
// AppleScript (macOS asks once for permission); other terminals just come forward.

public func tabSelectScript(bundleID: String, tty: String) -> String? {
    let dev = "/dev/" + tty
    guard tty.allSatisfy({ $0.isLetter || $0.isNumber }) else { return nil }
    switch bundleID {
    case "com.apple.Terminal":
        return """
        tell application "Terminal"
          repeat with w in windows
            repeat with t in tabs of w
              if tty of t is "\(dev)" then
                set selected of t to true
                set index of w to 1
                activate
                return
              end if
            end repeat
          end repeat
        end tell
        """
    case "com.googlecode.iterm2":
        return """
        tell application "iTerm2"
          repeat with w in windows
            repeat with t in tabs of w
              repeat with s in sessions of t
                if tty of s is "\(dev)" then
                  select w
                  select t
                  select s
                  activate
                  return
                end if
              end repeat
            end repeat
          end repeat
        end tell
        """
    default:
        return nil
    }
}
