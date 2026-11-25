import Foundation

/// Key code and Carbon modifier flags, as RegisterEventHotKey wants them.
public struct HotKey: Codable, Equatable, Sendable {
    public var keyCode: UInt32
    public var modifiers: UInt32

    public init(keyCode: UInt32, modifiers: UInt32) {
        self.keyCode = keyCode
        self.modifiers = modifiers
    }

    public static let command: UInt32 = 0x100
    public static let shift: UInt32 = 0x200
    public static let option: UInt32 = 0x800
    public static let control: UInt32 = 0x1000

    public static let optionSpace = HotKey(keyCode: 49, modifiers: option)
    public static let commandSpace = HotKey(keyCode: 49, modifiers: command)
}

/// How the launcher appears. It takes keys from the first frame in all of them.
public enum RevealStyle: String, Codable, CaseIterable, Sendable {
    case off, pop, glow
}

public struct Config: Codable, Equatable, Sendable {
    public var hotKey = HotKey.optionSpace
    public var lightTheme = "paper"
    public var darkTheme = "graphite"
    /// nil = use the theme's own value.
    public var opacity: Double?
    public var blur: BlurStyle?
    public var reveal = RevealStyle.glow
    /// Cover the screen with a colour while the launcher is open.
    public var dim = false
    /// 0...1
    public var dimAmount = 0.4
    /// Alpha is ignored; `dimAmount` sets it.
    public var dimColor = RGBA(hex: "#000000")!
    public var maxResults = 7
    public var showRecents = true
    public var hidden: [String] = []
    public var extraFolders: [String] = []

    public init() {}

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = Config()
        hotKey = try c.decodeIfPresent(HotKey.self, forKey: .hotKey) ?? d.hotKey
        lightTheme = try c.decodeIfPresent(String.self, forKey: .lightTheme) ?? d.lightTheme
        darkTheme = try c.decodeIfPresent(String.self, forKey: .darkTheme) ?? d.darkTheme
        opacity = try c.decodeIfPresent(Double.self, forKey: .opacity).map { min(max($0, 0), 1) }
        blur = try c.decodeIfPresent(BlurStyle.self, forKey: .blur)
        reveal = try c.decodeIfPresent(RevealStyle.self, forKey: .reveal) ?? d.reveal
        dim = try c.decodeIfPresent(Bool.self, forKey: .dim) ?? d.dim
        dimAmount = min(max(try c.decodeIfPresent(Double.self, forKey: .dimAmount) ?? d.dimAmount, 0), 1)
        dimColor = try c.decodeIfPresent(RGBA.self, forKey: .dimColor) ?? d.dimColor
        maxResults = min(max(try c.decodeIfPresent(Int.self, forKey: .maxResults) ?? d.maxResults, 3), 12)
        showRecents = try c.decodeIfPresent(Bool.self, forKey: .showRecents) ?? d.showRecents
        hidden = try c.decodeIfPresent([String].self, forKey: .hidden) ?? d.hidden
        extraFolders = try c.decodeIfPresent([String].self, forKey: .extraFolders) ?? d.extraFolders
    }
}

public enum JSONFile {
    /// A file that can't be read is moved aside as *.bad.json rather than overwritten.
    public static func load<T: Decodable>(_ type: T.Type, from url: URL) -> T? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        if let value = try? JSONDecoder().decode(type, from: data) { return value }
        let aside = url.deletingPathExtension().appendingPathExtension("bad.json")
        try? FileManager.default.removeItem(at: aside)
        try? FileManager.default.moveItem(at: url, to: aside)
        return nil
    }

    public static func save<T: Encodable>(_ value: T, to url: URL) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try encoder.encode(value).write(to: url, options: .atomic)
    }
}
