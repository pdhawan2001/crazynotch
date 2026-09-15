import AppKit
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    static let defaultPort: UInt16 = 8787

    private let store = SessionStore()
    private var notch: NotchWindow?
    private var server: HookServer?
    private var statusItem: NSStatusItem?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        notch = NotchWindow(store: store)

        let server = HookServer(store: store, port: Self.defaultPort)
        do {
            try server.start()
            self.server = server
        } catch {
            NSLog("CrazyNotch: port \(Self.defaultPort) unavailable — \(error.localizedDescription)")
        }

        installStatusItem()
    }

    /// A template image is recoloured by the system to match the menu bar, so
    /// it must carry shape in its alpha channel and no colour of its own.
    private static func menuBarIcon() -> NSImage? {
        guard let url = Bundle.main.url(forResource: "menubar-template", withExtension: "png"),
              let image = NSImage(contentsOf: url)
        else {
            return NSImage(systemSymbolName: "rectangle.topthird.inset.filled",
                           accessibilityDescription: "CrazyNotch")
        }
        image.isTemplate = true
        image.size = NSSize(width: 18, height: 18)
        return image
    }

    private func installStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.button?.image = Self.menuBarIcon()

        let menu = NSMenu()
        menu.addItem(withTitle: "Listening on 127.0.0.1:\(Self.defaultPort)", action: nil, keyEquivalent: "")
        menu.addItem(.separator())
        menu.addItem(withTitle: "Toggle Panel", action: #selector(togglePanel), keyEquivalent: "")
        menu.addItem(.separator())
        menu.addItem(withTitle: "Quit CrazyNotch", action: #selector(quit), keyEquivalent: "q")
        menu.items.forEach { $0.target = self }

        item.menu = menu
        statusItem = item
    }

    @objc private func togglePanel() { store.expanded.toggle() }
    @objc private func quit() { NSApp.terminate(nil) }
}
