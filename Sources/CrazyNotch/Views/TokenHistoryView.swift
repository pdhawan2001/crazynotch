import SwiftUI

struct TokenHistoryView: View {
    @State private var range = 30
    @State private var points: [UsageTracker.DailyPoint] = []

    private var total: Int { points.reduce(0) { $0 + $1.tokens } }
    private var activeDays: [UsageTracker.DailyPoint] { points.filter { $0.tokens > 0 } }
    private var busiest: UsageTracker.DailyPoint? { points.max { $0.tokens < $1.tokens } }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            summary
            chart
            legend
            Divider().overlay(Theme.hairline).padding(.horizontal, 24)
            footer
        }
        .frame(width: 660, height: 620)
        .background(Color(white: 0.11))
        .task(id: range) { points = await UsageTracker.shared.daily(days: range) }
    }

    private var header: some View {
        HStack(spacing: 10) {
            Image(systemName: "chart.bar.fill").foregroundStyle(Theme.dim)
            Text("Token history").font(Theme.ui(19, .semibold)).foregroundStyle(.white)
            Spacer()
            HStack(spacing: 4) {
                ForEach([("Today", 1), ("7 days", 7), ("30 days", 30)], id: \.1) { label, days in
                    Button { range = days } label: {
                        Text(label)
                            .font(Theme.ui(12, .medium))
                            .foregroundStyle(range == days ? .black : Theme.dim)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(Capsule().fill(range == days ? Color.white : .clear))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(3)
            .background(Capsule().fill(.white.opacity(0.08)))
        }
        .padding(.horizontal, 24)
        .padding(.top, 22)
        .padding(.bottom, 18)
    }

    private var summary: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 4) {
                Text(rangeLabel.uppercased())
                    .font(Theme.mono(10))
                    .foregroundStyle(Theme.dim)
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(Format.compact(total))
                        .font(Theme.ui(44, .medium))
                        .foregroundStyle(.white)
                    Text("tokens").font(Theme.ui(13)).foregroundStyle(Theme.dim)
                }
                Text(dateSpan).font(Theme.ui(12)).foregroundStyle(Theme.dim)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 4) {
                Text("EST. API VALUE").font(Theme.mono(10)).foregroundStyle(Theme.dim)
                Text("≈ $\(Int(Double(total) / 1_000_000 * UsageTracker.dollarsPerMillionTokens))")
                    .font(Theme.ui(30, .medium))
                    .foregroundStyle(.white)
                Text("At API rates").font(Theme.ui(11)).foregroundStyle(Theme.dim)
            }
        }
        .padding(.horizontal, 24)
        .padding(.bottom, 20)
    }

    private var chart: some View {
        let peak = max(points.map(\.tokens).max() ?? 1, 1)
        return VStack(spacing: 6) {
            HStack(alignment: .bottom, spacing: 3) {
                ForEach(points) { point in
                    RoundedRectangle(cornerRadius: 1)
                        .fill(point.tokens > 0 ? Color.white.opacity(0.88) : Color.white.opacity(0.10))
                        .frame(height: max(2, 210 * CGFloat(point.tokens) / CGFloat(peak)))
                }
            }
            .frame(height: 210, alignment: .bottom)

            HStack {
                Text(points.first.map { Format.day($0.day) } ?? "")
                Spacer()
                Text("Today")
            }
            .font(Theme.mono(10))
            .foregroundStyle(Theme.dim)
        }
        .padding(.horizontal, 24)
    }

    private var legend: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 7) {
                Circle().fill(.white).frame(width: 7, height: 7)
                Text("Claude Code").font(Theme.ui(12)).foregroundStyle(Theme.dim)
            }
            Text(Format.compact(total)).font(Theme.ui(15, .semibold)).foregroundStyle(.white)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 24)
        .padding(.vertical, 18)
    }

    private var footer: some View {
        HStack(alignment: .top, spacing: 0) {
            stat("PER ACTIVE DAY", Format.compact(activeDays.isEmpty ? 0 : total / activeDays.count), nil)
            stat("BUSIEST DAY", busiest.map { Format.compact($0.tokens) } ?? "—",
                 busiest.map { Format.day($0.day) })
            stat("ACTIVE DAYS", "\(activeDays.count)", "of \(points.count)")
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 18)
    }

    private func stat(_ label: String, _ value: String, _ suffix: String?) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(label).font(Theme.mono(10)).foregroundStyle(Theme.dim)
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(value).font(Theme.ui(22, .medium)).foregroundStyle(.white)
                if let suffix {
                    Text(suffix).font(Theme.ui(12)).foregroundStyle(Theme.dim)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var rangeLabel: String {
        range == 1 ? "Today" : "Last \(range) days"
    }

    private var dateSpan: String {
        guard let first = points.first?.day, let last = points.last?.day else { return "" }
        return range == 1 ? Format.day(last) : "\(Format.day(first)) – \(Format.day(last))"
    }
}

enum Format {
    static func compact(_ value: Int) -> String {
        let n = Double(value)
        switch n {
        case 1_000_000_000...: return String(format: "%.2fB", n / 1_000_000_000)
        case 1_000_000...:     return String(format: "%.1fM", n / 1_000_000)
        case 1_000...:         return String(format: "%.1fK", n / 1_000)
        default:               return "\(value)"
        }
    }

    static func day(_ date: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "d. MMM"
        return f.string(from: date)
    }
}
