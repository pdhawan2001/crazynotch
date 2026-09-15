import Foundation
import SwiftUI

@MainActor
final class SessionStore: ObservableObject {
    @Published private(set) var sessions: [AgentSession] = []
    @Published var expanded = false
    private var detailLoadedAt: [String: Date] = [:]
    @Published private(set) var liveUsage: [UsageWindow] = []
    @Published private(set) var usageObservedAt: Date?

    /// Only the status line knows these. With no reading the meters stay blank
    /// rather than showing a locally invented number.
    var usage: [UsageWindow] { liveUsage }

    var usageIsStale: Bool {
        guard let usageObservedAt else { return true }
        return Date().timeIntervalSince(usageObservedAt) > 900
    }
    @Published var showMeters = true
    @Published var hoveredID: String?
    @Published var hoveredButton: HeaderButton?

    private var resolvers: [String: CheckedContinuation<String, Never>] = [:]
    private var pruneTimer: Timer?

    init() {
        pruneTimer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.prune()
                self?.discover()
            }
            Task { await self?.refreshUsage() }
        }
        loadStoredUsage()
        Task { await refreshUsage() }
        discover()
    }

    /// Adds sessions the hooks have not announced; never overrides state that
    /// a hook has already reported.
    func discover() {
        Task.detached(priority: .utility) {
            let found = SessionDiscovery.scan()
            await MainActor.run {
                for item in found where self.index(item.id) == nil {
                    self.upsert(id: item.id, cwd: item.cwd) {
                        $0.state = .idle
                        $0.transcriptPath = item.transcriptPath
                        $0.updatedAt = item.modified
                    }
                }
            }
        }
    }

    func refreshUsage() async {
        await UsageTracker.shared.refresh()
    }


    /// Drives the panel's window height so it ends just under its last row
    /// instead of leaving dead space below the content.
    var panelHeight: CGFloat {
        var h = Theme.headerHeight
        if showMeters, !usage.isEmpty { h += 22 + CGFloat(usage.count) * 18 + 24 }
        for session in sorted {
            h += 66
            if session.pending != nil { h += session.pending?.reason.isEmpty == false ? 60 : 40 }
        }
        if sessions.isEmpty { h += 60 }
        return min(max(h + 8, 120), 560)
    }

    var sorted: [AgentSession] {
        sessions.sorted {
            $0.state.urgency != $1.state.urgency
                ? $0.state.urgency < $1.state.urgency
                : $0.updatedAt > $1.updatedAt
        }
    }

    var attention: [AgentSession] { sorted.filter { $0.state == .approving || $0.state == .waiting } }
    var working: [AgentSession] { sessions.filter { $0.state == .working } }
    var headline: AgentSession? { attention.first ?? sorted.first }

    /// Idle agents earn no pixels; working ones get only a count, so the notch
    /// stays quiet until something actually wants a human.
    enum CollapsedMode {
        case hidden, full
    }

    var collapsedMode: CollapsedMode {
        attention.isEmpty ? .hidden : .full
    }

    private func index(_ id: String) -> Int? { sessions.firstIndex { $0.id == id } }

    private func rowHeight(_ session: AgentSession) -> CGFloat {
        var h: CGFloat = 66
        if let pending = session.pending { h += pending.reason.isEmpty ? 40 : 60 }
        return h
    }

    /// Mirrors the panel's stacking order so the window can tell which row the
    /// cursor is over without SwiftUI hover events.
    var rowLayout: [(id: String, top: CGFloat, height: CGFloat)] {
        var y = Theme.headerHeight
        if showMeters, !usage.isEmpty { y += 22 + CGFloat(usage.count) * 18 + 24 }
        return sorted.map { session in
            let h = rowHeight(session)
            defer { y += h }
            return (session.id, y, h)
        }
    }

    func session(_ id: String) -> AgentSession? { index(id).map { sessions[$0] } }

    /// Refreshes whenever the data is stale: the context grows with every turn,
    /// so loading once at registration leaves the card showing the size the
    /// session had when it started.
    func loadDetail(_ id: String, force: Bool = false) {
        guard let i = index(id) else { return }
        if !force, let loaded = detailLoadedAt[id], Date().timeIntervalSince(loaded) < 10 { return }
        detailLoadedAt[id] = Date()
        let path = sessions[i].transcriptPath
        guard !path.isEmpty else { return }
        Task.detached(priority: .utility) {
            let detail = TranscriptReader.detail(path: path)
            await MainActor.run { self.apply(detail, to: id) }
        }
    }

    private var usageStore: URL {
        let dir = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("CrazyNotch")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("limits.json")
    }

    /// A reading stays meaningful across restarts because the resets are
    /// absolute instants; dropping it on launch just hides information that is
    /// still true, so it is written to disk and reloaded.
    private func persistUsage() {
        let payload: [String: Any] = [
            "observedAt": usageObservedAt?.timeIntervalSince1970 ?? 0,
            "windows": liveUsage.map { window -> [String: Any] in
                ["id": window.id,
                 "percent": window.percent as Any,
                 "resetsAt": window.resetsAt?.timeIntervalSince1970 ?? 0]
            },
        ]
        guard let data = try? JSONSerialization.data(withJSONObject: payload) else { return }
        try? data.write(to: usageStore, options: .atomic)
    }

    private func loadStoredUsage() {
        guard let data = try? Data(contentsOf: usageStore),
              let payload = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let rows = payload["windows"] as? [[String: Any]]
        else { return }

        if let observed = payload["observedAt"] as? Double, observed > 0 {
            usageObservedAt = Date(timeIntervalSince1970: observed)
        }
        liveUsage = rows.compactMap { row in
            guard let id = row["id"] as? String else { return nil }
            let resets = (row["resetsAt"] as? Double).flatMap { $0 > 0 ? Date(timeIntervalSince1970: $0) : nil }
            return UsageWindow(id: id, percent: row["percent"] as? Double, resetsAt: resets)
        }
    }

    func applyStatusLine(_ payload: [String: Any]) {
        if let limits = payload["rate_limits"] as? [String: Any] {
            var windows: [UsageWindow] = []
            for (key, label) in [("five_hour", "5H"), ("seven_day", "WEEK")] {
                guard let window = limits[key] as? [String: Any],
                      let percent = (window["used_percentage"] as? Double)
                        ?? (window["used_percentage"] as? Int).map(Double.init),
                      let resetsRaw = (window["resets_at"] as? Double)
                        ?? (window["resets_at"] as? Int).map(Double.init)
                else { continue }
                let resets = Date(timeIntervalSince1970: resetsRaw)
                windows.append(UsageWindow(id: label, percent: percent, resetsAt: resets))
            }
            if !windows.isEmpty {
                let weeklyReset = windows.first { $0.id == "WEEK" }?.resetsAt
                usageObservedAt = Date()
                Task { [weak self] in
                    let fable = await UsageTracker.shared.fableWindow(resetsAt: weeklyReset)
                    await MainActor.run {
                        self?.liveUsage = windows + [fable]
                        self?.persistUsage()
                    }
                }
            }
        }

        guard let id = payload["session_id"] as? String, let i = index(id) else { return }

        if let name = payload["session_name"] as? String, !name.isEmpty {
            var detail = sessions[i].detail ?? SessionDetail()
            detail.title = name
            sessions[i].detail = detail
        }

        if let context = payload["context_window"] as? [String: Any] {
            var detail = sessions[i].detail ?? SessionDetail()
            detail.contextPercent = context["used_percentage"] as? Double ?? detail.contextPercent
            detail.contextTokens = context["total_input_tokens"] as? Int ?? detail.contextTokens
            detail.contextWindow = context["context_window_size"] as? Int ?? detail.contextWindow
            if let model = payload["model"] as? [String: Any],
               let name = model["display_name"] as? String {
                detail.model = name
            }
            if let cost = payload["cost"] as? [String: Any],
               let usd = cost["total_cost_usd"] as? Double {
                detail.costUSD = usd
            }
            sessions[i].detail = detail
        }
    }

    func hover(_ id: String?) {
        guard hoveredID != id else { return }
        hoveredID = id
        guard let id else { return }
        loadDetail(id, force: true)
    }

    private func apply(_ detail: SessionDetail?, to id: String) {
        guard var detail, let i = index(id) else { return }
        if let live = sessions[i].detail, live.contextPercent > 0 {
            detail.contextPercent = live.contextPercent
            detail.contextWindow = live.contextWindow
            detail.contextTokens = live.contextTokens
        }
        if let existing = sessions[i].detail, !existing.lastAssistantText.isEmpty {
            detail.lastAssistantText = existing.lastAssistantText
        }
        sessions[i].detail = detail
    }

    func upsert(id: String, cwd: String?, mutate: (inout AgentSession) -> Void) {
        if let i = index(id) {
            if let cwd, sessions[i].cwd.isEmpty { sessions[i].cwd = cwd }
            mutate(&sessions[i])
            sessions[i].updatedAt = Date()
            loadDetail(id)
        } else {
            var s = AgentSession(id: id)
            s.cwd = cwd ?? ""
            mutate(&s)
            sessions.append(s)
            loadDetail(id)
        }
    }

    func remove(id: String) {
        if let i = index(id), let p = sessions[i].pending { resolve(p.id, decision: "ask") }
        sessions.removeAll { $0.id == id }
    }

    /// A session killed without SessionEnd would otherwise sit in the notch
    /// forever, and a discovered one is only evidence of life while its
    /// transcript keeps moving.
    private func prune() {
        let live = Set(SessionDiscovery.scan().map(\.id))
        let cutoff = Date().addingTimeInterval(-10 * 60)
        sessions.removeAll { session in
            guard session.state != .approving else { return false }
            if live.contains(session.id) { return false }
            return session.updatedAt < cutoff
        }
    }

    /// Suspends until the user taps, so the caller can hold the hook's process
    /// open. Falls back to "ask" on timeout, which hands the decision back to
    /// the terminal prompt rather than silently allowing anything.
    func awaitDecision(sessionID: String, cwd: String?, approval: PendingApproval) async -> String {
        upsert(id: sessionID, cwd: cwd) {
            $0.state = .approving
            $0.pending = approval
        }
        expanded = true

        let decision = await withCheckedContinuation { (cont: CheckedContinuation<String, Never>) in
            resolvers[approval.id] = cont
        }

        upsert(id: sessionID, cwd: nil) {
            if $0.pending?.id == approval.id {
                $0.pending = nil
                $0.state = .working
            }
        }
        return decision
    }

    func resolve(_ approvalID: String, decision: String) {
        guard let cont = resolvers.removeValue(forKey: approvalID) else { return }
        cont.resume(returning: decision)
    }
}
