import AppKit
import Combine
import SwiftUI
import LunchrCore

final class LauncherPanel: NSPanel {
    static let fieldID = NSUserInterfaceItemIdentifier("lunchr.query")
    var onKeyEquivalent: ((NSEvent) -> Bool)?

    override var canBecomeKey: Bool { true }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if onKeyEquivalent?(event) == true { return true }
        return super.performKeyEquivalent(with: event)
    }
}

@MainActor
final class LauncherController: NSObject, NSWindowDelegate {
    let model: LauncherModel
    private let state: AppState
    private let panel: LauncherPanel
    private let backdrop = BackdropView()
    private let glow = RevealGlowView(frame: .zero)
    /// Everything visible, scaled as one during the reveal.
    private let stage = NSView()
    private var host: NSView?
    private var subscriptions: Set<AnyCancellable> = []
    /// Top-centre point the window hangs from while it's open.
    private var anchor = NSPoint.zero
    private var previewing = false

    init(state: AppState) {
        self.state = state
        model = LauncherModel(state: state)
        panel = LauncherPanel(
            contentRect: NSRect(x: 0, y: 0, width: 620, height: 60),
            styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        super.init()

        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.level = .modalPanel
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient, .ignoresCycle]
        panel.hidesOnDeactivate = false
        panel.animationBehavior = .none
        panel.isReleasedWhenClosed = false
        panel.title = "Lunchr"
        panel.delegate = self
        panel.onKeyEquivalent = { [weak self] in self?.handleKey($0) ?? false }

        let content = NSView(frame: panel.contentLayoutRect)
        let host = NSHostingView(rootView: LauncherView(model: model, state: state))
        host.sizingOptions = []
        host.wantsLayer = true
        self.host = host
        content.wantsLayer = true
        stage.wantsLayer = true
        stage.frame = content.bounds
        stage.autoresizingMask = [.width, .height]
        content.addSubview(stage)
        for view in [backdrop, host, glow] as [NSView] {
            view.frame = stage.bounds
            view.autoresizingMask = [.width, .height]
            stage.addSubview(view)
        }
        panel.contentView = content

        state.$config.map(\.reveal).removeDuplicates().dropFirst()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in if self?.previewing == true { self?.reveal {} } }
            .store(in: &subscriptions)

        model.onClose = { [weak self] in self?.hide() }
        Publishers.Merge(
            model.objectWillChange.map { _ in () }, state.objectWillChange.map { _ in () })
            .receive(on: DispatchQueue.main)
            .sink { [weak self] in self?.layout() }
            .store(in: &subscriptions)
        layout()
    }

    #if DEBUG
    var debugWindow: NSWindow { panel }
    #endif

    func toggle() {
        if panel.isVisible, panel.isKeyWindow { hide() } else { show() }
    }

    func show(query: String = "") {
        endPreview()
        model.reset()
        model.query = query
        place()
        if panel.isVisible {
            panel.makeKeyAndOrderFront(nil)
            focusField()
        } else {
            reveal {
                panel.makeKeyAndOrderFront(nil)
                focusField()
            }
        }
    }

    /// Instant, so the app being opened is never kept waiting.
    func hide() {
        previewing = false
        panel.orderOut(nil)
        endReveal()
        // Next time opens on the right list instead of swapping it during the reveal.
        model.reset()
    }

    // MARK: Reveal

    /// Decoration only: `present` shows the window and focuses the field straight away.
    /// The window's own alpha stays at 1, because macOS draws no blur while it's fading.
    private func reveal(_ present: () -> Void) {
        endReveal()
        let style = state.config.reveal
        guard style != .off else { return present() }

        let fade = CABasicAnimation(keyPath: "opacity")
        fade.fromValue = 0
        fade.toValue = 1
        fade.duration = 0.1
        host?.layer?.add(fade, forKey: "reveal")
        guard !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion else { return present() }

        // No overshoot: past 100% the window would clip its own edges.
        if let layer = stage.layer {
            let spring = CASpringAnimation(perceptualDuration: 0.28, bounce: 0)
            spring.keyPath = "transform"
            spring.fromValue = scale(0.9, of: layer)
            spring.toValue = CATransform3DIdentity
            spring.duration = spring.settlingDuration
            layer.add(spring, forKey: "reveal")
        }
        if style == .glow { glow.play(state.theme) }

        model.beginReveal()
        panel.contentView?.layoutSubtreeIfNeeded()
        panel.displayIfNeeded()
        present()
        model.endReveal()
    }

    private func endReveal() {
        stage.layer?.removeAnimation(forKey: "reveal")
        host?.layer?.removeAnimation(forKey: "reveal")
        glow.stop()
        model.endReveal()
    }

    /// Scales around the top centre, whatever anchor point AppKit gave the layer.
    private func scale(_ factor: CGFloat, of layer: CALayer) -> CATransform3D {
        let size = layer.bounds.size
        let dx = size.width * (0.5 - layer.anchorPoint.x)
        let dy = size.height * (1 - layer.anchorPoint.y)
        var t = CATransform3DMakeTranslation(dx, dy, 0)
        t = CATransform3DScale(t, factor, factor, 1)
        return CATransform3DTranslate(t, -dx, -dy, 0)
    }

    /// Keeps the launcher on screen next to Settings while the look is being changed.
    func preview(_ on: Bool, query: String = "a") {
        guard on != previewing else { return }
        if on {
            model.reset()
            model.query = query
            place()
            previewing = true
            reveal { panel.orderFrontRegardless() }
        } else {
            hide()
        }
    }

    private func endPreview() { previewing = false }

    func windowDidResignKey(_ notification: Notification) {
        if !previewing { hide() }
    }

    private func focusField() {
        guard let field = find(LauncherPanel.fieldID, in: panel.contentView) as? NSTextField else { return }
        panel.makeFirstResponder(field)
        (field.currentEditor() as? NSTextView)?.insertionPointColor = state.theme.accent.nsColor
        field.currentEditor()?.selectedRange = NSRange(location: field.stringValue.utf16.count, length: 0)
    }

    private func find(_ id: NSUserInterfaceItemIdentifier, in view: NSView?) -> NSView? {
        guard let view else { return nil }
        if view.identifier == id { return view }
        for sub in view.subviews { if let hit = find(id, in: sub) { return hit } }
        return nil
    }

    private func place() {
        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { NSMouseInRect(mouse, $0.frame, false) } ?? NSScreen.main
        guard let area = screen?.visibleFrame else { return }
        anchor = NSPoint(x: area.midX, y: area.maxY - area.height * 0.22)
        layout()
    }

    private func layout() {
        let theme = state.theme
        backdrop.apply(theme)
        panel.appearance = NSAppearance(named: theme.dark ? .darkAqua : .aqua)
        let size = NSSize(width: theme.width, height: theme.height(rows: model.results.count))
        let frame = NSRect(
            x: (anchor.x - size.width / 2).rounded(), y: (anchor.y - size.height).rounded(),
            width: size.width, height: size.height)
        guard panel.frame != frame else { return }
        panel.setFrame(frame, display: true)
        panel.invalidateShadow()
    }

    private func handleKey(_ event: NSEvent) -> Bool {
        let flags = event.modifierFlags.intersection([.command, .option, .control, .shift])
        guard flags == .command else { return false }
        if event.keyCode == 36 || event.keyCode == 76 {
            model.open(pin: true)
            return true
        }
        // The app has no menu bar, so the usual editing shortcuts are routed by hand.
        switch event.charactersIgnoringModifiers {
        case ",": model.onOpenSettings?()
        case "h": model.hide()
        case "w": hide()
        case "a": NSApp.sendAction(#selector(NSText.selectAll(_:)), to: nil, from: nil)
        case "c": NSApp.sendAction(#selector(NSText.copy(_:)), to: nil, from: nil)
        case "x": NSApp.sendAction(#selector(NSText.cut(_:)), to: nil, from: nil)
        case "v": NSApp.sendAction(#selector(NSText.paste(_:)), to: nil, from: nil)
        default: return false
        }
        return true
    }
}
