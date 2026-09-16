import SwiftUI
import AppKit

struct NotchView: View {
    @EnvironmentObject var store: SessionStore

    private var notch: CGSize { NSScreen.notched?.notchSize ?? CGSize(width: 179, height: 32) }

    /// The reveal is a mask growing from the notch's own footprint rather than
    /// a window resize: the window is already at its final size, so the panel
    /// unfolds out of the cutout instead of the frame stepping open.
    private var maskWidth: CGFloat {
        store.expanded ? NotchWindow.panelWidth : NotchWindow.peekWidth(store: store)
    }
    private var maskHeight: CGFloat { store.expanded ? store.panelHeight : notch.height }

    var body: some View {
        // Only ever build the view that fits the current window. Keeping the
        // 720pt panel in the tree while collapsed made the layout 720pt wide
        // inside a 223pt window, pushing the drawn content sideways by half
        // the difference.
        Group {
            if store.expanded {
                PanelView().frame(width: NotchWindow.panelWidth, height: store.panelHeight)
            } else {
                PeekView()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .mask(
            UnevenRoundedRectangle(
                bottomLeadingRadius: store.expanded ? Theme.panelCorner : 10,
                bottomTrailingRadius: store.expanded ? Theme.panelCorner : 10
            )
            .frame(width: maskWidth, height: maskHeight)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        )
        .animation(.spring(response: 0.42, dampingFraction: 0.86), value: store.expanded)
        .animation(.spring(response: 0.42, dampingFraction: 0.86), value: store.panelHeight)
    }
}

private struct PeekView: View {
    @EnvironmentObject var store: SessionStore

    private var notch: CGSize { NSScreen.notched?.notchSize ?? CGSize(width: 179, height: 32) }

    var body: some View {
        HStack(spacing: 0) {
            leading
                .frame(maxWidth: .infinity, alignment: .trailing)
                .padding(.trailing, 7)
                .padding(.leading, 9)

            Color.clear.frame(width: notch.width)

            trailing
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.leading, 7)
                .padding(.trailing, 9)
        }
        .frame(height: notch.height)
        .background(
            UnevenRoundedRectangle(bottomLeadingRadius: 7, bottomTrailingRadius: 7)
                .fill(.black)
                .opacity(store.collapsedMode == .hidden ? 0 : 1)
        )
    }

    @ViewBuilder
    private var leading: some View {
        if let s = store.attention.first {
            AgentMark(agent: s.agent, size: 12, tint: .white)
        }
    }

    @ViewBuilder
    private var trailing: some View {
        if let s = store.attention.first {
            Image(systemName: s.state == .approving ? "exclamationmark.circle.fill" : "questionmark.circle.fill")
                .font(Theme.ui(12))
                .foregroundStyle(Theme.alert)
        }
    }
}

private struct PanelView: View {
    @EnvironmentObject var store: SessionStore

    var body: some View {
        VStack(spacing: 0) {
            HeaderBar()

            do {
                if store.showMeters, !store.usage.isEmpty {
                    MetersBlock()
                    Divider().overlay(Theme.hairline)
                }

            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: 0) {
                    ForEach(store.sorted) { session in
                        SessionRow(session: session)
                        if session.id != store.sorted.last?.id {
                            Divider().overlay(Theme.hairline)
                        }
                    }
                }
            }

                if store.sessions.isEmpty {
                    Text("no agents running")
                        .font(Theme.mono(11))
                        .foregroundStyle(Theme.faint)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 24)
                }
            }

            Spacer(minLength: 0)
        }
        .background(
            ZStack {
                VisualEffect()
                Color.black.opacity(0.20)
            }
        )
        .clipShape(
            UnevenRoundedRectangle(
                bottomLeadingRadius: Theme.panelCorner,
                bottomTrailingRadius: Theme.panelCorner
            )
        )
    }
}

private struct HeaderBar: View {
    @EnvironmentObject var store: SessionStore

    var body: some View {
        HStack(spacing: 0) {
            Text("\(store.sessions.count) agent\(store.sessions.count == 1 ? "" : "s")")
                .font(Theme.ui(13, .semibold))
                .foregroundStyle(.white)
            Spacer()
            HStack(spacing: HeaderButton.spacing) {
                HeaderIcon(button: .usage) { WindowManager.openTokenHistory() }
                HeaderIcon(button: .settings) { WindowManager.openSettings(store: store) }
            }
        }
        .padding(.leading, 20)
        .padding(.trailing, HeaderButton.trailing)
        .frame(height: Theme.headerHeight)
        .background(Color.black)
    }
}

private struct MetersBlock: View {
    @EnvironmentObject var store: SessionStore

    var body: some View {
        HStack(alignment: .top, spacing: 26) {
            MeterGroup(agent: "Claude Code", windows: store.usage)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
    }
}

private struct MeterGroup: View {
    let agent: String
    let windows: [UsageWindow]

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 7) {
                AgentMark(agent: agent, size: 12, tint: .white)
                Text(agent)
                    .font(Theme.ui(12, .semibold))
                    .foregroundStyle(.white)
            }
            ForEach(windows) { MeterRow(window: $0) }
        }
    }
}

private struct MeterRow: View {
    let window: UsageWindow

    var body: some View {
        HStack(spacing: 8) {
            Text(window.id)
                .font(Theme.mono(10))
                .foregroundStyle(Theme.dim)
                .frame(width: 62, alignment: .leading)

            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 1.5).fill(Theme.track)
                RoundedRectangle(cornerRadius: 1.5)
                    .fill((window.percent ?? 0) >= 100 ? Theme.alertRail : Color.white.opacity(0.88))
                    .frame(width: window.fraction <= 0 ? 0 : max(2, 433 * window.fraction))
                HStack(spacing: 0) {
                    ForEach(1..<6) { _ in
                        Spacer()
                        Rectangle().fill(.black.opacity(0.42)).frame(width: 1)
                    }
                    Spacer()
                }
            }
            .frame(width: 433, height: 8)

            Circle()
                .stroke(Theme.faint, lineWidth: 1)
                .frame(width: 5, height: 5)

            Text(window.percentLabel)
                .font(Theme.ui(12, .semibold))
                .foregroundStyle(window.percent == nil ? Theme.dim : .white)
                .frame(width: 44, alignment: .trailing)

            Text(window.resetLabel)
                .font(Theme.ui(10.5))
                .foregroundStyle(Theme.dim)
                .frame(width: 52, alignment: .trailing)
        }
        .frame(height: 18)
    }
}

private struct SessionRow: View {
    @EnvironmentObject var store: SessionStore
    let session: AgentSession

    private var needsYou: Bool { session.state == .approving || session.state == .waiting }

    var body: some View {
        HStack(spacing: 0) {
            Rectangle()
                .fill(needsYou ? Theme.alertRail : .clear)
                .frame(width: 3)

            VStack(alignment: .leading, spacing: 3) {
                HStack(alignment: .top, spacing: 11) {
                    AgentMark(agent: session.agent, size: 16, tint: .white)
                        .padding(.top, 1)

                    VStack(alignment: .leading, spacing: 3) {
                        Text(session.title)
                            .font(Theme.ui(15, .semibold))
                            .foregroundStyle(.white)
                            .lineLimit(1)
                        Text(session.caption)
                            .font(Theme.ui(12.5))
                            .foregroundStyle(Theme.dim)
                            .lineLimit(1)
                    }

                    Spacer()
                    StatusPill(state: session.state)
                }

                if let pending = session.pending {
                    ApprovalInline(approval: pending)
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 13)
        }
        .background(needsYou ? Theme.alertWash.opacity(0.55) : .clear)
    }
}

private struct StatusPill: View {
    let state: AgentSession.State

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: icon).font(Theme.ui(11))
            Text(state.label).font(Theme.ui(12, .medium))
        }
        .foregroundStyle(color)
    }

    private var icon: String {
        switch state {
        case .working: return "play.circle.fill"
        case .idle:    return "checkmark.circle.fill"
        default:       return "pause.circle.fill"
        }
    }

    private var color: Color {
        switch state {
        case .working: return .white
        case .idle:    return Theme.dim
        default:       return Theme.alert
        }
    }
}

private struct ApprovalInline: View {
    @EnvironmentObject var store: SessionStore
    let approval: PendingApproval

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if !approval.reason.isEmpty {
                Text(approval.reason)
                    .font(Theme.ui(12))
                    .foregroundStyle(.white.opacity(0.62))
                    .lineLimit(1)
            }
            HStack(spacing: 10) {
                Text(approval.summary)
                    .font(Theme.mono(12))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)
                DecisionButton(title: "Deny", filled: false) {
                    store.resolve(approval.id, decision: "deny")
                }
                DecisionButton(title: "Approve", filled: true) {
                    store.resolve(approval.id, decision: "allow")
                }
            }
        }
        .padding(.top, 2)
    }
}

private struct DecisionButton: View {
    let title: String
    let filled: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(Theme.ui(12.5, .medium))
                .foregroundStyle(filled ? .black : .white.opacity(0.85))
                .padding(.horizontal, 14)
                .padding(.vertical, 5)
                .background(Capsule().fill(filled ? Color.white : Color.white.opacity(0.14)))
        }
        .buttonStyle(.plain)
    }
}


enum HeaderButton: String {
    case usage, settings

    static let size: CGFloat = 28
    static let spacing: CGFloat = 6
    static let trailing: CGFloat = 14

    var symbol: String {
        switch self {
        case .usage:    return "chart.bar.fill"
        case .settings: return "gearshape.fill"
        }
    }

    /// Hit-tested against the cursor rather than SwiftUI hover, which this
    /// panel does not deliver reliably.
    static func hit(x: CGFloat, y: CGFloat, width: CGFloat) -> HeaderButton? {
        guard y >= 0, y <= Theme.headerHeight else { return nil }
        let settingsMaxX = width - trailing
        let settingsMinX = settingsMaxX - size
        let usageMaxX = settingsMinX - spacing
        let usageMinX = usageMaxX - size

        if x >= settingsMinX, x <= settingsMaxX { return .settings }
        if x >= usageMinX, x <= usageMaxX { return .usage }
        return nil
    }
}

private struct HeaderIcon: View {
    @EnvironmentObject var store: SessionStore
    let button: HeaderButton
    let action: () -> Void

    private var hovered: Bool { store.hoveredButton == button }

    var body: some View {
        Button(action: action) {
            Image(systemName: button.symbol)
                .font(Theme.ui(12.5))
                .foregroundStyle(hovered ? .white : Theme.dim)
                .frame(width: HeaderButton.size, height: HeaderButton.size)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
