import AppKit
import SwiftUI

@MainActor
enum WindowManager {
    private static var tokenHistory: NSWindow?
    private static var settings: NSWindow?

    static func openTokenHistory() {
        present(&tokenHistory, title: "Token history") { AnyView(TokenHistoryView()) }
    }

    static func openSettings(store: SessionStore) {
        present(&settings, title: "CrazyNotch Settings") { AnyView(SettingsWindowView(store: store)) }
    }

    private static func present(
        _ slot: inout NSWindow?,
        title: String,
        content: () -> AnyView
    ) {
        if let existing = slot {
            NSApp.activate(ignoringOtherApps: true)
            existing.makeKeyAndOrderFront(nil)
            return
        }

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 700, height: 500),
            styleMask: [.titled, .closable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.title = title
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.isReleasedWhenClosed = false
        window.appearance = NSAppearance(named: .darkAqua)
        window.contentView = NSHostingView(rootView: content())
        window.center()

        slot = window
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }
}
