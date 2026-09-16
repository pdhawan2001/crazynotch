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
            Image(systemName: "terminal")
                .font(.system(size: size))
                .foregroundStyle(tint)
                .frame(width: size, height: size)
        }
    }

}

