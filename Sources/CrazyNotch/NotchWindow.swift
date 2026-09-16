import AppKit
import SwiftUI
import Combine

extension NSScreen {
    static var notched: NSScreen? {
        NSScreen.screens.first { $0.safeAreaInsets.top > 0 } ?? NSScreen.main
    }

    /// Derived from the gap between the two menu-bar areas the system exposes,
    /// because the notch cutout itself has no public geometry.
    var notchSize: CGSize? {
        guard safeAreaInsets.top > 0,
              let left = auxiliaryTopLeftArea,
              let right = auxiliaryTopRightArea
        else { return nil }
        return CGSize(width: right.minX - left.maxX, height: safeAreaInsets.top)
    }
}

@MainActor
final class NotchWindow: NSObject {
    static let panelWidth: CGFloat = 720

    private let panel: NSPanel
    private let store: SessionStore
    private var bag = Set<AnyCancellable>()
    private var hoverTimer: Timer?
    private var detailPanel: NSPanel?
    private var collapseWork: DispatchWorkItem?
    private var collapseResize: DispatchWorkItem?

    init(store: SessionStore) {
        self.store = store
        panel = KeyablePanel(
            contentRect: .zero,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        super.init()

        panel.isFloatingPanel = true
        panel.level = .screenSaver
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.isMovable = false
        panel.hidesOnDeactivate = false
        panel.acceptsMouseMovedEvents = true
        panel.becomesKeyOnlyIfNeeded = true
        panel.contentView = NSHostingView(rootView: NotchView().environmentObject(store))

        store.$expanded
            .removeDuplicates()
            .sink { [weak self] expanded in
                guard let self else { return }
                if !expanded { self.hideDetail() }
                self.layout(expanded: expanded)
            }
            .store(in: &bag)

        store.$hoveredID
            .removeDuplicates()
            .sink { [weak self] id in
                DispatchQueue.main.async { self?.showDetail(for: id) }
            }
            .store(in: &bag)

        store.$liveUsage
            .sink { [weak self] _ in
                guard let self else { return }
                DispatchQueue.main.async { self.layout(expanded: self.store.expanded) }
            }
            .store(in: &bag)

        store.$sessions
            .sink { [weak self] _ in
                guard let self else { return }
                DispatchQueue.main.async { self.layout(expanded: self.store.expanded) }
            }
            .store(in: &bag)

        NotificationCenter.default
            .publisher(for: NSApplication.didChangeScreenParametersNotification)
            .sink { [weak self] _ in self?.layout(expanded: store.expanded) }
            .store(in: &bag)

        layout(expanded: false)
        panel.orderFrontRegardless()
        startHoverTracking()
    }

    /// A global .mouseMoved monitor needs Accessibility permission, which this
    /// app never asks for, so the cursor is polled instead — mouseLocation is a
    /// plain query and needs no entitlement.
    private func startHoverTracking() {
        hoverTimer = Timer.scheduledTimer(withTimeInterval: 0.06, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.evaluateHover() }
        }
    }

    /// Anchored to the notch rather than the window, because the collapsed
    /// window can be too small to be a comfortable target.
    private var hoverZone: NSRect {
        guard let screen = NSScreen.notched else { return .zero }
        let notch = notchSize
        if store.expanded { return panel.frame }
        return NSRect(
            x: screen.frame.midX - notch.width / 2 - 80,
            y: screen.frame.maxY - max(notch.height, 34),
            width: notch.width + 160,
            height: max(notch.height, 34)
        )
    }

    private func hideDetail() {
        detailPanel?.orderOut(nil)
        detailPanel?.setFrame(.zero, display: false)
    }

    private func evaluateHover() {
        let mouse = NSEvent.mouseLocation
        let inside = hoverZone.contains(mouse)

        if store.expanded, panel.frame.contains(mouse) {
            let localX = mouse.x - panel.frame.minX
            let localY = panel.frame.maxY - mouse.y
            store.hoveredButton = HeaderButton.hit(x: localX, y: localY, width: panel.frame.width)
            let row = store.rowLayout.first { localY >= $0.top && localY < $0.top + $0.height }
            store.hover(row?.id)
        } else {
            store.hover(nil)
            store.hoveredButton = nil
        }

        if inside {
            collapseWork?.cancel()
            collapseWork = nil
            if !store.expanded { store.expanded = true }
        } else if store.expanded, collapseWork == nil {
            let work = DispatchWorkItem { [weak self] in
                guard let self else { return }
                self.collapseWork = nil
                if !self.hoverZone.contains(NSEvent.mouseLocation) { self.store.expanded = false }
            }
            collapseWork = work
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4, execute: work)
        }
    }

    var notchSize: CGSize {
        NSScreen.notched?.notchSize ?? CGSize(width: 190, height: 32)
    }

    /// Hugs the label rather than padding to a fixed width, which otherwise
    /// leaves a black slab far wider than the text it carries.
    @MainActor
    /// Two glyphs hugging the notch: the agent that wants attention on one
    /// side, what it wants on the other. No label, so the strip stays short.
    static func peekWidth(store: SessionStore) -> CGFloat {
        let notch = NSScreen.notched?.notchSize ?? CGSize(width: 179, height: 32)
        return notch.width + 56
    }

    static func measure(_ text: String, size: CGFloat, weight: NSFont.Weight) -> CGFloat {
        let font = NSFont.systemFont(ofSize: size, weight: weight)
        return ceil((text as NSString).size(withAttributes: [.font: font]).width)
    }

    /// A separate panel rather than an overlay, so the card can sit outside the
    /// main panel's bounds without widening the window over the menu bar.
    private func showDetail(for id: String?) {
        guard let id, store.expanded, let session = store.session(id),
              let row = store.rowLayout.first(where: { $0.id == id })
        else {
            hideDetail()
            return
        }

        let host = NSHostingView(rootView: DetailCard(session: session))
        host.frame.size = host.fittingSize

        let card = detailPanel ?? {
            let p = NSPanel(
                contentRect: .zero,
                styleMask: [.borderless, .nonactivatingPanel],
                backing: .buffered,
                defer: false
            )
            p.isFloatingPanel = true
            p.level = .screenSaver
            p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
            p.isOpaque = false
            p.backgroundColor = .clear
            p.hasShadow = true
            p.ignoresMouseEvents = true
            detailPanel = p
            return p
        }()

        card.contentView = host
        let top = panel.frame.maxY - row.top
        card.setFrame(
            NSRect(
                x: panel.frame.minX - host.fittingSize.width - 10,
                y: top - host.fittingSize.height,
                width: host.fittingSize.width,
                height: host.fittingSize.height
            ),
            display: true
        )
        card.orderFrontRegardless()
    }

    private func layout(expanded: Bool) {
        guard let screen = NSScreen.notched else { return }
        let notch = notchSize
        let size = expanded
            ? CGSize(width: Self.panelWidth, height: store.panelHeight)
            : CGSize(width: Self.peekWidth(store: store), height: notch.height + Theme.peekDrop)

        let frame = NSRect(
            x: screen.frame.midX - size.width / 2,
            y: screen.frame.maxY - size.height,
            width: size.width,
            height: size.height
        )

        // Grow the window first and shrink it last, so the mask always animates
        // inside a frame big enough to hold it. Animating the frame itself
        // relayouts the whole view tree each step and stutters.
        collapseResize?.cancel()
        collapseResize = nil

        if panel.frame == .zero || expanded || size.width >= panel.frame.width {
            panel.setFrame(frame, display: true)
            Diagnostics.panelFrame = frame
            return
        }

        let shrink = DispatchWorkItem { [weak self] in
            guard let self, !self.store.expanded else { return }
            self.panel.setFrame(frame, display: true)
            Diagnostics.panelFrame = frame
        }
        collapseResize = shrink
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.44, execute: shrink)
    }
}


/// A borderless panel refuses key status by default, which silently swallows
/// clicks on any control inside it.
private final class KeyablePanel: NSPanel {
    override var canBecomeKey: Bool { true }
}


@MainActor
enum Diagnostics {
    static var panelFrame: NSRect?
}
