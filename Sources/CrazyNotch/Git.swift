import Foundation

enum Git {
    /// HEAD is a small text file, so the branch can be read directly rather
    /// than spawning a git process for every session that registers.
    static func branch(at path: String) -> String? {
        let root = URL(fileURLWithPath: path)
        guard let gitPath = resolveGitDir(root) else { return nil }

        let head = gitPath.appendingPathComponent("HEAD")
        guard let raw = try? String(contentsOf: head, encoding: .utf8) else { return nil }

        let line = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard line.hasPrefix("ref: ") else { return nil }
        let name = (line.dropFirst(5) as NSString).lastPathComponent
        return name.isEmpty || name == "HEAD" ? nil : name
    }

    /// .git is a directory in a normal clone and a file pointing elsewhere in a
    /// worktree, and the search walks up because a session's cwd is often a
    /// subdirectory of the repository.
    private static func resolveGitDir(_ start: URL) -> URL? {
        var dir = start
        for _ in 0..<12 {
            let candidate = dir.appendingPathComponent(".git")
            var isDirectory: ObjCBool = false
            if FileManager.default.fileExists(atPath: candidate.path, isDirectory: &isDirectory) {
                if isDirectory.boolValue { return candidate }
                if let pointer = try? String(contentsOf: candidate, encoding: .utf8),
                   let path = pointer.split(separator: " ").last {
                    return URL(fileURLWithPath: path.trimmingCharacters(in: .whitespacesAndNewlines))
                }
            }
            let parent = dir.deletingLastPathComponent()
            if parent.path == dir.path { break }
            dir = parent
        }
        return nil
    }
}
