import Foundation

struct UsageWindow: Identifiable, Equatable {
    let id: String
    /// nil when no authoritative reading exists; showing a computed guess here
    /// is what made every previous version wrong.
    let percent: Double?
    let resetsAt: Date?

    var fraction: Double { min((percent ?? 0) / 100, 1) }
    var percentLabel: String { percent.map { "\(Int($0.rounded()))%" } ?? "—" }

    var resetLabel: String {
        guard let resetsAt else { return "—" }
        let seconds = resetsAt.timeIntervalSinceNow
        if seconds <= 0 { return "now" }
        let hours = Int(seconds) / 3600
        let minutes = (Int(seconds) % 3600) / 60
        if hours >= 24 { return "\(hours / 24)d \(hours % 24)h" }
        if hours >= 1 { return "\(hours)h \(minutes)m" }
        return "\(max(1, minutes))m"
    }
}

/// Token totals per wall-clock hour, plus how far each transcript has already
/// been read, so a refresh only parses bytes appended since last time.
private struct UsageCache: Codable {
    var hours: [String: Int] = [:]
    var fableHours: [String: Int] = [:]
    var offsets: [String: UInt64] = [:]
    /// message id -> hour bucket. A transcript repeats a message's usage block
    /// across streaming updates, so without this the same tokens are counted
    /// several times; the hour lets old ids be pruned with their buckets.
    var counted: [String: Int] = [:]
}

actor UsageTracker {
    static let shared = UsageTracker()

    private var cache = UsageCache()
    private var loaded = false

    private let projects = FileManager.default
        .homeDirectoryForCurrentUser
        .appendingPathComponent(".claude/projects")

    private var cacheURL: URL {
        let dir = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("CrazyNotch")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("usage-cache-v4.json")
    }

    /// The limit measures what has been spent since the window opened, not a
    /// trailing sum: a rolling total carries the previous window's usage in and
    /// reads far too high just after a reset.
    struct DailyPoint: Identifiable, Equatable {
        let id: String
        let day: Date
        let tokens: Int
    }

    func daily(days: Int) -> [DailyPoint] {
        let calendar = Calendar.current
        let start = calendar.startOfDay(for: Date().addingTimeInterval(-Double(days - 1) * 86400))
        var totals: [Date: Int] = [:]

        for (key, value) in cache.hours {
            guard let hour = Int(key) else { continue }
            let date = Date(timeIntervalSince1970: Double(hour) * 3600)
            guard date >= start else { continue }
            totals[calendar.startOfDay(for: date), default: 0] += value
        }

        return (0..<days).compactMap { offset in
            guard let day = calendar.date(byAdding: .day, value: offset, to: start) else { return nil }
            return DailyPoint(id: ISO8601DateFormatter().string(from: day), day: day, tokens: totals[day] ?? 0)
        }
    }

    /// Exact: zero Fable tokens is zero percent of any ceiling. Above zero the
    /// ceiling is unknown, so the figure is withheld rather than guessed.
    func fableWindow(resetsAt: Date?) -> UsageWindow {
        let used = tokens(since: Date().addingTimeInterval(-7 * 86400), model: "fable")
        return UsageWindow(id: "FABLE", percent: used == 0 ? 0 : nil, resetsAt: resetsAt)
    }

    func refresh() {
        loadIfNeeded()
        guard let files = try? FileManager.default.subpathsOfDirectory(atPath: projects.path) else { return }
        let horizon = Date().addingTimeInterval(-31 * 86400)

        for rel in files where rel.hasSuffix(".jsonl") {
            let url = projects.appendingPathComponent(rel)
            guard let attrs = try? FileManager.default.attributesOfItem(atPath: url.path),
                  let modified = attrs[.modificationDate] as? Date, modified > horizon,
                  let size = (attrs[.size] as? NSNumber)?.uint64Value
            else { continue }

            let seen = cache.offsets[rel] ?? 0
            guard size > seen else { continue }
            ingest(url: url, key: rel, from: seen, to: size)
        }

        pruneOldBuckets()
        save()
    }

    private func ingest(url: URL, key: String, from: UInt64, to: UInt64) {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return }
        defer { try? handle.close() }
        try? handle.seek(toOffset: from)
        guard let data = try? handle.readToEnd(), !data.isEmpty else { return }

        var consumed = from
        var lastNewline = data.startIndex
        for line in data.split(separator: UInt8(ascii: "\n"), omittingEmptySubsequences: true) {
            lastNewline = line.endIndex
            guard let obj = try? JSONSerialization.jsonObject(with: Data(line)) as? [String: Any],
                  let stamp = obj["timestamp"] as? String,
                  let message = obj["message"] as? [String: Any],
                  let usage = message["usage"] as? [String: Any],
                  let date = ISO8601DateFormatter.shared.date(from: stamp)
            else { continue }

            let id = (message["id"] as? String)
                ?? (obj["messageId"] as? String)
                ?? (obj["uuid"] as? String)
            if let id, cache.counted[id] != nil { continue }

            // Cache reads are the bulk of real volume and count toward usage.
            let total = (usage["input_tokens"] as? Int ?? 0)
                + (usage["output_tokens"] as? Int ?? 0)
                + (usage["cache_creation_input_tokens"] as? Int ?? 0)
                + (usage["cache_read_input_tokens"] as? Int ?? 0)

            let bucket = Self.bucketKey(date)
            if let id, let hour = Int(bucket) { cache.counted[id] = hour }
            cache.hours[bucket, default: 0] += total

            if let model = message["model"] as? String, model.lowercased().contains("fable") {
                cache.fableHours[bucket, default: 0] += total
            }
        }

        consumed += UInt64(lastNewline - data.startIndex)
        cache.offsets[key] = min(consumed, to)
    }

    private static func bucketKey(_ date: Date) -> String {
        String(Int(date.timeIntervalSince1970) / 3600)
    }

    private func tokens(since: Date, model: String? = nil) -> Int {
        let floor = Int(since.timeIntervalSince1970) / 3600
        let source = model == "fable" ? cache.fableHours : cache.hours
        return source.reduce(into: 0) { sum, entry in
            if let h = Int(entry.key), h >= floor { sum += entry.value }
        }
    }

    private func pruneOldBuckets() {
        let floor = Int(Date().addingTimeInterval(-31 * 86400).timeIntervalSince1970) / 3600
        cache.hours = cache.hours.filter { Int($0.key).map { $0 >= floor } ?? false }
        cache.fableHours = cache.fableHours.filter { Int($0.key).map { $0 >= floor } ?? false }
        cache.counted = cache.counted.filter { $0.value >= floor }
    }

    private func loadIfNeeded() {
        guard !loaded else { return }
        loaded = true
        if let data = try? Data(contentsOf: cacheURL),
           let decoded = try? JSONDecoder().decode(UsageCache.self, from: data) {
            cache = decoded
        }
    }

    private func save() {
        if let data = try? JSONEncoder().encode(cache) {
            try? data.write(to: cacheURL, options: .atomic)
        }
    }
}

extension ISO8601DateFormatter {
    static let shared: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()
}
