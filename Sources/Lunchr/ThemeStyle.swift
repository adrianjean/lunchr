import AppKit
import SwiftUI
import LunchrCore

extension RGBA {
    var color: Color { Color(.sRGB, red: r, green: g, blue: b, opacity: a) }
    var nsColor: NSColor { NSColor(srgbRed: r, green: g, blue: b, alpha: a) }
}

extension Theme {
    func nsFont(_ size: Double, _ weight: NSFont.Weight = .regular) -> NSFont {
        let base = NSFont.systemFont(ofSize: size, weight: weight)
        func design(_ d: NSFontDescriptor.SystemDesign) -> NSFont {
            base.fontDescriptor.withDesign(d).flatMap { NSFont(descriptor: $0, size: size) } ?? base
        }
        switch font {
        case "system", "": return base
        case "rounded": return design(.rounded)
        case "mono": return design(.monospaced)
        case "serif": return design(.serif)
        default:
            return NSFontManager.shared.font(
                withFamily: font, traits: weight >= .semibold ? .boldFontMask : [], weight: 5, size: size) ?? base
        }
    }

    func font(_ size: Double, _ weight: NSFont.Weight = .regular) -> Font { Font(nsFont(size, weight)) }
}

extension BlurStyle {
    var label: String {
        switch self {
        case .none: "None"
        case .soft: "Soft"
        case .frosted: "Frosted"
        case .heavy: "Heavy"
        case .glass: "Glass"
        }
    }
}

/// The blurred layer behind the launcher, clipped to the theme's corner radius.
final class BackdropView: NSView {
    private var applied: (blur: BlurStyle, radius: Double, dark: Bool)?

    func apply(_ theme: Theme) {
        let next = (blur: theme.blur, radius: theme.cornerRadius, dark: theme.dark)
        if let applied, applied == next { return }
        applied = next

        subviews.forEach { $0.removeFromSuperview() }
        appearance = NSAppearance(named: theme.dark ? .darkAqua : .aqua)
        guard let view = makeEffect(theme) else { return }
        view.frame = bounds
        view.autoresizingMask = [.width, .height]
        addSubview(view)
    }

    private func makeEffect(_ theme: Theme) -> NSView? {
        switch theme.blur {
        case .none: return nil
        case .glass:
            if #available(macOS 26.0, *) {
                let glass = NSGlassEffectView()
                glass.style = .clear
                glass.cornerRadius = theme.cornerRadius
                return glass
            }
            return effect(.hudWindow, theme)
        case .soft: return effect(.fullScreenUI, theme)
        case .frosted: return effect(.hudWindow, theme)
        case .heavy: return effect(.underWindowBackground, theme)
        }
    }

    private func effect(_ material: NSVisualEffectView.Material, _ theme: Theme) -> NSView {
        let view = NSVisualEffectView()
        view.material = material
        view.blendingMode = .behindWindow
        view.state = .active
        view.maskImage = Self.mask(theme.cornerRadius)
        return view
    }

    /// Behind-window blur ignores layer corners; it needs a stretchable mask.
    private static func mask(_ radius: Double) -> NSImage {
        let edge = radius * 2 + 1
        let image = NSImage(size: NSSize(width: edge, height: edge), flipped: false) { rect in
            NSColor.black.setFill()
            NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius).fill()
            return true
        }
        image.capInsets = NSEdgeInsets(top: radius, left: radius, bottom: radius, right: radius)
        image.resizingMode = .stretch
        return image
    }
}
