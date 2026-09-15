import Foundation

/// Hooks only announce a session when it acts, so a session that is merely
/// open — or any session at all after a restart — would otherwise be invisible.
/// A recently written transcript is the reliable signal that one exists.
enum SessionDiscovery {
    struct Found {
        let id: String
        let cwd: String
        let transcriptPath: String
        let modified: Date
    }

    static func scan(within window: TimeInterval = 300) -> [Found] {
        let root = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".claude/projects")
        guard let entries = try? FileManager.default.subpathsOfDirectory(atPath: root.path) else { return [] }

        let cutoff = Date().addingTimeInterval(-window)
        var found: [Found] = []

        for relative in entries where relative.hasSuffix(".jsonl") {
            // agent-*.jsonl are subagent transcripts, not sessions of their own.
            let name = (relative as NSString).lastPathComponent
            if name.hasPrefix("agent-") { continue }

            let url = root.appendingPathComponent(relative)
            guard let attrs = try? FileManager.default.attributesOfItem(atPath: url.path),
                  let modified = attrs[.modificationDate] as? Date, modified > cutoff,
                  let cwd = cwd(of: url)
            else { continue }

            found.append(Found(
                id: url.deletingPathExtension().lastPathComponent,
                cwd: cwd,
                transcriptPath: url.path,
                modified: modified
            ))
        }
        return found
    }

    private static func cwd(of url: URL) -> String? {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }
        guard let data = try? handle.read(upToCount: 120_000) else { return nil }

        for line in data.split(separator: UInt8(ascii: "\n"), omittingEmptySubsequences: true) {
            guard let obj = try? JSONSerialization.jsonObject(with: Data(line)) as? [String: Any],
                  let cwd = obj["cwd"] as? String, !cwd.isEmpty
            else { continue }
            return cwd
        }
        return nil
    }
}
