import AppKit

/// The app icon reduced to a solid tile with the fork cut out, its handle running off the bottom.
/// A template image: macOS draws it white on a dark menu bar and black on a light one.
enum MenuBarIcon {
    static func make() -> NSImage {
        let image = NSImage(size: NSSize(width: 18, height: 18), flipped: true) { _ in
            NSColor.black.setFill()
            NSBezierPath(
                roundedRect: NSRect(x: 1, y: 1, width: 16, height: 16), xRadius: 4.25, yRadius: 4.25).fill()
            NSGraphicsContext.current?.compositingOperation = .destinationOut
            fork.fill()
            return true
        }
        image.isTemplate = true
        image.accessibilityDescription = "Lunchr"
        return image
    }

    /// Edges sit on half points, so they're sharp on a 2x display.
    private static var fork: NSBezierPath {
        let p = NSBezierPath()
        func point(_ x: Double, _ y: Double) -> NSPoint { NSPoint(x: x, y: y) }
        let tine = 2.0, gap = 1.0, left = 5.0, top = 3.0, slot = 7.5
        p.move(to: point(left, top + 2))
        for i in 0..<3 {
            let x = left + Double(i) * (tine + gap)
            p.curve(
                to: point(x + tine / 2, top), controlPoint1: point(x + 0.1, top + 0.8),
                controlPoint2: point(x + 0.5, top))
            p.curve(
                to: point(x + tine, top + 2), controlPoint1: point(x + tine - 0.5, top),
                controlPoint2: point(x + tine - 0.1, top + 0.8))
            guard i < 2 else { break }
            p.line(to: point(x + tine, slot))
            p.curve(
                to: point(x + tine + gap, slot), controlPoint1: point(x + tine, slot + 0.65),
                controlPoint2: point(x + tine + gap, slot + 0.65))
            p.line(to: point(x + tine + gap, top + 2))
        }
        p.line(to: point(13, 8))
        p.curve(to: point(10, 12), controlPoint1: point(13, 10.4), controlPoint2: point(10, 10))
        p.curve(to: point(10.5, 18), controlPoint1: point(10, 14), controlPoint2: point(10.5, 15))
        p.line(to: point(7.5, 18))
        p.curve(to: point(8, 12), controlPoint1: point(7.5, 15), controlPoint2: point(8, 14))
        p.curve(to: point(5, 8), controlPoint1: point(8, 10), controlPoint2: point(5, 10.4))
        p.close()
        return p
    }
}
