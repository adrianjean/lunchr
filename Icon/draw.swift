// Draws the icon artwork as a screen print: one mask per ink, multiplied onto paper.
//   swiftc -O Icon/draw.swift -o .build/draw-icon && .build/draw-icon Icon/Lunchr.icon/Assets/print.png
import AppKit

let size = 1024

// MARK: Noise

func hash(_ x: Int, _ y: Int, _ seed: Int) -> Double {
    var h = UInt64(bitPattern: Int64(x &* 374_761_393 &+ y &* 668_265_263 &+ seed &* 974_634_541))
    h = (h ^ (h >> 13)) &* 1_274_126_177
    h ^= h >> 16
    h = h &* 0x9E37_79B9_7F4A_7C15
    return Double(h >> 40) / Double(1 << 24)
}

func noise(_ x: Double, _ y: Double, _ seed: Int) -> Double {
    let xi = Int(x.rounded(.down)), yi = Int(y.rounded(.down))
    func ease(_ t: Double) -> Double { t * t * (3 - 2 * t) }
    let u = ease(x - Double(xi)), v = ease(y - Double(yi))
    let top = hash(xi, yi, seed) * (1 - u) + hash(xi + 1, yi, seed) * u
    let bottom = hash(xi, yi + 1, seed) * (1 - u) + hash(xi + 1, yi + 1, seed) * u
    return top * (1 - v) + bottom * v
}

/// Layered noise, about 0...1.
func cloud(_ x: Double, _ y: Double, _ scale: Double, _ seed: Int) -> Double {
    var total = 0.0, weight = 0.5, s = scale
    for i in 0..<4 {
        total += noise(x / s, y / s, seed + i) * weight
        weight /= 2
        s /= 2
    }
    return total / 0.9375
}

// MARK: Plates

/// Coverage 0...1 of a shape, y pointing down.
struct Plate {
    var values: [Float]

    init(_ draw: (CGContext) -> Void) {
        var bytes = [UInt8](repeating: 0, count: size * size)
        bytes.withUnsafeMutableBytes { buffer in
            let c = CGContext(
                data: buffer.baseAddress, width: size, height: size, bitsPerComponent: 8, bytesPerRow: size,
                space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.none.rawValue)!
            c.translateBy(x: 0, y: CGFloat(size))
            c.scaleBy(x: 1, y: -1)
            c.setFillColor(gray: 1, alpha: 1)
            draw(c)
        }
        values = bytes.map { Float($0) / 255 }
    }

    func at(_ x: Double, _ y: Double) -> Double {
        let xi = Int(x.rounded(.down)), yi = Int(y.rounded(.down))
        func v(_ x: Int, _ y: Int) -> Double {
            Double(values[min(max(y, 0), size - 1) * size + min(max(x, 0), size - 1)])
        }
        let u = x - Double(xi), w = y - Double(yi)
        return (v(xi, yi) * (1 - u) + v(xi + 1, yi) * u) * (1 - w)
            + (v(xi, yi + 1) * (1 - u) + v(xi + 1, yi + 1) * u) * w
    }
}

func circle(_ x: Double, _ y: Double, _ r: Double) -> Plate {
    Plate { $0.fillEllipse(in: CGRect(x: x - r, y: y - r, width: r * 2, height: r * 2)) }
}

func point(_ x: Double, _ y: Double) -> CGPoint { CGPoint(x: x, y: y) }

/// Three long tines, a soft bowl and a teardrop handle.
let fork: CGPath = {
    let p = CGMutablePath()
    let tine = 60.0, gap = 44.0, top = 96.0, slot = 400.0
    let left = 512 - (tine * 3 + gap * 2) / 2
    let right = 1024 - left
    p.move(to: point(left, top + 200))
    for i in 0..<3 {
        let x = left + Double(i) * (tine + gap)
        // Long taper to a soft point.
        p.addCurve(
            to: point(x + tine / 2 - 10, top + 10), control1: point(x, top + 110),
            control2: point(x + tine / 2 - 16, top + 50))
        p.addQuadCurve(to: point(x + tine / 2 + 10, top + 10), control: point(x + tine / 2, top - 12))
        p.addCurve(
            to: point(x + tine, top + 200), control1: point(x + tine / 2 + 16, top + 50),
            control2: point(x + tine, top + 110))
        guard i < 2 else { break }
        p.addLine(to: point(x + tine, slot))
        p.addCurve(
            to: point(x + tine + gap, slot), control1: point(x + tine, slot + 32),
            control2: point(x + tine + gap, slot + 32))
        p.addLine(to: point(x + tine + gap, top + 200))
    }
    p.addLine(to: point(right, 430))
    p.addCurve(to: point(531, 640), control1: point(right, 545), control2: point(531, 530))
    p.addCurve(to: point(574, 852), control1: point(531, 720), control2: point(574, 770))
    p.addCurve(to: point(512, 926), control1: point(574, 898), control2: point(546, 926))
    p.addCurve(to: point(450, 852), control1: point(478, 926), control2: point(450, 898))
    p.addCurve(to: point(493, 640), control1: point(450, 770), control2: point(493, 720))
    p.addCurve(to: point(left, 430), control1: point(493, 530), control2: point(left, 545))
    p.closeSubpath()
    return p
}()

func fill(_ path: CGPath) -> Plate {
    Plate {
        $0.addPath(path)
        $0.fillPath()
    }
}

let forkPlate = fill(fork)
let forkRight = Plate {
    $0.clip(to: CGRect(x: 512, y: 0, width: 512, height: 1024))
    $0.addPath(fork)
    $0.fillPath()
}
let diamond: CGPath = {
    let p = CGMutablePath()
    p.addLines(between: [point(512, 772), point(544, 840), point(512, 908), point(480, 840)])
    p.closeSubpath()
    return p
}()

struct Ink {
    let plate: Plate
    let color: (Double, Double, Double)
    var strength = 0.95
    /// How far this plate is off, in pixels.
    let shift: (Double, Double)
    /// Printed around the fork instead of over it.
    var leavesFork = true
    let seed: Int
}

let radius = 478.0
let inks: [Ink] = [
    Ink(plate: circle(0, 512, radius), color: (0.95, 0.69, 0.15), shift: (3, -2), seed: 10),
    Ink(plate: circle(512, 1024, radius), color: (0.70, 0.73, 0.30), shift: (-3, 3), seed: 20),
    Ink(plate: circle(1024, 512, radius), color: (0.93, 0.38, 0.29), shift: (-2, -4), seed: 30),
    Ink(plate: circle(512, 0, radius), color: (0.34, 0.70, 0.72), shift: (4, 2), seed: 40),
    Ink(plate: forkPlate, color: (0.15, 0.17, 0.22), strength: 0.93, shift: (20, 16), seed: 50),
    Ink(plate: forkRight, color: (0.96, 0.74, 0.36), strength: 0.8, shift: (4, 2), leavesFork: false, seed: 60),
    Ink(plate: fill(diamond), color: (0.91, 0.36, 0.25), shift: (-3, 2), leavesFork: false, seed: 70),
]

// MARK: Printing

var pixels = [UInt8](repeating: 255, count: size * size * 4)
pixels.withUnsafeMutableBufferPointer { out in
    for yi in 0..<size {
        for xi in 0..<size {
            let x = Double(xi), y = Double(yi)

            // Paper: warm, mottled, with a tooth and a few fibres.
            let tooth = hash(xi / 2, yi / 2, 1) * 0.6 + hash(xi, yi, 2) * 0.4 - 0.5
            let mottle = cloud(x, y, 160, 3) - 0.5
            let weave = cloud(x, y * 0.35, 14, 5) - 0.5
            let fibre = noise(x / 34, y / 3.2, 7) > 0.955 ? -0.05 : 0
            let light = 1 + tooth * 0.07 + mottle * 0.07 + weave * 0.07 + fibre
            var rgb = [0.955 * light, 0.905 * light, 0.80 * light]

            // Ragged ink edges.
            let ex = x + (cloud(x, y, 9, 90) - 0.5) * 3.2
            let ey = y + (cloud(x, y, 9, 95) - 0.5) * 3.2

            for ink in inks {
                var cover = ink.plate.at(ex - ink.shift.0, ey - ink.shift.1)
                if ink.leavesFork { cover *= 1 - forkPlate.at(ex, ey) }
                guard cover > 0 else { continue }
                // Uneven ink, and specks where the paper's tooth shows through.
                let blotch = cloud(x, y, 70, ink.seed) - 0.5
                let grain = cloud(x, y, 5, ink.seed + 5)
                let speck = hash(xi / 2, yi / 2, ink.seed + 9) > 0.965 && grain > 0.5 ? 0.45 : 0
                let dry = max(0, grain - 0.62) * 1.5
                cover *= max(0, min(1, ink.strength + blotch * 0.22 - dry - speck))
                let c = [ink.color.0, ink.color.1, ink.color.2]
                for i in 0..<3 { rgb[i] *= 1 - cover * (1 - c[i]) }
            }
            for i in 0..<3 { out[(yi * size + xi) * 4 + i] = UInt8(max(0, min(1, rgb[i])) * 255) }
        }
    }
}

let image = pixels.withUnsafeMutableBytes { buffer in
    CGContext(
        data: buffer.baseAddress, width: size, height: size, bitsPerComponent: 8, bytesPerRow: size * 4,
        space: CGColorSpace(name: CGColorSpace.sRGB)!,
        bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!.makeImage()!
}
let png = NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:])!
try png.write(to: URL(fileURLWithPath: CommandLine.arguments[1]))
