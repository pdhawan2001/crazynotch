import SwiftUI
import ServiceManagement

struct SettingsWindowView: View {
    enum Section: String, CaseIterable, Identifiable {
        case general = "General"
        case notch = "Notch"
        case panel = "Panel"
        case planUsage = "Plan usage"
        case about = "About"

        var id: String { rawValue }

        var symbol: String {
            switch self {
            case .general:   return "gearshape.fill"
            case .notch:     return "rectangle.topthird.inset.filled"
            case .panel:     return "sidebar.right"
            case .planUsage: return "info.circle.fill"
            case .about:     return "questionmark.circle.fill"
            }
        }
    }

    @ObservedObject var store: SessionStore
    @State private var section: Section = .general

    var body: some View {
        HStack(spacing: 0) {
            sidebar
            Divider().overlay(Theme.hairline)
            detail
        }
        .frame(width: 720, height: 460)
        .background(Color(white: 0.13))
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 2) {
            ForEach(Section.allCases) { item in
                Button { section = item } label: {
                    HStack(spacing: 9) {
                        Image(systemName: item.symbol)
                            .font(Theme.ui(12))
                            .frame(width: 16)
                        Text(item.rawValue).font(Theme.ui(13))
                        Spacer()
                    }
                    .foregroundStyle(section == item ? .white : Theme.dim)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 7)
                    .background(
                        RoundedRectangle(cornerRadius: 6)
                            .fill(section == item ? Color.white.opacity(0.12) : .clear)
                    )
                }
                .buttonStyle(.plain)
            }
            Spacer()
        }
        .padding(10)
        .frame(width: 190)
    }

    private var detail: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text(section.rawValue).font(Theme.ui(19, .semibold)).foregroundStyle(.white)

                switch section {
                case .general:   GeneralPane()
                case .notch:     NotchPane()
                case .panel:     PanelPane(store: store)
                case .planUsage: PlanUsagePane(store: store)
                case .about:     AboutPane()
                }
                Spacer(minLength: 0)
            }
            .padding(22)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

private struct Card<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 0) { content }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 10).fill(.white.opacity(0.06)))
    }
}

private struct GeneralPane: View {
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled

    var body: some View {
        Card {
            Toggle("Launch at login", isOn: $launchAtLogin)
                .toggleStyle(.switch)
                .font(Theme.ui(13))
                .foregroundStyle(.white)
                .onChange(of: launchAtLogin) { _, on in
                    do {
                        on ? try SMAppService.mainApp.register()
                           : try SMAppService.mainApp.unregister()
                    } catch {
                        launchAtLogin = SMAppService.mainApp.status == .enabled
                    }
                }
        }
    }
}

private struct NotchPane: View {
    var body: some View {
        Card {
            VStack(alignment: .leading, spacing: 8) {
                ForEach(NSScreen.screens.indices, id: \.self) { index in
                    let screen = NSScreen.screens[index]
                    HStack(spacing: 9) {
                        Image(systemName: screen.notchSize == nil ? "display" : "laptopcomputer")
                            .foregroundStyle(Theme.dim)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(screen.localizedName)
                                .font(Theme.ui(13))
                                .foregroundStyle(.white)
                            Text(screen.notchSize == nil ? "No notch" : "Notch · Main")
                                .font(Theme.ui(11))
                                .foregroundStyle(Theme.dim)
                        }
                        Spacer()
                    }
                }
            }
        }
    }
}

private struct PanelPane: View {
    @ObservedObject var store: SessionStore

    var body: some View {
        Card {
            Toggle("Show plan meters", isOn: $store.showMeters)
                .toggleStyle(.switch)
                .font(Theme.ui(13))
                .foregroundStyle(.white)
        }
    }
}

private struct PlanUsagePane: View {
    @ObservedObject var store: SessionStore

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Limits are read from Claude Code itself, not estimated. They arrive through the status line, which only terminal sessions render — the desktop app does not. Open a terminal session to refresh them.")
                .font(Theme.ui(12))
                .foregroundStyle(Theme.dim)
                .fixedSize(horizontal: false, vertical: true)

            Card {
                VStack(alignment: .leading, spacing: 8) {
                    if let observed = store.usageObservedAt {
                        Row(label: "Last reading", value: observed.formatted(date: .omitted, time: .shortened))
                        Row(label: "Status", value: store.usageIsStale ? "stale" : "current")
                    } else {
                        Row(label: "Status", value: "no reading yet")
                    }
                    ForEach(store.usage) { window in
                        Row(label: window.id, value: "\(window.percentLabel) · resets \(window.resetLabel)")
                    }
                }
            }
        }
    }
}

private struct Row: View {
    let label: String
    let value: String

    var body: some View {
        HStack {
            Text(label).font(Theme.ui(12)).foregroundStyle(Theme.dim)
            Spacer()
            Text(value).font(Theme.mono(11)).foregroundStyle(.white)
        }
    }
}


private struct AboutPane: View {
    var body: some View {
        Card {
            VStack(alignment: .leading, spacing: 7) {
                Text("CrazyNotch (local build)").font(Theme.ui(14, .semibold)).foregroundStyle(.white)
                Text("Reads Claude Code hooks on 127.0.0.1:\(AppDelegate.defaultPort). Nothing leaves this Mac.")
                    .font(Theme.ui(12))
                    .foregroundStyle(Theme.dim)
                    .fixedSize(horizontal: false, vertical: true)
                Button("Quit CrazyNotch") { NSApp.terminate(nil) }
                    .buttonStyle(.plain)
                    .font(Theme.ui(12))
                    .foregroundStyle(Theme.alert)
                    .padding(.top, 4)
            }
        }
    }
}
