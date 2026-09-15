import SwiftUI

struct DetailCard: View {
    let session: AgentSession

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            Text(session.title)
                .font(Theme.ui(13, .semibold))
                .foregroundStyle(.white)
                .lineLimit(2)

            Text(session.caption)
                .font(Theme.ui(11))
                .foregroundStyle(Theme.dim)
                .lineLimit(1)

            if let detail = session.detail, !detail.lastAssistantText.isEmpty {
                Text(detail.lastAssistantText)
                    .font(Theme.ui(11.5))
                    .foregroundStyle(.white.opacity(0.72))
                    .lineLimit(3)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if let detail = session.detail {
                VStack(alignment: .leading, spacing: 5) {
                    HStack(spacing: 8) {
                        Text("Context \(Int(detail.contextPercent.rounded()))%")
                            .font(Theme.ui(11, .medium))
                            .foregroundStyle(.white)
                        Spacer()
                        Text(Format.compact(detail.contextTokens))
                            .font(Theme.mono(10.5))
                            .foregroundStyle(Theme.dim)
                    }
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            Capsule().fill(Theme.track)
                            Capsule()
                                .fill(.white.opacity(0.85))
                                .frame(width: max(2, geo.size.width * detail.contextFraction))
                        }
                    }
                    .frame(height: 4)
                }

                HStack(spacing: 6) {
                    AgentMark(agent: session.agent, size: 10, tint: Theme.dim)
                    Text(detail.prettyModel.isEmpty ? session.agent : detail.prettyModel)
                        .font(Theme.ui(11))
                        .foregroundStyle(Theme.dim)
                    if detail.costUSD > 0 {
                        Text("· $\(String(format: "%.2f", detail.costUSD))")
                            .font(Theme.ui(11))
                            .foregroundStyle(Theme.dim)
                    }
                }
            }

            if !session.tasks.isEmpty {
                let running = session.tasks.filter(\.isRunning).count
                HStack(spacing: 6) {
                    Image(systemName: "circle.grid.2x2")
                        .font(Theme.ui(10))
                        .foregroundStyle(Theme.dim)
                    Text("\(session.tasks.count) task\(session.tasks.count == 1 ? "" : "s") · \(running) running")
                        .font(Theme.ui(11))
                        .foregroundStyle(Theme.dim)
                }
            }

            Text(Format.ago(session.updatedAt))
                .font(Theme.ui(11))
                .foregroundStyle(Theme.faint)
        }
        .padding(14)
        .frame(width: 300, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(Color(white: 0.16))
        )
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(.white.opacity(0.10), lineWidth: 1))
    }
}

extension Format {
    static func ago(_ date: Date) -> String {
        let seconds = Int(-date.timeIntervalSinceNow)
        if seconds < 60 { return "active just now" }
        if seconds < 3600 { return "active \(seconds / 60)m ago" }
        if seconds < 86400 { return "active \(seconds / 3600)h ago" }
        return "active \(seconds / 86400)d ago"
    }
}
