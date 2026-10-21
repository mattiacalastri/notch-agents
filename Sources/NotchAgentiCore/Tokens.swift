import Foundation

// Today's tokens, counted from the transcripts Claude Code already keeps in
// ~/.claude/projects/<project>/<session>.jsonl. Every assistant reply carries its
// `usage` (input, output, cache written, cache read) and a timestamp; a reply split
// over several lines repeats the same message id, so each id counts once.
// Files are read incrementally: only what was appended since the last reading.

public struct Today: Equatable {
    public let tokens: Int
    public let yesterday: Int
    public let spark: [Int]
    public init(tokens: Int, yesterday: Int, spark: [Int]) { self.tokens = tokens; self.yesterday = yesterday; self.spark = spark }
    /// Percent against yesterday at the same hour; nil without a yesterday.
    public var delta: Int? { yesterday > 0 ? Int((Double(tokens - yesterday) * 100 / Double(yesterday)).rounded()) : nil }
}

public func tokensText(_ n: Int) -> String {
    if n >= 1_000_000_000 { return String(format: "%.1fG", Double(n) / 1e9).replacingOccurrences(of: ".", with: ",") }
    if n >= 1_000_000 { return "\(n / 1_000_000)M" }
    if n >= 1_000 { return "\(n / 1_000)k" }
    return "\(n)"
}

/// What one transcript has said so far: tokens per hour (hours since 1970), ids already counted.
public struct FileTally: Equatable {
    public var offset: UInt64 = 0
    public var ids = Set<String>()
    public var hours: [Int: Int] = [:]
    public init() {}
}

private let isoFrac: ISO8601DateFormatter = {
    let f = ISO8601DateFormatter()
    f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    return f
}()
private let isoPlain = ISO8601DateFormatter()

/// Adds the replies in `text` (whole JSONL lines) to the tally.
public func tally(lines text: Substring, into t: inout FileTally) {
    for line in text.split(separator: "\n") where line.contains("\"usage\"") && line.contains("\"assistant\"") {
        guard let obj = try? JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any],
              obj["type"] as? String == "assistant",
              let msg = obj["message"] as? [String: Any],
              let usage = msg["usage"] as? [String: Any],
              let stamp = obj["timestamp"] as? String,
              let date = isoFrac.date(from: stamp) ?? isoPlain.date(from: stamp) else { continue }
        let id = (msg["id"] as? String) ?? (obj["uuid"] as? String) ?? UUID().uuidString
        guard t.ids.insert(id).inserted else { continue }
        let n = ["input_tokens", "output_tokens", "cache_creation_input_tokens", "cache_read_input_tokens"]
            .reduce(0) { $0 + ((usage[$1] as? NSNumber)?.intValue ?? 0) }
        t.hours[Int(date.timeIntervalSince1970 / 3600), default: 0] += n
    }
}

/// Today since local midnight, yesterday up to the same time, the last 8 hours (oldest first).
public func today(from hours: [Int: Int], now: Date = Date(), calendar: Calendar = .current) -> Today {
    let hourNow = Int(now.timeIntervalSince1970 / 3600)
    let midnight = Int(calendar.startOfDay(for: now).timeIntervalSince1970 / 3600)
    let span = hourNow - midnight
    let todayTotal = (midnight...hourNow).reduce(0) { $0 + (hours[$1] ?? 0) }
    let yesterdayTotal = ((midnight - 24)...(midnight - 24 + span)).reduce(0) { $0 + (hours[$1] ?? 0) }
    let spark = ((hourNow - 7)...hourNow).map { hours[$0] ?? 0 }
    return Today(tokens: todayTotal, yesterday: yesterdayTotal, spark: spark)
}

/// Keeps a tally per transcript and reads only what each one appended. Use from one queue only.
public final class TokenCounter {
    private var files: [String: FileTally] = [:]
    private let root: URL
    public init(root: URL) { self.root = root }

    public func read(now: Date = Date()) -> Today? {
        let fm = FileManager.default
        let horizon = now.addingTimeInterval(-50 * 3600)   // yesterday at midnight, and a margin
        guard let walker = fm.enumerator(at: root, includingPropertiesForKeys: [.contentModificationDateKey, .fileSizeKey],
                                         options: [.skipsHiddenFiles]) else { return nil }
        var alive = Set<String>()
        for case let url as URL in walker where url.pathExtension == "jsonl" {
            guard let v = try? url.resourceValues(forKeys: [.contentModificationDateKey, .fileSizeKey]),
                  let mod = v.contentModificationDate, mod > horizon else { continue }
            let size = UInt64(v.fileSize ?? 0)
            var t = files[url.path] ?? FileTally()
            if size < t.offset { t = FileTally() }   // rewritten from scratch
            if size > t.offset, let h = try? FileHandle(forReadingFrom: url) {
                try? h.seek(toOffset: t.offset)
                let data = (try? h.readToEnd()) ?? Data()
                try? h.close()
                // only whole lines: a reply being written right now is read next time
                if let lastNL = data.lastIndex(of: 0x0A) {
                    let chunk = data[data.startIndex...lastNL]
                    tally(lines: Substring(String(decoding: chunk, as: UTF8.self)), into: &t)
                    t.offset += UInt64(chunk.count)
                }
            }
            let oldest = Int(horizon.timeIntervalSince1970 / 3600)
            t.hours = t.hours.filter { $0.key >= oldest }
            files[url.path] = t
            alive.insert(url.path)
        }
        for k in files.keys where !alive.contains(k) { files[k] = nil }
        var hours: [Int: Int] = [:]
        for t in files.values { for (h, n) in t.hours { hours[h, default: 0] += n } }
        return hours.isEmpty ? nil : today(from: hours, now: now)
    }
}
