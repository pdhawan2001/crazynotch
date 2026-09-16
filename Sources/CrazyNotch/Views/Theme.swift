import SwiftUI
import AppKit

enum Theme {
    static let headerHeight: CGFloat = 48
    static let peekDrop: CGFloat = 12
    static let panelCorner: CGFloat = 18

    static let ink = Color.white
    static let dim = Color.white.opacity(0.52)
    static let faint = Color.white.opacity(0.32)
    static let hairline = Color.white.opacity(0.08)
    static let track = Color.white.opacity(0.13)
    static let alert = Color(red: 0.97, green: 0.58, blue: 0.20)
    static let alertRail = Color(red: 0.85, green: 0.30, blue: 0.36)
    static let alertWash = Color(red: 0.32, green: 0.09, blue: 0.11)

    static func mono(_ size: CGFloat, _ weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight, design: .monospaced)
    }

    static func ui(_ size: CGFloat, _ weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight)
    }
}

struct VisualEffect: View {

    /// ImageRenderer cannot rasterise a live NSVisualEffectView and paints an
    /// error glyph instead, so offscreen renders get a flat stand-in.
    nonisolated(unsafe) static var isRendering = false

    var body: some View {
        if Self.isRendering {
            Color(white: 0.12)
        } else {
            Backing()
        }
    }
}

private struct Backing: NSViewRepresentable {

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = .hudWindow
        view.blendingMode = .behindWindow
        view.state = .active
        return view
    }

    func updateNSView(_ view: NSVisualEffectView, context: Context) {}
}
