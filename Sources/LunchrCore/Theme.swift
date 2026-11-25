import Foundation

public enum BlurStyle: String, Codable, CaseIterable, Sendable {
    case none, soft, frosted, heavy, glass
}

public struct RGBA: Codable, Equatable, Sendable {
    public var r, g, b, a: Double

    /// "#RRGGBB" or "#RRGGBBAA"
    public init?(hex: String) {
        let digits = hex.hasPrefix("#") ? String(hex.dropFirst()) : hex
        guard digits.count == 6 || digits.count == 8,
              digits.allSatisfy(\.isHexDigit), let v = UInt32(digits, radix: 16) else { return nil }
        let full = digits.count == 6 ? (v << 8) | 0xFF : v
        r = Double(full >> 24 & 0xFF) / 255
        g = Double(full >> 16 & 0xFF) / 255
        b = Double(full >> 8 & 0xFF) / 255
        a = Double(full & 0xFF) / 255
    }

    /// Relative luminance, 0 (black) to 1 (white), ignoring alpha.
    public var luminance: Double {
        func linear(_ v: Double) -> Double { v <= 0.04045 ? v / 12.92 : pow((v + 0.055) / 1.055, 2.4) }
        return 0.2126 * linear(r) + 0.7152 * linear(g) + 0.0722 * linear(b)
    }

    public func mixed(withWhite share: Double) -> RGBA {
        var c = self
        c.r += (1 - r) * share
        c.g += (1 - g) * share
        c.b += (1 - b) * share
        return c
    }

    public var hex: String {
        let v = [r, g, b].map { String(format: "%02X", Int(($0 * 255).rounded())) }.joined()
        return "#" + v + (a < 1 ? String(format: "%02X", Int((a * 255).rounded())) : "")
    }

    public init(from decoder: Decoder) throws {
        let text = try decoder.singleValueContainer().decode(String.self)
        guard let color = RGBA(hex: text) else {
            throw DecodingError.dataCorrupted(.init(
                codingPath: decoder.codingPath, debugDescription: "\"\(text)\" isn't #RRGGBB or #RRGGBBAA"))
        }
        self = color
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        try c.encode(hex)
    }
}

public struct Theme: Codable, Equatable, Identifiable, Sendable {
    /// File name without .json. Not stored in the file.
    public var id = ""
    public var name = "Untitled"
    public var dark = true
    public var background = RGBA(hex: "#1C1C1F")!
    /// 0 = only the blur shows, 1 = solid.
    public var opacity = 0.6
    public var blur = BlurStyle.frosted
    public var text = RGBA(hex: "#F4F4F6")!
    public var secondaryText = RGBA(hex: "#F4F4F699")!
    public var accent = RGBA(hex: "#6EA8FE")!
    public var selection = RGBA(hex: "#FFFFFF22")!
    public var selectedText = RGBA(hex: "#FFFFFF")!
    public var border = RGBA(hex: "#FFFFFF26")!
    public var cornerRadius = 18.0
    /// "system", "rounded", "mono", "serif", or an installed font family.
    public var font = "system"
    public var querySize = 24.0
    public var rowSize = 15.0
    public var iconSize = 30.0
    public var width = 620.0

    enum CodingKeys: String, CodingKey {
        case name, dark, background, opacity, blur, text, secondaryText, accent, selection
        case selectedText, border, cornerRadius, font, querySize, rowSize, iconSize, width
    }

    public init() {}

    /// Every field is optional: a theme file only needs what it changes.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        func read<T: Decodable>(_ key: CodingKeys, _ value: inout T) throws {
            if let v = try c.decodeIfPresent(T.self, forKey: key) { value = v }
        }
        func read(_ key: CodingKeys, _ value: inout Double, in range: ClosedRange<Double>) throws {
            if let v = try c.decodeIfPresent(Double.self, forKey: key) {
                value = min(max(v, range.lowerBound), range.upperBound)
            }
        }
        try read(.name, &name)
        try read(.dark, &dark)
        try read(.background, &background)
        try read(.opacity, &opacity, in: 0...1)
        try read(.blur, &blur)
        try read(.text, &text)
        try read(.secondaryText, &secondaryText)
        try read(.accent, &accent)
        try read(.selection, &selection)
        try read(.selectedText, &selectedText)
        try read(.border, &border)
        try read(.cornerRadius, &cornerRadius, in: 0...40)
        try read(.font, &font)
        try read(.querySize, &querySize, in: 12...48)
        try read(.rowSize, &rowSize, in: 10...32)
        try read(.iconSize, &iconSize, in: 14...64)
        try read(.width, &width, in: 360...1200)
    }

    /// Reveal glow. Always lighter than the panel: white on light themes, otherwise the accent,
    /// lightened if it's too dark to glow.
    public var glow: RGBA {
        var color = accent
        color.a = 1
        if !dark || background.luminance > 0.4 { return RGBA(hex: "#FFFFFF")! }
        let target = background.luminance + 0.2
        for step in 0...10 {
            let lighter = color.mixed(withWhite: Double(step) / 10)
            if lighter.luminance >= target { return lighter }
        }
        return color.mixed(withWhite: 1)
    }

    // MARK: Layout

    public var rowHeight: Double { max(iconSize, rowSize * 1.3) + 12 }
    public var fieldHeight: Double { querySize + 36 }
    public static let listPadding = 8.0

    public func height(rows: Int) -> Double {
        rows == 0 ? fieldHeight : fieldHeight + 1 + Double(rows) * rowHeight + Self.listPadding * 2
    }
}

extension Theme {
    private static func make(_ id: String, _ name: String, _ edit: (inout Theme) -> Void) -> Theme {
        var t = Theme()
        t.id = id
        t.name = name
        edit(&t)
        return t
    }

    private static func c(_ hex: String) -> RGBA { RGBA(hex: hex)! }

    public static let builtIn: [Theme] = [
        make("graphite", "Graphite") { _ in },
        make("paper", "Paper") {
            $0.dark = false
            $0.background = c("#FBFAF7")
            $0.opacity = 0.65
            $0.text = c("#1D1D1F")
            $0.secondaryText = c("#1D1D1FA6")
            $0.accent = c("#0A5FD6")
            $0.selection = c("#0000001A")
            $0.selectedText = c("#000000")
            $0.border = c("#00000021")
        },
        make("clear", "Clear Glass") {
            $0.background = c("#0B0B0E")
            $0.opacity = 0.3
            $0.blur = .glass
            $0.text = c("#FFFFFF")
            $0.secondaryText = c("#FFFFFFB3")
            $0.accent = c("#8FD3FF")
            $0.selection = c("#FFFFFF2E")
            $0.border = c("#FFFFFF33")
            $0.cornerRadius = 26
        },
        make("midnight", "Midnight") {
            $0.background = c("#0C1430")
            $0.opacity = 0.65
            $0.text = c("#E6ECFF")
            $0.secondaryText = c("#B4C1F0B3")
            $0.accent = c("#7C9BFF")
            $0.selection = c("#5B7CFF4D")
            $0.border = c("#7C9BFF40")
            $0.font = "rounded"
        },
        make("ember", "Ember") {
            $0.background = c("#24130E")
            $0.opacity = 0.65
            $0.text = c("#FFEDE2")
            $0.secondaryText = c("#FFD9C2A6")
            $0.accent = c("#FF9A5C")
            $0.selection = c("#FF7A3D42")
            $0.border = c("#FF9A5C3D")
            $0.font = "rounded"
        },
        make("meadow", "Meadow") {
            $0.dark = false
            $0.background = c("#EEF6EE")
            $0.opacity = 0.65
            $0.text = c("#16301F")
            $0.secondaryText = c("#16301FA6")
            $0.accent = c("#147A43")
            $0.selection = c("#1F9D5733")
            $0.selectedText = c("#0B2114")
            $0.border = c("#147A4333")
        },
        make("console", "Console") {
            $0.background = c("#050A07")
            $0.opacity = 0.75
            $0.blur = .soft
            $0.text = c("#B8F5C8")
            $0.secondaryText = c("#B8F5C899")
            $0.accent = c("#4DFF88")
            $0.selection = c("#4DFF882B")
            $0.selectedText = c("#E4FFEC")
            $0.border = c("#4DFF8847")
            $0.cornerRadius = 6
            $0.font = "mono"
            $0.querySize = 20
            $0.rowSize = 14
            $0.iconSize = 24
        },
    ]
}

public enum ThemeLoader {
    public struct Result: Sendable {
        public var themes: [Theme]
        /// One line per file that couldn't be read.
        public var problems: [String]
    }

    /// Built-in themes plus *.json in `folder`. A file named after a built-in replaces it.
    public static func load(folder: URL) -> Result {
        var themes = Theme.builtIn
        var problems: [String] = []
        let files = (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)) ?? []
        for file in files.sorted(by: { $0.path < $1.path }) where file.pathExtension == "json" {
            do {
                var theme = try JSONDecoder().decode(Theme.self, from: Data(contentsOf: file))
                theme.id = file.deletingPathExtension().lastPathComponent
                if let i = themes.firstIndex(where: { $0.id == theme.id }) {
                    themes[i] = theme
                } else {
                    themes.append(theme)
                }
            } catch {
                problems.append("\(file.lastPathComponent): \(describe(error))")
            }
        }
        return Result(themes: themes, problems: problems)
    }

    private static func describe(_ error: Error) -> String {
        guard let e = error as? DecodingError else { return error.localizedDescription }
        switch e {
        case .typeMismatch(_, let c), .valueNotFound(_, let c), .keyNotFound(_, let c), .dataCorrupted(let c):
            let field = c.codingPath.map(\.stringValue).joined(separator: ".")
            return field.isEmpty ? "not valid JSON" : "\(field): \(c.debugDescription)"
        @unknown default: return error.localizedDescription
        }
    }
}
