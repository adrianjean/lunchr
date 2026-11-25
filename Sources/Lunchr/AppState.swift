import AppKit
import Combine
import LunchrCore

/// Settings, memory, themes and the app list. One instance for the whole app.
@MainActor
final class AppState: ObservableObject {
    @Published var config: Config { didSet { if config != oldValue { configChanged(from: oldValue) } } }
    @Published private(set) var memory: LaunchMemory
    @Published private(set) var apps: [AppEntry] = []
    @Published private(set) var themes: [Theme]
    @Published private(set) var themeProblems: [String]
    /// Theme open in the editor; the launcher shows it instead of the chosen one.
    @Published var editingThemeID: String?
    @Published private(set) var hotKeyFailed = false
    @Published private(set) var systemIsDark = AppState.readSystemIsDark()

    let home: URL
    var themesFolder: URL { home.appendingPathComponent("Themes") }
    private var configURL: URL { home.appendingPathComponent("config.json") }
    private var memoryURL: URL { home.appendingPathComponent("memory.json") }

    private var icons: [String: NSImage] = [:]
    private var appWatcher: FolderWatcher?
    private var themeWatcher: FolderWatcher?
    private var pendingScan: DispatchWorkItem?
    private var pendingSave: DispatchWorkItem?
    private var unsavedThemes: [String: Theme] = [:]
    private var appearanceObserver: NSKeyValueObservation?
    private let scanQueue = DispatchQueue(label: "lunchr.scan", qos: .userInitiated)

    init() {
        // LUNCHR_HOME keeps development runs away from the real settings.
        if let custom = ProcessInfo.processInfo.environment["LUNCHR_HOME"] {
            home = URL(fileURLWithPath: custom)
        } else {
            home = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
                .appendingPathComponent("Lunchr")
        }
        config = JSONFile.load(Config.self, from: home.appendingPathComponent("config.json")) ?? Config()
        memory = JSONFile.load(LaunchMemory.self, from: home.appendingPathComponent("memory.json")) ?? LaunchMemory()
        let loaded = ThemeLoader.load(folder: home.appendingPathComponent("Themes"))
        themes = loaded.themes
        themeProblems = loaded.problems
    }

    func start() {
        try? FileManager.default.createDirectory(at: themesFolder, withIntermediateDirectories: true)
        registerHotKey()
        rescan()
        watchApps()
        themeWatcher = FolderWatcher(paths: [themesFolder.path]) { [weak self] _ in
            MainActor.assumeIsolated { self?.reloadThemes() }
        }
        appearanceObserver = NSApp.observe(\.effectiveAppearance) { [weak self] _, _ in
            DispatchQueue.main.async {
                MainActor.assumeIsolated { self?.systemIsDark = AppState.readSystemIsDark() }
            }
        }
    }

    // MARK: Apps

    private var roots: [String] { AppScanner.defaultRoots + config.extraFolders }

    func rescan() {
        let roots = self.roots
        scanQueue.async {
            let apps = AppScanner.scan(roots: roots)
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    self.apps = apps
                    self.loadIcons(apps)
                }
            }
        }
    }

    private func watchApps() {
        appWatcher = FolderWatcher(paths: roots) { [weak self] paths in
            // Ignore apps writing inside their own bundle.
            let relevant = paths.contains { path in
                guard let r = path.range(of: ".app/") else { return true }
                let inside = path[r.upperBound...]
                return inside.isEmpty || inside == "Contents" || inside == "Contents/"
            }
            if relevant { MainActor.assumeIsolated { self?.scheduleScan() } }
        }
    }

    private func scheduleScan() {
        pendingScan?.cancel()
        let work = DispatchWorkItem { [weak self] in
            MainActor.assumeIsolated {
                self?.icons = [:]
                self?.rescan()
            }
        }
        pendingScan = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5, execute: work)
    }

    func icon(_ path: String) -> NSImage {
        if let cached = icons[path] { return cached }
        let icon = Self.fileIcon(path)
        icons[path] = icon
        return icon
    }

    /// The real file's icon: a symlink's (Safari) has an alias arrow on it.
    nonisolated private static func fileIcon(_ path: String) -> NSImage {
        NSWorkspace.shared.icon(forFile: URL(fileURLWithPath: path).resolvingSymlinksInPath().path)
    }

    /// Draws every icon once in the background so the first search doesn't wait for them.
    private func loadIcons(_ apps: [AppEntry]) {
        let missing = apps.map(\.path).filter { icons[$0] == nil }
        scanQueue.async {
            for path in missing {
                let icon = Self.fileIcon(path)
                var rect = NSRect(x: 0, y: 0, width: 64, height: 64)
                guard let image = icon.cgImage(forProposedRect: &rect, context: nil, hints: nil) else { continue }
                let flat = NSImage(cgImage: image, size: NSSize(width: 64, height: 64))
                DispatchQueue.main.async { MainActor.assumeIsolated { self.icons[path] = flat } }
            }
        }
    }

    func name(_ path: String) -> String {
        apps.first { $0.path == path }?.name
            ?? ((path as NSString).lastPathComponent as NSString).deletingPathExtension
    }

    // MARK: Search and memory

    func search(_ text: String) -> [RankedApp] {
        let query = Query(text)
        let hidden = Set(config.hidden)
        if query.isEmpty {
            guard config.showRecents, text.allSatisfy(\.isWhitespace) else { return [] }
            return Ranker.recents(apps: apps, memory: memory, hidden: hidden, limit: config.maxResults)
        }
        return Ranker.rank(query, apps: apps, memory: memory, hidden: hidden, limit: config.maxResults)
    }

    func updateMemory(_ change: (inout LaunchMemory) -> Void) {
        change(&memory)
        save(memory, to: memoryURL)
    }

    func setHidden(_ path: String, _ hide: Bool) {
        config.hidden.removeAll { $0 == path }
        if hide { config.hidden.append(path) }
    }

    // MARK: Themes

    var activeThemeID: String { systemIsDark ? config.darkTheme : config.lightTheme }

    var theme: Theme {
        // While a theme is being edited, show exactly that theme.
        if let id = editingThemeID, let theme = themes.first(where: { $0.id == id }) { return theme }
        var theme = themes.first { $0.id == activeThemeID } ?? themes[0]
        if let opacity = config.opacity { theme.opacity = opacity }
        if let blur = config.blur { theme.blur = blur }
        return theme
    }

    private func reloadThemes() {
        // Unsaved edits are newer than the files; saving them brings us back here.
        guard unsavedThemes.isEmpty else { return }
        let loaded = ThemeLoader.load(folder: themesFolder)
        if themes != loaded.themes { themes = loaded.themes }
        if themeProblems != loaded.problems { themeProblems = loaded.problems }
    }

    func useTheme(_ id: String) {
        if systemIsDark { config.darkTheme = id } else { config.lightTheme = id }
    }

    /// True when the theme has a file: the user's own, or an edited built-in.
    func hasFile(_ id: String) -> Bool {
        unsavedThemes[id] != nil
            || FileManager.default.fileExists(atPath: ThemeLoader.file(id, in: themesFolder).path)
    }

    /// Shows the edit at once and saves shortly after the last one.
    func updateTheme(_ theme: Theme) {
        guard let i = themes.firstIndex(where: { $0.id == theme.id }), themes[i] != theme else { return }
        unsavedThemes[theme.id] = theme
        themes[i] = theme
        pendingSave?.cancel()
        let work = DispatchWorkItem { [weak self] in MainActor.assumeIsolated { self?.saveThemes() } }
        pendingSave = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4, execute: work)
    }

    func saveThemes() {
        pendingSave?.cancel()
        pendingSave = nil
        let edited = unsavedThemes.values
        unsavedThemes = [:]
        var failures: [String] = []
        for theme in edited {
            do {
                try ThemeLoader.save(theme, in: themesFolder)
            } catch {
                failures.append("\(theme.name) wasn't saved: \(error.localizedDescription)")
            }
        }
        if !failures.isEmpty { themeProblems = failures }
    }

    /// Returns the id of the copy.
    func duplicateTheme(_ id: String) -> String? {
        guard let source = themes.first(where: { $0.id == id }) else { return nil }
        saveThemes()
        let copy = ThemeLoader.duplicate(source, among: themes, in: themesFolder)
        guard save(copy, to: ThemeLoader.file(copy.id, in: themesFolder)) else { return nil }
        reloadThemes()
        return copy.id
    }

    /// Moves the theme's file to the Trash: deletes the user's own, restores a built-in.
    func removeThemeFile(_ id: String) {
        saveThemes()
        do {
            try FileManager.default.trashItem(
                at: ThemeLoader.file(id, in: themesFolder), resultingItemURL: nil)
        } catch {
            themeProblems = ["Couldn't move the theme to the Trash: \(error.localizedDescription)"]
            return
        }
        if !ThemeLoader.isBuiltIn(id) {
            if config.lightTheme == id { config.lightTheme = Config().lightTheme }
            if config.darkTheme == id { config.darkTheme = Config().darkTheme }
        }
        reloadThemes()
    }

    private static func readSystemIsDark() -> Bool {
        NSApplication.shared.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
    }

    // MARK: Settings

    private func configChanged(from old: Config) {
        save(config, to: configURL)
        if config.hotKey != old.hotKey { registerHotKey() }
        if config.extraFolders != old.extraFolders {
            watchApps()
            rescan()
        }
    }

    func registerHotKey() {
        hotKeyFailed = !HotKeyCenter.shared.register(config.hotKey)
    }

    @discardableResult
    private func save<T: Encodable>(_ value: T, to url: URL) -> Bool {
        do {
            try JSONFile.save(value, to: url)
            return true
        } catch {
            NSLog("Lunchr: couldn't save %@: %@", url.path, error.localizedDescription)
            return false
        }
    }
}
