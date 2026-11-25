import AppKit
import SwiftUI
import LunchrCore

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    private var state: AppState!
    private var launcher: LauncherController!
    private var statusItem: NSStatusItem!
    private var settings: NSWindow?

    func applicationDidFinishLaunching(_ notification: Notification) {
        state = AppState()
        launcher = LauncherController(state: state)
        launcher.model.onOpenSettings = { [weak self] in self?.openSettings() }
        HotKeyCenter.shared.onPress = { [weak self] in self?.launcher.toggle() }
        makeStatusItem()
        makeMainMenu()
        state.start()

        #if DEBUG
        debugSnapshot()
        #endif
    }

    #if DEBUG
    /// LUNCHR_SNAPSHOT=out.png [LUNCHR_PREVIEW=query | LUNCHR_SETTINGS=tab]: draw a window to a file
    /// and quit. Behind-window blur is drawn by the window server, so it isn't in the picture.
    private func debugSnapshot() {
        let env = ProcessInfo.processInfo.environment
        // LUNCHR_FRAMES=folder: reveal over a striped window and save what the screen shows.
        if let folder = env["LUNCHR_FRAMES"] {
            debugFrames(folder, query: env["LUNCHR_PREVIEW"] ?? "te")
            return
        }
        // LUNCHR_OPEN=query: show, time it, open the first result, report what's in front.
        if let query = env["LUNCHR_OPEN"] {
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [self] in
                MainActor.assumeIsolated {
                    let start = Date()
                    launcher.show(query: query)
                    launcher.debugWindow.displayIfNeeded()
                    print("show ms:", Int(Date().timeIntervalSince(start) * 1000),
                          "key:", launcher.debugWindow.isKeyWindow, "active:", NSApp.isActive,
                          "first:", launcher.model.results.first?.app.name ?? "-")
                    launcher.model.open()
                }
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 5) { [self] in
                MainActor.assumeIsolated {
                    print("front:", NSWorkspace.shared.frontmostApplication?.localizedName ?? "-",
                          "launcher visible:", launcher.debugWindow.isVisible)
                    quit()
                }
            }
            return
        }
        guard let out = env["LUNCHR_SNAPSHOT"] else { return }
        if let tab = env["LUNCHR_SETTINGS"].flatMap(Int.init) {
            showSettings(tab: tab)
            // LUNCHR_EDIT=1: change the open theme the way the editor does.
            if env["LUNCHR_EDIT"] != nil {
                DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [self] in
                    MainActor.assumeIsolated {
                        for width in [640.0, 660, 700] {
                            var theme = state.theme
                            theme.width = width
                            theme.accent = RGBA(hex: "#FF3366")!
                            state.updateTheme(theme)
                        }
                    }
                }
            }
        } else {
            launcher.preview(true, query: env["LUNCHR_PREVIEW"] ?? "")
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) { [self] in
            MainActor.assumeIsolated {
                let window = env["LUNCHR_SETTINGS"] == nil ? launcher.debugWindow : settings
                if let view = window?.contentView, let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) {
                    view.cacheDisplay(in: view.bounds, to: rep)
                    try? rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: out))
                }
                print("apps:", state.apps.count, "key:", window?.isKeyWindow ?? false,
                      "hotkey failed:", state.hotKeyFailed, "frame:", window?.frame ?? .zero)
                if let window = settings {
                    let panel = launcher.debugWindow
                    print("launcher visible:", panel.isVisible, "frame:", panel.frame,
                          "overlaps settings:", panel.isVisible && panel.frame.intersects(window.frame),
                          "active:", NSApp.isActive, "editing:", state.editingThemeID ?? "-")
                    window.close()
                    print("after close, launcher visible:", panel.isVisible, "editing:", state.editingThemeID ?? "-")
                }
                quit()
            }
        }
    }

    private func debugFrames(_ folder: String, query: String) {
        typealias Capture = @convention(c) (CGRect, UInt32, UInt32, UInt32) -> Unmanaged<CGImage>?
        guard let symbol = dlsym(UnsafeMutableRawPointer(bitPattern: -2), "CGWindowListCreateImage") else {
            print("no capture function")
            quit()
            return
        }
        let capture = unsafeBitCast(symbol, to: Capture.self)
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [self] in
            MainActor.assumeIsolated {
                launcher.preview(true, query: query)
                launcher.debugWindow.displayIfNeeded()
                let frame = launcher.debugWindow.frame.insetBy(dx: -40, dy: -40)
                launcher.hide()
                let stripes = NSWindow(
                    contentRect: frame, styleMask: [.borderless], backing: .buffered, defer: false)
                stripes.isReleasedWhenClosed = false
                stripes.level = .floating
                stripes.contentView = StripesView(frame: NSRect(origin: .zero, size: frame.size))
                stripes.orderFrontRegardless()
                debugStripes = stripes
                let top = (NSScreen.screens.first?.frame.maxY ?? 0) - frame.maxY
                let rect = CGRect(x: frame.minX, y: top, width: frame.width, height: frame.height)
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [self] in
                    MainActor.assumeIsolated {
                        let start = CACurrentMediaTime()
                        launcher.show(query: query)
                        print("show + reveal ms:", Int((CACurrentMediaTime() - start) * 1000),
                              "key:", launcher.debugWindow.isKeyWindow)
                        for ms in [30, 80, 150, 250, 400, 900] {
                            DispatchQueue.main.asyncAfter(deadline: .now() + Double(ms) / 1000) {
                                let at = Int((CACurrentMediaTime() - start) * 1000)
                                guard let image = capture(rect, 1, 0, 0)?.takeRetainedValue() else {
                                    print(ms, "no image")
                                    return
                                }
                                let rep = NSBitmapImageRep(cgImage: image)
                                try? rep.representation(using: .png, properties: [:])?
                                    .write(to: URL(fileURLWithPath: folder + "/f\(ms).png"))
                                print("frame at", at, image.width, image.height)
                            }
                        }
                    }
                }
            }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 5) { [self] in MainActor.assumeIsolated { quit() } }
    }

    private var debugStripes: NSWindow?

    private final class StripesView: NSView {
        override func draw(_ dirtyRect: NSRect) {
            let colors: [NSColor] = [.systemRed, .white, .systemBlue, .systemYellow, .black, .systemGreen]
            for i in 0...Int(bounds.width / 24) {
                colors[i % colors.count].setFill()
                NSRect(x: CGFloat(i) * 24, y: 0, width: 24, height: bounds.height).fill()
            }
        }
    }
    #endif

    /// Opening the app again (Finder, `open -a Lunchr`) shows the launcher.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows: Bool) -> Bool {
        launcher.show()
        return false
    }

    private func makeStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem.button?.image = MenuBarIcon.make()
        let menu = NSMenu()
        menu.addItem(item("Open Lunchr", #selector(showLauncher)))
        menu.addItem(item("Settings…", #selector(openSettings), ","))
        menu.addItem(item("Rescan Apps", #selector(rescan)))
        menu.addItem(.separator())
        menu.addItem(item("Quit Lunchr", #selector(quit), "q"))
        statusItem.menu = menu
    }

    /// Never visible, but Settings needs it for ⌘W, ⌘Q and text editing.
    private func makeMainMenu() {
        let appMenu = NSMenu()
        appMenu.addItem(item("Quit Lunchr", #selector(quit), "q"))
        let edit = NSMenu(title: "Edit")
        edit.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        edit.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        edit.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        edit.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        edit.addItem(withTitle: "Close", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
        let main = NSMenu()
        for menu in [appMenu, edit] {
            let holder = NSMenuItem()
            holder.submenu = menu
            main.addItem(holder)
        }
        NSApp.mainMenu = main
    }

    private func item(_ title: String, _ action: Selector, _ key: String = "") -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
        item.target = self
        return item
    }

    @objc private func showLauncher() { launcher.show() }
    @objc private func rescan() { state.rescan() }
    @objc private func quit() { NSApp.terminate(nil) }

    @objc private func openSettings() { showSettings(tab: 0) }

    private func showSettings(tab: Int) {
        launcher.hide()
        if settings == nil {
            let window = NSWindow(contentViewController: NSHostingController(
                rootView: SettingsView(state: state, tab: tab) { [weak self] on in
                    // Next turn: the window isn't on screen yet when the first tab appears.
                    DispatchQueue.main.async {
                        MainActor.assumeIsolated {
                            guard let self, let window = self.settings else { return }
                            self.launcher.preview(on, beside: window)
                        }
                    }
                }))
            window.title = "Lunchr Settings"
            window.styleMask = [.titled, .closable]
            window.isReleasedWhenClosed = false
            window.delegate = self
            window.center()
            settings = window
        }
        NSApp.activate(ignoringOtherApps: true)
        settings?.makeKeyAndOrderFront(nil)
    }

    func windowWillClose(_ notification: Notification) {
        // Drop the window so its tabs (and any preview) are torn down.
        if NSColorPanel.sharedColorPanelExists { NSColorPanel.shared.close() }
        launcher.preview(false)
        settings?.contentViewController = nil
        settings = nil
        state.saveThemes()
        state.editingThemeID = nil
    }

    func windowDidMove(_ notification: Notification) { launcher.layout() }
    func windowDidBecomeKey(_ notification: Notification) { launcher.resumePreview() }
    func applicationDidBecomeActive(_ notification: Notification) { launcher?.resumePreview() }
    func applicationDidResignActive(_ notification: Notification) { launcher?.suspendPreview() }
    func applicationWillTerminate(_ notification: Notification) { state.saveThemes() }
}
