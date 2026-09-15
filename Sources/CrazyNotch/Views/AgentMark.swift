import SwiftUI
import AppKit

/// Prefers the vendor's own mark when one was downloaded into the bundle, and
/// falls back to a drawn path so a missing or unusable asset still renders.
struct AgentMark: View {
    let agent: String
    var size: CGFloat = 13
    var tint: Color = .white

    private static var cache: [String: NSImage] = [:]

    private static func asset(_ agent: String) -> NSImage? {
        let file: String
        switch agent {
        case "Claude Code": file = "claude-mark"
        case "Cursor":      file = "cursor-mark"
        case "Kimi":        file = "kimi-mark"
        default:            return nil
        }
        if let hit = cache[file] { return hit }
        guard let url = Bundle.main.url(forResource: file, withExtension: "png", subdirectory: "logos")
                ?? Bundle.main.url(forResource: file, withExtension: "png"),
              let image = NSImage(contentsOf: url)
        else { return nil }
        image.isTemplate = true
        cache[file] = image
        return image
    }

    var body: some View {
        if let image = Self.asset(agent) {
            Image(nsImage: image)
                .resizable()
                .renderingMode(.template)
                .aspectRatio(contentMode: .fit)
                .frame(width: size, height: size)
                .foregroundStyle(tint)
        } else {
            drawn.frame(width: size, height: size)
        }
    }

    @ViewBuilder
    private var drawn: some View {
        switch agent {
        case "Codex": CodexMark().fill(tint)
        default:      OpenCodeMark().fill(tint)
        }
    }
}

struct CodexMark: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let c = CGPoint(x: rect.midX, y: rect.midY)
        let r = min(rect.width, rect.height) / 2
        for (index, ring) in [r, r * 0.72].enumerated() {
            var ringPath = Path()
            for i in 0..<6 {
                let angle = (CGFloat(i) / 6) * 2 * .pi - .pi / 2
                let p = CGPoint(x: c.x + cos(angle) * ring, y: c.y + sin(angle) * ring)
                i == 0 ? ringPath.move(to: p) : ringPath.addLine(to: p)
            }
            ringPath.closeSubpath()
            if index == 0 { path = ringPath } else { path = path.subtracting(ringPath) }
        }
        path.addEllipse(in: CGRect(x: c.x - r * 0.2, y: c.y - r * 0.2, width: r * 0.4, height: r * 0.4))
        return path
    }
}

struct OpenCodeMark: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path(roundedRect: rect, cornerRadius: rect.width * 0.22)
        let slot = CGRect(
            x: rect.minX + rect.width * 0.22,
            y: rect.midY - rect.height * 0.07,
            width: rect.width * 0.56,
            height: rect.height * 0.14
        )
        path = path.subtracting(Path(roundedRect: slot, cornerRadius: rect.height * 0.07))
        return path
    }
}
