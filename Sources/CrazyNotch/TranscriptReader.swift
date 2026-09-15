import Foundation

enum TranscriptReader {
    /// Only the tail is parsed: a transcript can be hundreds of megabytes and
    /// everything shown in the hover card lives in its most recent entries.
    static func detail(path: String, tailBytes: Int = 400_000) -> SessionDetail? {
        guard !path.isEmpty,
              let handle = try? FileHandle(forReadingFrom: URL(fileURLWithPath: path))
        else { return nil }
        defer { try? handle.close() }

        guard let size = try? handle.seekToEnd() else { return nil }
        let start = size > UInt64(tailBytes) ? size - UInt64(tailBytes) : 0
        try? handle.seek(toOffset: start)
        guard let data = try? handle.readToEnd() else { return nil }

        var detail = SessionDetail()
        detail.title = titleFromHead(path: path)
        var sawUsage = false

        for line in data.split(separator: UInt8(ascii: "\n"), omittingEmptySubsequences: true) {
            guard let obj = try? JSONSerialization.jsonObject(with: Data(line)) as? [String: Any],
                  let message = obj["message"] as? [String: Any]
            else { continue }

            // Subagents report their own much smaller context; counting those
            // makes the main thread's usage look like whatever ran last.
            if obj["isSidechain"] as? Bool == true { continue }

            if let model = message["model"] as? String { detail.model = model }

            if let usage = message["usage"] as? [String: Any] {
                sawUsage = true
                let input = usage["input_tokens"] as? Int ?? 0
                let cacheRead = usage["cache_read_input_tokens"] as? Int ?? 0
                let cacheWrite = usage["cache_creation_input_tokens"] as? Int ?? 0
                detail.contextTokens = input + cacheRead + cacheWrite
            }

            if (message["role"] as? String) == "assistant", let text = extractText(message) {
                detail.lastAssistantText = plain(text)
            }
        }

        detail.contextWindow = detail.contextTokens > 200_000 ? 1_000_000 : 200_000
        if detail.contextWindow > 0 {
            detail.contextPercent = Double(detail.contextTokens) / Double(detail.contextWindow) * 100
        }
        return sawUsage || !detail.lastAssistantText.isEmpty || !detail.title.isEmpty ? detail : nil
    }

    /// The chat's own name lives near the start of the transcript, while
    /// everything else the card shows lives at the end, so the head is read
    /// separately rather than loading the whole file.
    private static func titleFromHead(path: String, headBytes: Int = 300_000) -> String {
        guard let handle = try? FileHandle(forReadingFrom: URL(fileURLWithPath: path)) else { return "" }
        defer { try? handle.close() }
        guard let data = try? handle.read(upToCount: headBytes) else { return "" }

        var title = ""
        for line in data.split(separator: UInt8(ascii: "\n"), omittingEmptySubsequences: true) {
            guard let obj = try? JSONSerialization.jsonObject(with: Data(line)) as? [String: Any] else { continue }
            for key in ["customTitle", "ai-title", "custom-title", "title"] {
                if let value = obj[key] as? String, !value.isEmpty { title = value }
            }
        }
        return title
    }

    /// Transcript text is markdown; the card renders plain strings, so the
    /// syntax would otherwise show up as literal asterisks and backticks.
    private static func plain(_ text: String) -> String {
        var out = text
        for pattern in ["```[a-zA-Z]*", "\\*\\*", "`", "^#{1,6} ", "^[-*] ", "^> "] {
            out = out.replacingOccurrences(
                of: pattern,
                with: "",
                options: [.regularExpression, .caseInsensitive]
            )
        }
        return out
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }

    private static func extractText(_ message: [String: Any]) -> String? {
        if let text = message["content"] as? String, !text.isEmpty { return text }
        guard let blocks = message["content"] as? [[String: Any]] else { return nil }
        let joined = blocks
            .filter { ($0["type"] as? String) == "text" }
            .compactMap { $0["text"] as? String }
            .joined(separator: " ")
        return joined.isEmpty ? nil : joined
    }
}
