#if DEBUG
import AppKit
import AVFoundation
import LunchrCore

/// LUNCHR_DEMO=folder: plays a script over a drawn desktop and saves screenshots and a video.
/// Nothing else on the Mac can be in the picture; see Grabber.
@MainActor
final class DemoRecorder {
    private let state: AppState
    private let launcher: LauncherController
    private let folder: URL
    private let openSettings: (Int) -> NSWindow?
    private var stage: NSWindow?
    private var keyMonitor: Any?

    private static let size = NSSize(width: 1280, height: 800)

    init(state: AppState, launcher: LauncherController, folder: String, openSettings: @escaping (Int) -> NSWindow?) {
        self.state = state
        self.launcher = launcher
        self.folder = URL(fileURLWithPath: folder)
        self.openSettings = openSettings
    }

    func run() async {
        // Real keys typed meanwhile stay out of the recording. Esc stops it.
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .keyUp]) { event in
            if event.keyCode == 53 { NSApp.terminate(nil) }
            return nil
        }
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        await pause(2)
        seedRecents()

        launcher.preview(true, query: "")
        let panel = launcher.debugWindow.frame
        launcher.hide()
        let region = NSRect(
            x: panel.midX - Self.size.width / 2, y: panel.maxY + 150 - Self.size.height,
            width: Self.size.width, height: Self.size.height)
        showStage(region)
        await pause(0.8)

        let grabber = Grabber(region: Self.flipped(region))
        for theme in ["graphite", "paper", "ember", "clear", "naked"] {
            use(theme)
            await pause(0.4)
            let movie = folder.appendingPathComponent("\(theme).mov")
            grabber.start(movie)
            await pause(0.5)
            await scene(theme, grabber)
            await pause(0.6)
            let frames = await grabber.stop()
            print(theme, "frames:", frames)
        }
        for theme in ["midnight", "meadow", "console"] {
            use(theme)
            await pause(0.4)
            launcher.show()
            await pause(0.9)
            await type("ma")
            await pause(0.5)
            grabber.still(folder.appendingPathComponent("\(theme).png"))
            launcher.hide()
            await pause(0.4)
        }
        await settingsShot(region)
        NSApp.terminate(nil)
    }

    private func scene(_ theme: String, _ grabber: Grabber) async {
        launcher.show()
        await pause(1.1)
        if theme == "naked" { grabber.still(folder.appendingPathComponent("naked-open.png")) }
        let word = ["graphite": "te", "paper": "ph", "ember": "st", "clear": "ca", "naked": "ma"][theme] ?? "ma"
        await type(word)
        await pause(0.6)
        grabber.still(folder.appendingPathComponent("\(theme).png"))
        for _ in 0..<2 {
            launcher.model.move(1)
            await pause(0.22)
        }
        await pause(0.5)
        launcher.hide()
    }

    private func settingsShot(_ region: NSRect) async {
        use("graphite")
        guard let window = openSettings(2) else { return }
        let wide = NSRect(x: region.midX - 720, y: region.midY - 400, width: 1440, height: 800)
        window.setFrameOrigin(NSPoint(x: wide.minX + 50, y: wide.midY - window.frame.height / 2))
        showStage(wide)
        stage?.level = Self.level(-3)
        window.level = Self.level(-2)
        window.makeKeyAndOrderFront(nil)
        launcher.layout()
        await pause(0.4)
        launcher.debugWindow.level = .modalPanel
        launcher.debugWindow.makeFirstResponder(nil)
        await pause(1.4)
        Grabber(region: Self.flipped(wide)).still(folder.appendingPathComponent("settings.png"))
    }

    /// Recents, so the list has something in it before typing.
    private func seedRecents() {
        for name in ["Maps", "Photos", "Music", "Calendar", "Notes", "Safari"] {
            guard let app = state.apps.first(where: { $0.name == name }) else { continue }
            state.updateMemory { $0.recordLaunch(app.path, query: Query("")) }
        }
    }

    private func use(_ theme: String) {
        state.config.lightTheme = theme
        state.config.darkTheme = theme
        // A darkened launcher is above the menu bar, so the stage goes up with it.
        stage?.level = state.dim.amount > 0 ? .statusBar : Self.level(-1)
        stage?.orderFrontRegardless()
    }

    /// Relative to the launcher's usual level.
    private static func level(_ step: Int) -> NSWindow.Level {
        NSWindow.Level(NSWindow.Level.modalPanel.rawValue + step)
    }

    /// Through the field editor, like real typing.
    private func type(_ text: String) async {
        for c in text {
            let editor = launcher.debugWindow.firstResponder as? NSTextView
            editor?.insertText(String(c), replacementRange: NSRange(location: NSNotFound, length: 0))
            await pause(0.17)
        }
    }

    private func pause(_ seconds: Double) async {
        try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
    }

    private func showStage(_ frame: NSRect) {
        stage?.orderOut(nil)
        let window = NSWindow(contentRect: frame, styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.level = Self.level(-1)
        window.contentView = DesktopView(frame: NSRect(origin: .zero, size: frame.size))
        window.orderFrontRegardless()
        stage = window
    }

    private static func flipped(_ rect: NSRect) -> CGRect {
        let top = (NSScreen.screens.first?.frame.maxY ?? 0) - rect.maxY
        return CGRect(x: rect.minX, y: top, width: rect.width, height: rect.height)
    }
}

/// A made-up desktop: the icon's overprinted circles and an empty dark and light window.
/// LUNCHR_BACKGROUND=file: that picture instead of the circles. LUNCHR_WINDOWS=0: no windows.
private final class DesktopView: NSView {
    private let env = ProcessInfo.processInfo.environment
    private lazy var picture = env["LUNCHR_BACKGROUND"].flatMap { NSImage(contentsOfFile: $0) }

    override var isFlipped: Bool { true }
    override var isOpaque: Bool { true }

    private func color(_ hex: String) -> NSColor { RGBA(hex: hex)!.nsColor }

    override func draw(_ dirtyRect: NSRect) {
        guard let context = NSGraphicsContext.current?.cgContext else { return }
        let w = bounds.width, h = bounds.height
        if let picture {
            let scale = max(w / picture.size.width, h / picture.size.height)
            let size = NSSize(width: picture.size.width * scale, height: picture.size.height * scale)
            NSColor.black.setFill()
            bounds.fill()
            NSGraphicsContext.current?.imageInterpolation = .high
            picture.draw(
                in: NSRect(x: (w - size.width) / 2, y: (h - size.height) / 2, width: size.width, height: size.height),
                from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: nil)
        } else {
            drawCircles(context, w, h)
        }
        guard env["LUNCHR_WINDOWS"] != "0" else { return }
        window(NSRect(x: w * 0.06, y: h * 0.11, width: 600, height: 470), dark: true, context)
        window(NSRect(x: w * 0.94 - 560, y: h * 0.34, width: 560, height: 460), dark: false, context)
    }

    private func drawCircles(_ context: CGContext, _ w: CGFloat, _ h: CGFloat) {
        color("#F3E7CC").setFill()
        bounds.fill()
        context.saveGState()
        context.setBlendMode(.multiply)
        for (hex, x, y, r) in [
            ("#F2B026", 0.02, 0.5, 0.6), ("#ED6149", 0.98, 0.5, 0.6),
            ("#57B3B8", 0.5, -0.08, 0.62), ("#B3BA4D", 0.5, 1.08, 0.62),
        ] {
            context.setFillColor(color(hex).cgColor)
            let radius = h * r
            context.fillEllipse(in: CGRect(x: w * x - radius, y: h * y - radius, width: radius * 2, height: radius * 2))
        }
        context.restoreGState()
    }

    private func window(_ frame: NSRect, dark: Bool, _ context: CGContext) {
        context.saveGState()
        context.setShadow(
            offset: CGSize(width: 0, height: -14), blur: 40, color: NSColor.black.withAlphaComponent(0.4).cgColor)
        color(dark ? "#23262E" : "#FCFBF8").setFill()
        NSBezierPath(roundedRect: frame, xRadius: 12, yRadius: 12).fill()
        context.restoreGState()

        for (i, hex) in ["#FF5F57", "#FEBC2E", "#28C840"].enumerated() {
            color(hex).setFill()
            NSBezierPath(ovalIn: NSRect(
                x: frame.minX + 16 + Double(i) * 20, y: frame.minY + 15, width: 12, height: 12)).fill()
        }
    }
}

/// Films one rectangle of the screen, from our frontmost window down. The stage is opaque and
/// directly beneath the launcher, so nothing else gets in: not notifications above, not windows below.
private final class Grabber: @unchecked Sendable {
    private typealias Capture = @convention(c) (CGRect, UInt32, UInt32, UInt32) -> Unmanaged<CGImage>?
    private let region: CGRect
    private let queue = DispatchQueue(label: "lunchr.demo", qos: .userInteractive)
    private let lock = NSLock()
    private var running = false
    private var frames = 0
    private var done: CheckedContinuation<Int, Never>?
    private let capture: Capture? = dlsym(
        UnsafeMutableRawPointer(bitPattern: -2), "CGWindowListCreateImage")
        .map { unsafeBitCast($0, to: Capture.self) }

    init(region: CGRect) { self.region = region }

    private func image() -> CGImage? {
        let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as? [[String: Any]] ?? []
        // Front to back, so the first that isn't the menu bar icon is our frontmost window.
        let front = list.first {
            let bounds = $0[kCGWindowBounds as String] as? [String: Double]
            return $0[kCGWindowOwnerPID as String] as? Int32 == getpid() && (bounds?["Width"] ?? 0) > 100
        }
        guard let number = front?[kCGWindowNumber as String] as? UInt32 else { return nil }
        let options: CGWindowListOption = [.optionOnScreenBelowWindow, .optionIncludingWindow]
        return capture?(region, options.rawValue, number, 0)?.takeRetainedValue()
    }

    /// Redrawn in sRGB: a capture carries the display's own colour profile, name and all.
    func still(_ url: URL) {
        guard let image = image(), let context = CGContext(
            data: nil, width: image.width, height: image.height, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)
        else { return print("no image for", url.lastPathComponent) }
        context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        guard let flat = context.makeImage() else { return }
        try? NSBitmapImageRep(cgImage: flat).representation(using: .png, properties: [:])?.write(to: url)
    }

    func start(_ url: URL) {
        running = true
        frames = 0
        queue.async { self.film(url) }
    }

    func stop() async -> Int {
        await withCheckedContinuation { continuation in
            lock.withLock {
                done = continuation
                running = false
            }
        }
    }

    private func film(_ url: URL) {
        try? FileManager.default.removeItem(at: url)
        guard let first = image(), let writer = try? AVAssetWriter(url: url, fileType: .mov) else {
            return print("can't film", url.lastPathComponent)
        }
        let width = first.width, height = first.height
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: [
            AVVideoCodecKey: AVVideoCodecType.proRes422, AVVideoWidthKey: width, AVVideoHeightKey: height,
        ])
        input.expectsMediaDataInRealTime = true
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input, sourcePixelBufferAttributes: [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
            kCVPixelBufferWidthKey as String: width, kCVPixelBufferHeightKey as String: height,
        ])
        writer.add(input)
        writer.startWriting()
        writer.startSession(atSourceTime: .zero)
        let start = CACurrentMediaTime()
        var last = -1.0
        while lock.withLock({ running }) {
            let now = CACurrentMediaTime() - start
            if now - last < 1.0 / 61 {
                usleep(800)
                continue
            }
            last = now
            guard input.isReadyForMoreMediaData, let image = image(), let pool = adaptor.pixelBufferPool
            else { continue }
            var buffer: CVPixelBuffer?
            CVPixelBufferPoolCreatePixelBuffer(nil, pool, &buffer)
            guard let buffer else { continue }
            CVPixelBufferLockBaseAddress(buffer, [])
            CGContext(
                data: CVPixelBufferGetBaseAddress(buffer), width: width, height: height, bitsPerComponent: 8,
                bytesPerRow: CVPixelBufferGetBytesPerRow(buffer), space: CGColorSpace(name: CGColorSpace.sRGB)!,
                bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue)?
                .draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
            CVPixelBufferUnlockBaseAddress(buffer, [])
            if adaptor.append(buffer, withPresentationTime: CMTime(seconds: now, preferredTimescale: 6000)) {
                frames += 1
            }
        }
        input.markAsFinished()
        writer.finishWriting {
            let continuation = self.lock.withLock { self.done }
            continuation?.resume(returning: self.frames)
        }
    }
}
#endif
