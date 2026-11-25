import AppKit

/// Covers one screen with a see-through colour. Clicks go through it.
@MainActor
final class ScreenDimmer {
    struct Look: Equatable {
        var frame: NSRect
        var color: NSColor
        /// 0...1
        var amount: Double
        var level: NSWindow.Level
        /// Window number to sit just under, or 0 for the front of its level.
        var below = 0
    }

    private final class DimWindow: NSPanel {
        override var canBecomeKey: Bool { false }
        // Otherwise macOS may push it out from under the menu bar.
        override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect { frameRect }
    }

    private let window = DimWindow(
        contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: true)
    private var look: Look?

    init() {
        window.isOpaque = false
        window.hasShadow = false
        window.ignoresMouseEvents = true
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient, .ignoresCycle]
        window.hidesOnDeactivate = false
        window.animationBehavior = .none
        window.isReleasedWhenClosed = false
        window.alphaValue = 0
    }

    /// nil takes it away. Fades in and out; changes while it's up are instant.
    func show(_ new: Look?, fade: Bool) {
        guard new != look else { return }
        let old = look
        look = new
        if let new {
            window.level = new.level
            window.backgroundColor = new.color
            if window.frame != new.frame { window.setFrame(new.frame, display: true) }
            if old?.level != new.level || old?.below != new.below {
                if new.below > 0 {
                    window.order(.below, relativeTo: new.below)
                } else {
                    window.orderFrontRegardless()
                }
            }
        }
        NSAnimationContext.runAnimationGroup { context in
            context.duration = fade && (old == nil || new == nil) ? 0.15 : 0
            window.animator().alphaValue = new?.amount ?? 0
        } completionHandler: { [weak self] in
            MainActor.assumeIsolated {
                guard let self, self.look == nil else { return }
                self.window.orderOut(nil)
            }
        }
    }
}
