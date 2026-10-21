import Foundation

// What a session is doing, or what it is asking you — read from the tail of its
// transcript. The hook writes which transcript belongs to which terminal
// (~/.notch-agenti/run/transcript_<tty>.txt): nothing is guessed.
//   working  → the last tool it called, in words («modifica main.swift»)
//   waiting  → the question it left you (the last line with a «?»), or its last line

public func sessionDetail(tail: String, waiting: Bool) -> String? {
    for line in tail.split(separator: "\n").reversed() {
        guard line.contains("\"assistant\""),
              let obj = try? JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any],
              obj["type"] as? String == "assistant",
              let msg = obj["message"] as? [String: Any],
              let blocks = msg["content"] as? [[String: Any]] else { continue }
        if waiting {
            if let text = blocks.reversed().compactMap({ $0["type"] as? String == "text" ? $0["text"] as? String : nil })
                .first(where: { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }) {
                return quote(text)
            }
        } else if let tool = blocks.last(where: { $0["type"] as? String == "tool_use" }) {
            return describe(tool: tool["name"] as? String ?? "", input: tool["input"] as? [String: Any] ?? [:])
        }
    }
    return nil
}

/// The line that asks something; otherwise the last line said. Markdown stripped, short.
func quote(_ text: String) -> String {
    let lines = text.split(separator: "\n")
        .map { clean(String($0)) }
        .filter { !$0.isEmpty }
    let pick = lines.last(where: { $0.contains("?") }) ?? lines.last ?? ""
    var sentence = pick
    if let q = pick.firstIndex(of: "?") {   // from the sentence start to its «?»
        let head = pick[..<q]
        let start = head.lastIndex(where: { ".!:".contains($0) }).map { pick.index(after: $0) } ?? pick.startIndex
        sentence = String(pick[start...q]).trimmingCharacters(in: .whitespaces)
    }
    return "«\(short(sentence, 120))»"
}

func clean(_ s: String) -> String {
    var t = s.trimmingCharacters(in: .whitespaces)
    while let f = t.first, "#->*|".contains(f) { t.removeFirst(); t = t.trimmingCharacters(in: .whitespaces) }
    for mark in ["**", "`", "__"] { t = t.replacingOccurrences(of: mark, with: "") }
    return t.trimmingCharacters(in: .whitespaces)
}

func short(_ s: String, _ n: Int) -> String {
    s.count <= n ? s : String(s.prefix(n - 1)).trimmingCharacters(in: .whitespaces) + "…"
}

func base(_ path: Any?) -> String {
    ((path as? String).map { ($0 as NSString).lastPathComponent }) ?? ""
}

public func describe(tool name: String, input: [String: Any]) -> String {
    let s: String
    switch name {
    case "Bash":
        if let d = input["description"] as? String, !d.isEmpty { s = d }
        else { s = (input["command"] as? String ?? "").split(separator: "\n").first.map(String.init) ?? "terminale" }
    case "Read": s = "legge \(base(input["file_path"]))"
    case "Edit", "MultiEdit": s = "modifica \(base(input["file_path"]))"
    case "Write": s = "scrive \(base(input["file_path"]))"
    case "NotebookEdit": s = "modifica \(base(input["notebook_path"]))"
    case "Grep", "Glob": s = "cerca \(input["pattern"] as? String ?? "")"
    case "Agent", "Task": s = "agente: \(input["description"] as? String ?? "al lavoro")"
    case "WebFetch": s = "legge \(URL(string: input["url"] as? String ?? "")?.host ?? "una pagina web")"
    case "WebSearch": s = "cerca sul web: \(input["query"] as? String ?? "")"
    case "Skill": s = "skill \(input["skill"] as? String ?? "")"
    case "TaskCreate", "TaskUpdate", "TodoWrite": s = "aggiorna la lista dei compiti"
    default:
        if name.hasPrefix("mcp__") {
            let parts = name.split(separator: "_", omittingEmptySubsequences: true)
            // mcp__server__tool → «server · tool»
            let comps = name.dropFirst(5).components(separatedBy: "__")
            s = comps.count >= 2 ? "\(comps[0].replacingOccurrences(of: "_", with: " ")) · \(comps[1].replacingOccurrences(of: "_", with: " "))"
                                 : parts.joined(separator: " ")
        } else {
            s = name
        }
    }
    return short(s.trimmingCharacters(in: .whitespaces), 70)
}

/// The last `bytes` of a file, starting at a whole line.
public func readTail(_ url: URL, bytes: Int = 1_000_000) -> String {
    guard let h = try? FileHandle(forReadingFrom: url) else { return "" }
    defer { try? h.close() }
    let size = (try? h.seekToEnd()) ?? 0
    let from = size > UInt64(bytes) ? size - UInt64(bytes) : 0
    try? h.seek(toOffset: from)
    let data = (try? h.readToEnd()) ?? Data()
    var text = String(decoding: data, as: UTF8.self)
    if from > 0, let nl = text.firstIndex(of: "\n") { text = String(text[text.index(after: nl)...]) }
    return text
}

/// Detail for every session, by tty. A transcript is read again only when it
/// changed (size or date) or the session changed state: a second is a lot of
/// megabytes otherwise. Use from one queue only.
public final class DetailReader {
    private var cache: [String: (stamp: String, waiting: Bool, detail: String?)] = [:]
    public init() {}

    public func read(_ sessions: [Session], runDir: URL) -> [String: String] {
        var out: [String: String] = [:]
        var seen = Set<String>()
        for s in sessions where s.state != .unknown {
            let f = runDir.appendingPathComponent("transcript_\(s.tty).txt")
            guard let path = try? String(contentsOf: f, encoding: .utf8).trimmingCharacters(in: .whitespacesAndNewlines),
                  !path.isEmpty,
                  let attrs = try? FileManager.default.attributesOfItem(atPath: path) else { continue }
            seen.insert(path)
            let stamp = "\(attrs[.size] ?? 0)|\((attrs[.modificationDate] as? Date)?.timeIntervalSince1970 ?? 0)"
            let waiting = s.state.waitsForUser
            let detail: String?
            if let c = cache[path], c.stamp == stamp, c.waiting == waiting {
                detail = c.detail
            } else {
                detail = sessionDetail(tail: readTail(URL(fileURLWithPath: path)), waiting: waiting)
                cache[path] = (stamp, waiting, detail)
            }
            if let detail { out[s.tty] = detail }
        }
        for k in cache.keys where !seen.contains(k) { cache[k] = nil }
        return out
    }
}
