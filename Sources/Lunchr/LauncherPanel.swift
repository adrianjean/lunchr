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
    private let dimmer = ScreenDimmer()
    /// The screen the launcher opened on.
    private var screen: NSScreen?
    /// Everything visible, scaled as one during the reveal.
    private let stage = NSView()
    private var host: NSView?
    private var subscriptions: Set<AnyCancellable> = []
    /// Top-centre point the window hangs from while it's open.
    private var anchor = NSPoint.zero
    private var previewing = false
    private var previewWanted = false
    private weak var neighbour: NSWindow?

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

        // Replay when the reveal or the theme being edited changes.
        Publishers.Merge(
            state.$config.map(\.reveal).removeDuplicates().dropFirst().map { _ in () },
            state.$editingThemeID.removeDuplicates().dropFirst().map { _ in () })
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
        setPreviewing(false)
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
        updateDim()
    }

    /// Instant, so the app being opened is never kept waiting.
    func hide() {
        setPreviewing(false)
        panel.orderOut(nil)
        updateDim()
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

    // MARK: Preview

    /// Keeps the launcher on screen beside Settings while the look is being changed.
    func preview(_ on: Bool, beside window: NSWindow? = nil, query: String = "a") {
        previewWanted = on
        neighbour = window
        if on {
            startPreview(query: query)
        } else if previewing {
            hide()
        }
    }

    /// Settings lost or regained the screen.
    func suspendPreview() { if previewing { hide() } }
    func resumePreview() { if previewWanted { startPreview(query: "a") } }

    private func startPreview(query: String) {
        guard !previewing, !panel.isVisible else { return }
        model.reset()
        model.query = query
        if neighbour == nil { place() } else { moveNeighbourIfNeeded() }
        setPreviewing(true)
        layout()
        reveal { panel.orderFrontRegardless() }
        updateDim()
    }

    private func setPreviewing(_ on: Bool) {
        previewing = on
        panel.ignoresMouseEvents = on
        // Darkening covers the menu bar, so the launcher has to be above that.
        panel.level = on ? .floating : state.dim.amount > 0 ? Self.aboveDim : .modalPanel
    }

    // MARK: Darken the screen

    private static let dimLevel = NSWindow.Level(NSWindow.Level.statusBar.rawValue + 1)
    private static let aboveDim = NSWindow.Level(NSWindow.Level.statusBar.rawValue + 2)

    /// Open: covers everything else. In the preview: goes behind Settings, which has to stay readable.
    private func updateDim() {
        let target = previewing ? neighbour?.screen ?? screen : screen
        let dim = state.dim
        guard dim.amount > 0, panel.isVisible, let frame = target?.frame else {
            dimmer.show(nil, fade: state.config.reveal != .off)
            return
        }
        dimmer.show(
            ScreenDimmer.Look(
                frame: frame, color: dim.color.nsColor.withAlphaComponent(1),
                amount: dim.amount, level: previewing ? .normal : Self.dimLevel,
                below: previewing ? neighbour?.windowNumber ?? 0 : 0),
            fade: state.config.reveal != .off)
    }

    /// Where the launcher hangs beside Settings: right if it fits, else left, else as far right as it goes.
    private func previewAnchor() -> NSPoint? {
        guard let window = neighbour, let area = (window.screen ?? NSScreen.main)?.visibleFrame else { return nil }
        let width = state.theme.width
        var x = window.frame.maxX + Self.previewGap
        if x + width > area.maxX {
            let left = window.frame.minX - Self.previewGap - width
            x = left >= area.minX ? left : area.maxX - width
        }
        return NSPoint(x: x + width / 2, y: window.frame.maxY)
    }

    private func moveNeighbourIfNeeded() {
        guard let window = neighbour, let area = (window.screen ?? NSScreen.main)?.visibleFrame else { return }
        let needed = state.theme.width + Self.previewGap
        guard area.maxX - window.frame.maxX < needed, window.frame.minX - area.minX < needed else { return }
        window.setFrameOrigin(NSPoint(x: area.minX + Self.previewGap, y: window.frame.minY))
    }

    private static let previewGap = 20.0

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
        screen = NSScreen.screens.first { NSMouseInRect(mouse, $0.frame, false) } ?? NSScreen.main
        guard let area = screen?.visibleFrame else { return }
        anchor = NSPoint(x: area.midX, y: area.maxY - area.height * 0.22)
        layout()
    }

    func layout() {
        let theme = state.theme
        if previewing, let beside = previewAnchor() { anchor = beside }
        let reshaped = backdrop.apply(theme)
        panel.appearance = NSAppearance(named: theme.dark ? .darkAqua : .aqua)
        // Without a panel the shadow would follow the letters.
        panel.hasShadow = theme.blur != .none || theme.opacity >= 0.1
        let size = NSSize(width: theme.width, height: theme.height(rows: model.results.count))
        let frame = NSRect(
            x: (anchor.x - size.width / 2).rounded(), y: (anchor.y - size.height).rounded(),
            width: size.width, height: size.height)
        updateDim()
        guard reshaped || panel.frame != frame else { return }
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
