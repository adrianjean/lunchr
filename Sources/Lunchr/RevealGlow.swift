import AppKit
import LunchrCore

/// Two streaks of accent colour that start at the top centre, race down both sides and meet
/// at the bottom. Core Animation only, so nothing runs on the main thread while it plays.
final class RevealGlowView: NSView {
    private struct Streak {
        let layer: CAShapeLayer
        let clockwise: Bool
        let isCore: Bool
    }

    private let stage = CALayer()
    private var streaks: [Streak] = []
    private var radius = 0.0

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.addSublayer(stage)
        stage.masksToBounds = true
        stage.opacity = 0
        for clockwise in [true, false] {
            for isCore in [false, true] {
                let line = CAShapeLayer()
                line.fillColor = nil
                line.lineCap = .round
                stage.addSublayer(line)
                streaks.append(Streak(layer: line, clockwise: clockwise, isCore: isCore))
            }
        }
    }

    required init?(coder: NSCoder) { fatalError() }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    /// Keeps the path on the border when the window changes height mid-flight.
    override func layout() {
        super.layout()
        updatePaths()
    }

    func play(_ theme: Theme) {
        radius = theme.cornerRadius
        let glow = theme.glow
        for streak in streaks {
            let line = streak.layer
            let isCore = streak.isCore
            // White on a light panel needs more body to show than colour on a dark one.
            let isWhite = glow.luminance > 0.95
            line.lineWidth = isCore ? (isWhite ? 3 : 2) : (isWhite ? 10 : 7)
            line.strokeColor = (isCore
                ? glow.mixed(withWhite: 0.45).nsColor
                : glow.nsColor.withAlphaComponent(isWhite ? 0.4 : 0.35)).cgColor
            line.shadowColor = glow.nsColor.cgColor
            line.shadowOpacity = isWhite ? 1 : 0.9
            line.shadowRadius = isCore ? 5 : (isWhite ? 18 : 12)
            line.shadowOffset = .zero
            line.strokeStart = 1
            line.strokeEnd = 1

            let head = animation("strokeEnd", from: 0, to: 1, start: 0, duration: 0.5)
            let tail = animation("strokeStart", from: 0, to: 1, start: 0.13, duration: 0.5)
            line.add(head, forKey: "head")
            line.add(tail, forKey: "tail")
        }
        updatePaths()

        let fade = CAKeyframeAnimation(keyPath: "opacity")
        fade.values = [0, 1, 1, 0]
        fade.keyTimes = [0, 0.12, 0.6, 1]
        fade.duration = 0.63
        stage.add(fade, forKey: "fade")
    }

    func stop() {
        stage.removeAllAnimations()
        streaks.forEach { $0.layer.removeAllAnimations() }
    }

    private func animation(
        _ key: String, from: Double, to: Double, start: Double, duration: Double
    ) -> CABasicAnimation {
        let a = CABasicAnimation(keyPath: key)
        a.fromValue = from
        a.toValue = to
        a.beginTime = CACurrentMediaTime() + start
        a.duration = duration
        a.fillMode = .backwards
        a.timingFunction = CAMediaTimingFunction(controlPoints: 0.3, 0.1, 0.15, 1)
        return a
    }

    private func updatePaths() {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        stage.frame = bounds
        stage.cornerRadius = radius
        for streak in streaks {
            streak.layer.frame = bounds
            streak.layer.path = halfBorder(mirrored: streak.clockwise)
        }
        CATransaction.commit()
    }

    /// Top centre → down one side → bottom centre. Y points up.
    private func halfBorder(mirrored: Bool) -> CGPath {
        let box = bounds.insetBy(dx: 1, dy: 1)
        let r = min(radius, box.width / 2, box.height / 2)
        let path = CGMutablePath()
        path.move(to: CGPoint(x: box.midX, y: box.maxY))
        path.addArc(
            tangent1End: CGPoint(x: box.minX, y: box.maxY),
            tangent2End: CGPoint(x: box.minX, y: box.midY), radius: r)
        path.addArc(
            tangent1End: CGPoint(x: box.minX, y: box.minY),
            tangent2End: CGPoint(x: box.midX, y: box.minY), radius: r)
        path.addLine(to: CGPoint(x: box.midX, y: box.minY))
        guard mirrored else { return path }
        var flip = CGAffineTransform(translationX: box.midX * 2, y: 0).scaledBy(x: -1, y: 1)
        return path.copy(using: &flip) ?? path
    }
}
