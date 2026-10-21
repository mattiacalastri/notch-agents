import Foundation

// Which Claude account this Mac is logged into, and how much of its limits is left.
// Account: `claude auth status` (JSON; a shell banner before it is skipped).
// Limits: Claude Code hands every statusline call a `rate_limits` block (5-hour
// window and 7-day window, used percentage + reset time, on Pro and Max plans); the
// statusline installed with the app (hooks/notch-agenti-statusline.sh) keeps the last
// one in ~/.notch-agenti/run/statusline.json. Read-only, like the rest of the app.

public struct Account: Equatable {
    public let email: String
    public let plan: String       // «Max», «Pro», or the raw word
    public init(email: String, plan: String) { self.email = email; self.plan = plan }
}

public struct LimitWindow: Equatable {
    public let used: Double       // percent
    public let resetsAt: Date
    public var left: Double { max(0, 100 - used) }
    public init(used: Double, resetsAt: Date) { self.used = used; self.resetsAt = resetsAt }
}

public struct Usage: Equatable {
    public let fiveHour: LimitWindow?
    public let sevenDay: LimitWindow?
    public var readAt = Date.distantPast
    public init(fiveHour: LimitWindow?, sevenDay: LimitWindow?) { self.fiveHour = fiveHour; self.sevenDay = sevenDay }
}

public func parseUsage(_ data: Data) -> Usage? {
    guard let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
          let rl = obj["rate_limits"] as? [String: Any] else { return nil }
    func window(_ key: String) -> LimitWindow? {
        guard let w = rl[key] as? [String: Any],
              let used = (w["used_percentage"] as? NSNumber)?.doubleValue,
              let reset = (w["resets_at"] as? NSNumber)?.doubleValue else { return nil }
        return LimitWindow(used: used, resetsAt: Date(timeIntervalSince1970: reset))
    }
    let u = Usage(fiveHour: window("five_hour"), sevenDay: window("seven_day"))
    return (u.fiveHour == nil && u.sevenDay == nil) ? nil : u
}

public func parseAccount(_ output: String) -> Account? {
    guard let start = output.firstIndex(of: "{"), let end = output.lastIndex(of: "}"), start < end,
          let obj = try? JSONSerialization.jsonObject(with: Data(output[start...end].utf8)) as? [String: Any],
          obj["loggedIn"] as? Bool == true,
          let email = obj["email"] as? String else { return nil }
    let raw = (obj["subscriptionType"] as? String) ?? ""
    let plan = ["max": "Max", "pro": "Pro", "team": "Team", "enterprise": "Enterprise"][raw.lowercased()] ?? raw
    return Account(email: email, plan: plan)
}

public func resetText(_ date: Date, now: Date = Date()) -> String {
    let s = date.timeIntervalSince(now)
    if s < 60 { return "adesso" }
    if s < 3600 { return "tra \(Int(s / 60)) min" }
    if s < 86400 { return "tra \(Int(s / 3600)) h" }
    return "tra \(Int(s / 86400)) g"
}

/// The latest `rate_limits` a session handed to the statusline.
public func readUsage(file: URL = defaultRunDir.appendingPathComponent("statusline.json")) -> Usage? {
    guard let data = try? Data(contentsOf: file), var u = parseUsage(data) else { return nil }
    u.readAt = (try? FileManager.default.attributesOfItem(atPath: file.path)[.modificationDate] as? Date) ?? Date()
    return u
}

/// `claude auth status`, run from the binary the installer found in the user's shell.
public func readAccount(env: ToolEnv = .load()) -> Account? {
    guard let bin = env.claude else { return nil }
    let p = Process()
    p.executableURL = URL(fileURLWithPath: bin)
    p.arguments = ["auth", "status"]
    p.environment = env.processEnvironment
    let pipe = Pipe()
    p.standardOutput = pipe
    p.standardError = FileHandle.nullDevice
    do { try p.run() } catch { return nil }
    let data = pipe.fileHandleForReading.readDataToEndOfFile()
    p.waitUntilExit()
    return parseAccount(String(data: data, encoding: .utf8) ?? "")
}

// ── Codex (OpenAI): the second account this Mac works with ──
// Codex CLI keeps its ChatGPT session in ~/.codex/auth.json (access token + account id)
// and reads its own limits from `GET https://chatgpt.com/backend-api/wham/usage`: plan,
// a 5-hour window and a weekly window, used percentage + reset time. We ask the same
// endpoint with the same token, read-only; the token is never written, logged or shown.

public struct CodexUsage: Equatable {
    public let account: Account
    public let fiveHour: LimitWindow?
    public let sevenDay: LimitWindow?
    public var readAt = Date.distantPast
    public init(account: Account, fiveHour: LimitWindow?, sevenDay: LimitWindow?) {
        self.account = account; self.fiveHour = fiveHour; self.sevenDay = sevenDay
    }
}

public struct CodexAuth: Equatable {
    public let accessToken: String
    public let accountId: String
}

/// The ChatGPT session Codex is logged in with; nil when logged out or in API-key mode.
public func parseCodexAuth(_ data: Data) -> CodexAuth? {
    guard let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
          (obj["auth_mode"] as? String ?? "chatgpt") == "chatgpt",
          let tokens = obj["tokens"] as? [String: Any],
          let token = tokens["access_token"] as? String, !token.isEmpty,
          let account = tokens["account_id"] as? String, !account.isEmpty else { return nil }
    return CodexAuth(accessToken: token, accountId: account)
}

/// The `wham/usage` answer: who, which plan, how much of each window is used.
public func parseCodexUsage(_ data: Data) -> CodexUsage? {
    guard let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
          let email = obj["email"] as? String else { return nil }
    let raw = (obj["plan_type"] as? String) ?? ""
    let plan = ["plus": "Plus", "pro": "Pro", "team": "Team", "business": "Business",
                "enterprise": "Enterprise", "free": "Free"][raw.lowercased()] ?? raw.capitalized
    let rl = obj["rate_limit"] as? [String: Any]
    func window(_ key: String) -> LimitWindow? {
        guard let w = rl?[key] as? [String: Any],
              let used = (w["used_percent"] as? NSNumber)?.doubleValue,
              let reset = (w["reset_at"] as? NSNumber)?.doubleValue else { return nil }
        return LimitWindow(used: used, resetsAt: Date(timeIntervalSince1970: reset))
    }
    return CodexUsage(account: Account(email: email, plan: plan),
                      fiveHour: window("primary_window"), sevenDay: window("secondary_window"))
}

/// Ask OpenAI for Codex's live limits with the session stored by Codex CLI. Synchronous,
/// meant for the reader queue; nil when logged out, offline, or the token is no longer valid.
public func readCodexUsage(authFile: URL = FileManager.default.homeDirectoryForCurrentUser
                              .appendingPathComponent(".codex/auth.json"),
                           endpoint: URL = URL(string: "https://chatgpt.com/backend-api/wham/usage")!,
                           timeout: TimeInterval = 10) -> CodexUsage? {
    guard let data = try? Data(contentsOf: authFile), let auth = parseCodexAuth(data) else { return nil }
    var req = URLRequest(url: endpoint, timeoutInterval: timeout)
    req.setValue("Bearer \(auth.accessToken)", forHTTPHeaderField: "Authorization")
    req.setValue(auth.accountId, forHTTPHeaderField: "ChatGPT-Account-Id")
    req.setValue("application/json", forHTTPHeaderField: "Accept")
    req.setValue("notch-agenti/0.1 (codex-cli usage)", forHTTPHeaderField: "User-Agent")
    let done = DispatchSemaphore(value: 0)
    var body: Data?
    let task = URLSession.shared.dataTask(with: req) { d, resp, _ in
        if let http = resp as? HTTPURLResponse, (200..<300).contains(http.statusCode) { body = d }
        done.signal()
    }
    task.resume()
    guard done.wait(timeout: .now() + timeout + 2) == .success, let b = body,
          var u = parseCodexUsage(b) else { return nil }
    u.readAt = Date()
    return u
}
