import XCTest
@testable import LunchrCore

final class MatcherTests: XCTestCase {
    private func kind(_ q: String, _ name: String) -> MatchKind? {
        Matcher.match(Query(q), SearchName(name))?.kind
    }

    func testKinds() {
        XCTAssertEqual(kind("notes", "Notes"), .exact)
        XCTAssertEqual(kind("term", "Terminal"), .prefix)
        XCTAssertEqual(kind("term", "iTerm2"), .wordStart)
        XCTAssertEqual(kind("code", "Visual Studio Code"), .wordStart)
        XCTAssertEqual(kind("vsc", "Visual Studio Code"), .initials)
        XCTAssertEqual(kind("vis cod", "Visual Studio Code"), .wordStart)
        XCTAssertEqual(kind("visualstudio", "Visual Studio Code"), .prefix)
        XCTAssertEqual(kind("shop", "Photoshop"), .substring)
        XCTAssertEqual(kind("phtshp", "Photoshop"), .fuzzy)
        XCTAssertNil(kind("xyz", "Photoshop"))
        XCTAssertNil(kind("hot", "Terminal"))
    }

    func testAccentsCaseAndPunctuation() {
        XCTAssertEqual(kind("cafe", "Café"), .exact)
        XCTAssertEqual(kind("PASS", "1Password"), .wordStart)
        XCTAssertEqual(kind("tv", "TV"), .exact)
        XCTAssertNil(kind("  ", "TV"))
        XCTAssertNil(kind("++", "TV"))
    }

    func testHighlightsPointAtTheOriginalName() {
        XCTAssertEqual(Matcher.match(Query("vsc"), SearchName("Visual Studio Code"))?.indices, [0, 7, 14])
        XCTAssertEqual(Matcher.match(Query("term"), SearchName("iTerm2"))?.indices, [1, 2, 3, 4])
    }

    func testAlternateNameMatchesWithoutHighlight() {
        let app = AppEntry(path: "/A/iTerm.app", name: "iTerm", alternateNames: ["iTerm2", "iTerm"])
        let m = Matcher.match(Query("iterm2"), app)
        XCTAssertEqual(m?.kind, .exact)
        XCTAssertEqual(m?.indices, [])
        XCTAssertEqual(app.names.count, 2)
    }

    func testShorterAlternateNameKeepsTheHighlight() {
        let app = AppEntry(
            path: "/D.app", name: "Blackmagic Disk Speed Test", alternateNames: ["Disk Speed Test"])
        XCTAssertEqual(Matcher.match(Query("te"), app)?.indices, [22, 23])
    }
}

final class RankerTests: XCTestCase {
    private let terminal = AppEntry(path: "/Terminal.app", name: "Terminal")
    private let iterm = AppEntry(path: "/iTerm.app", name: "iTerm2")
    private let textEdit = AppEntry(path: "/TextEdit.app", name: "TextEdit")
    private let photos = AppEntry(path: "/Photos.app", name: "Photos")
    private let photoshop = AppEntry(path: "/Photoshop.app", name: "Photoshop")
    private var apps: [AppEntry] { [terminal, iterm, textEdit, photos, photoshop] }
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    private func top(_ q: String, _ m: LaunchMemory, hidden: Set<String> = []) -> String? {
        names(q, m, hidden: hidden).first
    }

    private func names(_ q: String, _ m: LaunchMemory, hidden: Set<String> = []) -> [String] {
        Ranker.rank(Query(q), apps: apps, memory: m, hidden: hidden, limit: 10, now: now).map(\.app.name)
    }

    func testPickIsRememberedForTheQueryAndItsPrefixes() {
        var m = LaunchMemory()
        XCTAssertEqual(top("term", m), "Terminal")
        m.recordLaunch(iterm.path, query: Query("Term"), now: now)
        XCTAssertEqual(top("term", m), "iTerm2")
        XCTAssertEqual(top("ter", m), "iTerm2")
        XCTAssertEqual(top("te", m), "iTerm2")
        XCTAssertEqual(top("terminal", m), "Terminal")
    }

    func testOneLetterIsOnlyTaughtByItself() {
        var m = LaunchMemory()
        m.recordLaunch(iterm.path, query: Query("term"), now: now)
        XCTAssertNotEqual(top("t", m), "iTerm2")
        m.recordLaunch(iterm.path, query: Query("t"), now: now)
        XCTAssertEqual(top("t", m), "iTerm2")
    }

    func testLatestPickWins() {
        var m = LaunchMemory()
        m.recordLaunch(iterm.path, query: Query("term"), now: now.addingTimeInterval(-60))
        m.recordLaunch(terminal.path, query: Query("term"), now: now)
        XCTAssertEqual(names("term", m), ["Terminal", "iTerm2"])
    }

    func testExactQueryPickBeatsRelatedPick() {
        var m = LaunchMemory()
        m.recordLaunch(iterm.path, query: Query("term"), now: now)
        m.recordLaunch(textEdit.path, query: Query("te"), now: now.addingTimeInterval(-60))
        XCTAssertEqual(top("te", m), "TextEdit")
    }

    func testPinBeatsLaterPicks() {
        var m = LaunchMemory()
        m.pin(iterm.path, query: Query("term"))
        m.recordLaunch(terminal.path, query: Query("term"), now: now)
        XCTAssertEqual(top("term", m), "iTerm2")
        XCTAssertEqual(
            Ranker.rank(Query("term"), apps: apps, memory: m, limit: 5, now: now).map(\.isPinned), [true, false])
        m.unpin("term")
        XCTAssertEqual(top("term", m), "Terminal")
    }

    func testFullNameBeatsRelatedPick() {
        var m = LaunchMemory()
        m.recordLaunch(photoshop.path, query: Query("phot"), now: now)
        XCTAssertEqual(top("photo", m), "Photoshop")
        XCTAssertEqual(top("photos", m), "Photos")
    }

    func testUsageBreaksTiesButNotMatchKind() {
        var m = LaunchMemory()
        for _ in 0..<50 { m.recordLaunch(photoshop.path, query: Query(""), now: now) }
        XCTAssertEqual(top("ph", m), "Photoshop")
        for _ in 0..<50 { m.recordLaunch(iterm.path, query: Query(""), now: now) }
        XCTAssertEqual(top("term", m), "Terminal")
    }

    func testFuzzyHiddenWhenThereIsABetterMatch() {
        let list = [terminal, AppEntry(path: "/T.app", name: "Teleramica")]
        let r = Ranker.rank(Query("term"), apps: list, memory: LaunchMemory(), limit: 5, now: now)
        XCTAssertEqual(r.map(\.app.name), ["Terminal"])
    }

    func testHiddenAppsAndRecents() {
        var m = LaunchMemory()
        XCTAssertEqual(names("term", m, hidden: [terminal.path]), ["iTerm2"])
        XCTAssertTrue(Ranker.recents(apps: apps, memory: m, limit: 5, now: now).isEmpty)
        m.recordLaunch(photos.path, query: Query("ph"), now: now.addingTimeInterval(-86_400 * 14))
        m.recordLaunch(iterm.path, query: Query("it"), now: now)
        XCTAssertEqual(Ranker.recents(apps: apps, memory: m, limit: 5, now: now).map(\.app.name), ["iTerm2", "Photos"])
        XCTAssertEqual(m.frecency(photos.path, now: now), 0.5, accuracy: 0.001)
    }

    func testForget() {
        var m = LaunchMemory()
        m.recordLaunch(iterm.path, query: Query("term"), now: now)
        m.pin(iterm.path, query: Query("term"))
        m.forget("term")
        XCTAssertEqual(top("term", m), "Terminal")
    }
}

final class FileTests: XCTestCase {
    private var dir: URL!

    override func setUpWithError() throws {
        dir = FileManager.default.temporaryDirectory.appendingPathComponent("lunchr-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    }

    override func tearDown() { try? FileManager.default.removeItem(at: dir) }

    private func write(_ text: String, _ name: String) throws {
        try Data(text.utf8).write(to: dir.appendingPathComponent(name))
    }

    func testThemeFilesPartialOverrideAndBroken() throws {
        try write(##"{"name": "Mine", "background": "#102030", "opacity": 5}"##, "mine.json")
        try write(##"{"name": "My Paper", "dark": false}"##, "paper.json")
        try write(##"{"text": "red"}"##, "broken.json")
        let r = ThemeLoader.load(folder: dir)
        XCTAssertEqual(r.themes.count, Theme.builtIn.count + 1)
        let mine = try XCTUnwrap(r.themes.first { $0.id == "mine" })
        XCTAssertEqual(mine.background.hex, "#102030")
        XCTAssertEqual(mine.opacity, 1)
        XCTAssertEqual(mine.querySize, Theme().querySize)
        XCTAssertEqual(r.themes.first { $0.id == "paper" }?.name, "My Paper")
        XCTAssertEqual(r.problems.count, 1)
        XCTAssertTrue(r.problems[0].contains("text"))
    }

    func testGlowIsAlwaysLighterThanThePanel() {
        for theme in Theme.builtIn {
            XCTAssertGreaterThan(theme.glow.luminance, theme.background.luminance, theme.name)
            if !theme.dark { XCTAssertEqual(theme.glow.hex, "#FFFFFF", theme.name) }
        }
        var theme = Theme()
        theme.accent = RGBA(hex: "#000000")!
        XCTAssertGreaterThan(theme.glow.luminance, theme.background.luminance + 0.19)
    }

    func testEditedThemeSurvivesSaveAndLoad() throws {
        var paper = try XCTUnwrap(Theme.builtIn.first { $0.id == "paper" })
        paper.accent = RGBA(r: 0.123456, g: 2, b: -1, a: 0.5)
        paper.width = 700
        try ThemeLoader.save(paper, in: dir)
        let loaded = ThemeLoader.load(folder: dir)
        XCTAssertEqual(loaded.themes.count, Theme.builtIn.count)
        XCTAssertEqual(loaded.themes.first { $0.id == "paper" }, paper)
        XCTAssertEqual(paper.accent.hex, "#1FFF0080")
    }

    func testDuplicateFindsAFreeName() throws {
        let paper = try XCTUnwrap(Theme.builtIn.first { $0.id == "paper" })
        let one = ThemeLoader.duplicate(paper, among: Theme.builtIn, in: dir)
        XCTAssertEqual([one.id, one.name], ["paper-copy", "Paper copy"])
        let two = ThemeLoader.duplicate(paper, among: Theme.builtIn + [one], in: dir)
        XCTAssertEqual([two.id, two.name], ["paper-copy-2", "Paper copy 2"])
        // A broken file isn't in the list but its name is still taken.
        try write("{", "paper-copy.json")
        XCTAssertEqual(ThemeLoader.duplicate(paper, among: Theme.builtIn, in: dir).id, "paper-copy-2")
    }

    func testThemeRoundTrip() throws {
        for theme in Theme.builtIn {
            var back = try JSONDecoder().decode(Theme.self, from: JSONEncoder().encode(theme))
            back.id = theme.id
            XCTAssertEqual(back, theme)
        }
    }

    func testConfigAndMemoryRoundTripAndBadFile() throws {
        let url = dir.appendingPathComponent("config.json")
        var config = Config()
        config.hotKey = .commandSpace
        config.blur = .glass
        config.opacity = 0.4
        try JSONFile.save(config, to: url)
        XCTAssertEqual(JSONFile.load(Config.self, from: url), config)

        var m = LaunchMemory()
        m.recordLaunch("/A.app", query: Query("a"))
        m.pin("/A.app", query: Query("a"))
        let mem = dir.appendingPathComponent("memory.json")
        try JSONFile.save(m, to: mem)
        XCTAssertEqual(JSONFile.load(LaunchMemory.self, from: mem), m)

        try write("{ not json", "config.json")
        XCTAssertNil(JSONFile.load(Config.self, from: url))
        XCTAssertTrue(FileManager.default.fileExists(atPath: dir.appendingPathComponent("config.bad.json").path))
    }

    func testScannerSymlinksNestingAndBackgroundOnly() throws {
        func app(_ path: String, _ plist: [String: Any]) throws {
            let contents = dir.appendingPathComponent(path + "/Contents")
            try FileManager.default.createDirectory(at: contents, withIntermediateDirectories: true)
            try (plist as NSDictionary).write(to: contents.appendingPathComponent("Info.plist"))
        }
        try app("apps/One.app", ["CFBundleName": "Uno"])
        try app("apps/One.app/Contents/Helpers/Inner.app", [:])
        try app("apps/Suite/Two.app", [:])
        try app("apps/Agent.app", ["LSBackgroundOnly": true])
        try app("elsewhere/Linked.app", [:])
        try FileManager.default.createSymbolicLink(
            at: dir.appendingPathComponent("apps/Linked.app"),
            withDestinationURL: dir.appendingPathComponent("elsewhere/Linked.app"))
        let found = AppScanner.scan(roots: [dir.appendingPathComponent("apps").path], includeExtras: false)
        XCTAssertEqual(found.map(\.name), ["Linked", "One", "Two"])
        XCTAssertEqual(found[1].names.map(\.text), ["One", "Uno"])
    }

    func testRealMachineScan() {
        let names = Set(AppScanner.scan().map(\.name))
        for expected in ["Safari", "Finder", "Terminal", "System Settings"] {
            XCTAssertTrue(names.contains(expected), expected)
        }
    }
}
