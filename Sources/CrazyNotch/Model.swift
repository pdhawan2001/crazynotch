import Foundation

struct AgentSession: Identifiable, Equatable {
    enum State: String {
        case working, idle, waiting, approving

        /// Sort weight — whatever needs a human wins.
        var urgency: Int {
            switch self {
            case .approving: return 0
            case .waiting:   return 1
            case .working:   return 2
            case .idle:      return 3
            }
        }

        var label: String {
            switch self {
            case .working:   return "Working"
            case .idle:      return "Finished"
            case .waiting:   return "Needs you"
            case .approving: return "Your turn"
            }
        }
    }

    let id: String
    var agent: String = "Claude Code"
    var cwd: String = ""
    var state: State = .idle
    var updatedAt: Date = Date()
    var pending: PendingApproval?

    /// Falls back through what is actually known: the chat's own title if the
    /// transcript has produced one yet, then the last thing the user typed.
    var title: String {
        if let chatTitle = detail?.title, !chatTitle.isEmpty { return chatTitle }
        return agent
    }

    var branch: String = ""
    var transcriptPath: String = ""
    var detail: SessionDetail?
    var tasks: [BackgroundTask] = []

    /// Folder name only — the notch has no room for a full path.
    var project: String {
        let name = (cwd as NSString).lastPathComponent
        return name.isEmpty ? "—" : name
    }

    var caption: String {
        branch.isEmpty ? "\(project) · \(agent)" : "\(project) · \(branch) · \(agent)"
    }
}

/// A tool call parked on the PermissionRequest hook, holding that hook's
/// process open until the user taps.
struct PendingApproval: Identifiable, Equatable {
    let id: String
    let toolName: String
    let summary: String
    let reason: String
    let createdAt: Date

    static func == (a: PendingApproval, b: PendingApproval) -> Bool { a.id == b.id }
}

enum ToolSummary {
    static func make(tool: String, input: [String: Any]) -> String {
        switch tool {
        case "Bash":
            let cmd = input["command"] as? String ?? ""
            return cmd
        case "Edit", "Write", "NotebookEdit":
            let path = input["file_path"] as? String ?? ""
            return "\(tool) \((path as NSString).lastPathComponent)"
        case "Read":
            let path = input["file_path"] as? String ?? ""
            return "Read \((path as NSString).lastPathComponent)"
        case "WebFetch":
            let url = input["url"] as? String ?? ""
            return "Fetch \(url)"
        default:
            let parts = input
                .sorted { $0.key < $1.key }
                .compactMap { k, v -> String? in
                    guard !(v is [Any]), !(v is [String: Any]) else { return nil }
                    return "\(k): \(v)"
                }
            let joined = parts.joined(separator: "  ")
            return joined.isEmpty ? tool : joined
        }
    }
}


/// Read straight from the session's transcript, so the numbers match what
/// Claude Code itself is working with rather than being inferred.
struct SessionDetail: Equatable {
    var title: String = ""
    var model: String = ""
    var contextPercent: Double = 0
    var costUSD: Double = 0
    var lastAssistantText: String = ""
    var contextTokens: Int = 0
    var contextWindow: Int = 200_000

    var contextFraction: Double { min(contextPercent / 100, 1) }

}


struct BackgroundTask: Identifiable, Equatable {
    let id: String
    let kind: String
    let status: String
    let description: String

    init?(_ json: [String: Any]) {
        guard let id = json["id"] as? String else { return nil }
        self.id = id
        kind = json["type"] as? String ?? "task"
        status = json["status"] as? String ?? ""
        description = json["description"] as? String ?? ""
    }

    var isRunning: Bool { status == "running" }
}
