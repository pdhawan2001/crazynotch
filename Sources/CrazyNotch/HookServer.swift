import Foundation
import Network
import AppKit

struct HTTPRequest {
    let path: String
    let body: Data

    /// Returns nil while the request is still arriving, so the caller keeps reading.
    init?(_ buffer: Data) {
        guard let headEnd = buffer.range(of: Data("\r\n\r\n".utf8)) else { return nil }
        let head = String(decoding: buffer[..<headEnd.lowerBound], as: UTF8.self)
        let lines = head.components(separatedBy: "\r\n")
        let parts = lines.first?.components(separatedBy: " ") ?? []
        guard parts.count >= 2 else { return nil }

        let length = lines
            .first { $0.lowercased().hasPrefix("content-length:") }
            .flatMap { Int($0.dropFirst("content-length:".count).trimmingCharacters(in: .whitespaces)) } ?? 0

        let bodyStart = headEnd.upperBound
        let available = buffer.count - bodyStart
        guard available >= length else { return nil }

        path = parts[1]
        body = buffer.subdata(in: bodyStart..<(bodyStart + length))
    }
}

final class HookServer {
    private let store: SessionStore
    private let port: UInt16
    private var listener: NWListener?
    private let queue = DispatchQueue(label: "crazynotch.hooks")

    init(store: SessionStore, port: UInt16) {
        self.store = store
        self.port = port
    }

    func start() throws {
        let params = NWParameters.tcp
        params.allowLocalEndpointReuse = true
        params.requiredLocalEndpoint = .hostPort(host: .ipv4(.loopback), port: .init(rawValue: port)!)

        let listener = try NWListener(using: params)
        listener.newConnectionHandler = { [weak self] conn in self?.accept(conn) }
        listener.start(queue: queue)
        self.listener = listener
    }

    private func accept(_ conn: NWConnection) {
        conn.start(queue: queue)
        read(conn, buffer: Data())
    }

    private func read(_ conn: NWConnection, buffer: Data) {
        conn.receive(minimumIncompleteLength: 1, maximumLength: 1 << 20) { [weak self] data, _, isComplete, error in
            guard let self else { return }
            var buf = buffer
            if let data { buf.append(data) }

            if let request = HTTPRequest(buf) {
                self.route(request, conn)
            } else if error == nil && !isComplete {
                self.read(conn, buffer: buf)
            } else {
                conn.cancel()
            }
        }
    }

    private func route(_ request: HTTPRequest, _ conn: NWConnection) {
        switch request.path {
        case "/health":
            respond(conn, Data("ok".utf8), type: "text/plain")
        case "/state":
            Task { [weak self] in
                guard let self else { return }
                let body = await MainActor.run { () -> Data in
                    let windows = self.store.usage.map { w -> [String: Any] in
                        ["id": w.id, "percent": w.percent,
                         "resetsAt": w.resetsAt?.timeIntervalSince1970 ?? 0]
                    }
                    let screens = NSScreen.screens.map { s -> [String: Any] in
                        ["name": s.localizedName,
                         "frame": ["x": s.frame.minX, "y": s.frame.minY,
                                   "w": s.frame.width, "h": s.frame.height],
                         "safeTop": s.safeAreaInsets.top,
                         "notchW": s.notchSize?.width ?? 0]
                    }
                    let notchRect: [String: Any] = {
                        guard let s = NSScreen.notched,
                              let l = s.auxiliaryTopLeftArea,
                              let r = s.auxiliaryTopRightArea else { return [:] }
                        return ["left": l.maxX, "right": r.minX,
                                "centre": (l.maxX + r.minX) / 2,
                                "width": r.minX - l.maxX]
                    }()
                    let payload: [String: Any] = [
                        "screens": screens,
                        "notch": notchRect,
                        "panelFrame": Diagnostics.panelFrame.map {
                            ["x": $0.minX, "y": $0.minY, "w": $0.width, "h": $0.height]
                        } ?? [:],
                        "live": !self.store.liveUsage.isEmpty,
                        "windows": windows,
                        "sessions": self.store.sorted.map { s -> [String: Any] in
                            ["project": s.project, "title": s.title, "state": s.state.rawValue,
                             "context": s.detail?.contextPercent ?? 0]
                        },
                    ]
                    return (try? JSONSerialization.data(withJSONObject: payload, options: [.prettyPrinted, .sortedKeys])) ?? Data()
                }
                self.respond(conn, body)
            }
        case "/statusline":
            Task { [weak self] in
                guard let self,
                      let payload = try? JSONSerialization.jsonObject(with: request.body) as? [String: Any]
                else { self?.respond(conn, Data()); return }
                await MainActor.run { self.store.applyStatusLine(payload) }
                self.respond(conn, Data())
            }
        case "/hook":
            Task { [weak self] in
                let reply = await self?.handleHook(request.body, conn: conn) ?? Data()
                self?.respond(conn, reply)
            }
        default:
            respond(conn, Data(), status: "404 Not Found")
        }
    }

    /// Anything returned here is printed by the hook shim, and a hook's stdout
    /// lands in Claude's context — so every event except PermissionRequest must
    /// answer with an empty body.
    private func handleHook(_ body: Data, conn: NWConnection) async -> Data {
        Self.trace(body)
        guard let json = try? JSONSerialization.jsonObject(with: body) as? [String: Any],
              let event = json["hook_event_name"] as? String,
              let sessionID = json["session_id"] as? String
        else { return Data() }

        let cwd = json["cwd"] as? String
        let transcript = json["transcript_path"] as? String ?? ""

        if event == "PermissionRequest" {
            return await permissionRequest(json, sessionID: sessionID, cwd: cwd, conn: conn)
        }

        await MainActor.run {
            // Only events that genuinely end the request may cancel it. A
            // Notification fires milliseconds after PermissionRequest for the
            // very same prompt, so clearing on any event resolved the approval
            // as "ask" before the user could reach the button.
            if event == "SessionEnd", let pending = store.session(sessionID)?.pending {
                store.resolve(pending.id, decision: "ask")
            }

            switch event {
            case "SessionStart":
                let branch = cwd.flatMap(Git.branch(at:)) ?? ""
                store.upsert(id: sessionID, cwd: cwd) {
                    $0.state = .idle
                    $0.branch = branch
                    if !transcript.isEmpty { $0.transcriptPath = transcript }
                }
            case "UserPromptSubmit":
                let prompt = json["prompt"] as? String ?? ""
                store.upsert(id: sessionID, cwd: cwd) {
                    $0.state = .working
                    if !transcript.isEmpty { $0.transcriptPath = transcript }
                    if Self.isTypedByHuman(prompt) { $0.lastMessage = Self.oneLine(prompt) }
                }
            case "Stop":
                // The hook hands over the final message and the live task list,
                // so neither has to be reconstructed from the transcript.
                let summary = json["last_assistant_message"] as? String ?? ""
                let tasks = (json["background_tasks"] as? [[String: Any]] ?? []).compactMap(BackgroundTask.init)
                store.upsert(id: sessionID, cwd: cwd) {
                    $0.state = .idle
                    if !transcript.isEmpty { $0.transcriptPath = transcript }
                    $0.tasks = tasks
                    if !summary.isEmpty {
                        var detail = $0.detail ?? SessionDetail()
                        detail.lastAssistantText = Self.oneLine(summary)
                        $0.detail = detail
                    }
                }
            case "Notification":
                // Most notification types are status, not a question. idle_prompt
                // in particular only means Claude is sitting idle, and treating it
                // as attention raised the peek when nothing needed answering.
                let kind = json["notification_type"] as? String ?? ""
                let wantsHuman = ["permission_prompt", "agent_needs_input",
                                  "elicitation_dialog", "elicitation_url_dialog"]
                guard wantsHuman.contains(kind) else { break }

                let message = json["notification_message"] as? String ?? "Needs your input"
                store.upsert(id: sessionID, cwd: cwd) {
                    $0.state = .waiting
                    $0.lastMessage = Self.oneLine(message)
                }
            case "SessionEnd":
                store.remove(id: sessionID)
            default:
                break
            }
        }
        return Data()
    }

    private func permissionRequest(_ json: [String: Any], sessionID: String, cwd: String?, conn: NWConnection) async -> Data {
        let tool = json["tool_name"] as? String ?? "Tool"
        let input = json["tool_input"] as? [String: Any] ?? [:]
        let id = json["tool_use_id"] as? String ?? UUID().uuidString
        let summary = ToolSummary.make(tool: tool, input: input)

        let approval = PendingApproval(
            id: id, toolName: tool,
            summary: Self.oneLine(summary),
            reason: Self.oneLine(json["tool_input"].flatMap { ($0 as? [String: Any])?["description"] as? String } ?? ""),
            createdAt: Date()
        )

        // Claude moves on the moment the hook process dies — whether it timed
        // out or the user answered in Claude's own prompt — so the card has to
        // go with it rather than lingering until the internal timeout.
        conn.stateUpdateHandler = { [weak self] state in
            switch state {
            case .cancelled, .failed:
                Task { @MainActor in self?.store.resolve(id, decision: "ask") }
            default:
                break
            }
        }

        let decision = await withTaskGroup(of: String.self) { group -> String in
            group.addTask { @MainActor in
                await self.store.awaitDecision(sessionID: sessionID, cwd: cwd, approval: approval)
            }
            group.addTask {
                // Claude puts its own prompt up 6s after asking and stops
                // waiting on the hook, so holding the card any longer just
                // leaves it stranded after the question was answered in chat.
                try? await Task.sleep(nanoseconds: 10 * 1_000_000_000)
                await MainActor.run { self.store.resolve(id, decision: "ask") }
                return "ask"
            }
            let first = await group.next() ?? "ask"
            group.cancelAll()
            return first
        }

        let payload: [String: Any] = [
            "hookSpecificOutput": [
                "hookEventName": "PermissionRequest",
                "decision": decision,
                "decisionReason": decision == "ask"
                    ? "CrazyNotch timed out"
                    : "\(decision == "allow" ? "Approved" : "Denied") from the notch",
            ]
        ]
        Self.note("  -> returned \(decision) for \(tool)")
        return (try? JSONSerialization.data(withJSONObject: payload)) ?? Data()
    }

    static func note(_ text: String) {
        let url = URL(fileURLWithPath: "/tmp/crazynotch-hooks.log")
        let line = "\(ISO8601DateFormatter().string(from: Date()))\(text)\n"
        if let handle = try? FileHandle(forWritingTo: url) {
            handle.seekToEndOfFile(); handle.write(Data(line.utf8)); try? handle.close()
        }
    }

    /// UserPromptSubmit also fires when the harness re-invokes a session on its
    /// own; those carry notification text as the prompt and must not be shown
    /// as something the user said.
    /// One line per received hook, so a session that never reaches the app can
    /// be told apart from one whose decision is being ignored.
    static func trace(_ body: Data) {
        guard let json = try? JSONSerialization.jsonObject(with: body) as? [String: Any] else { return }
        let event = json["hook_event_name"] as? String ?? "?"
        let session = (json["session_id"] as? String)?.prefix(8) ?? "?"
        let tool = json["tool_name"] as? String ?? ""
        let kind = json["notification_type"] as? String ?? ""
        let cmd = ((json["tool_input"] as? [String: Any])?["command"] as? String ?? "")
            .prefix(48).replacingOccurrences(of: "\n", with: " ")
        let line = "\(ISO8601DateFormatter().string(from: Date())) \(event) \(session) \(tool)\(kind) \(cmd)\n"
        let url = URL(fileURLWithPath: "/tmp/crazynotch-hooks.log")
        if let handle = try? FileHandle(forWritingTo: url) {
            handle.seekToEndOfFile()
            handle.write(Data(line.utf8))
            try? handle.close()
        } else {
            try? Data(line.utf8).write(to: url)
        }
    }

    static func isTypedByHuman(_ text: String) -> Bool {
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { return false }
        let robots = ["<task-notification", "<system-reminder", "[SYSTEM NOTIFICATION", "<command-name"]
        return !robots.contains { t.lowercased().hasPrefix($0.lowercased()) }
    }

    static func oneLine(_ text: String) -> String {
        let flat = text
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
            .joined(separator: " ")
        return flat.count > 240 ? String(flat.prefix(240)) + "…" : flat
    }

    private func respond(_ conn: NWConnection, _ body: Data, status: String = "200 OK", type: String = "application/json") {
        var head = "HTTP/1.1 \(status)\r\n"
        head += "Content-Type: \(type)\r\n"
        head += "Content-Length: \(body.count)\r\n"
        head += "Connection: close\r\n\r\n"
        conn.send(content: Data(head.utf8) + body, completion: .contentProcessed { _ in conn.cancel() })
    }
}
