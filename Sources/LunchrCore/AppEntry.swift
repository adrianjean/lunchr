import Foundation

/// A name prepared for matching: letters and digits only, case and accents removed,
/// with the positions where words start ("iTerm2" → i, T, 2).
public struct SearchName: Hashable, Sendable {
    public let text: String
    let chars: [Character]
    /// Position of each entry of `chars` in `text`, for highlighting.
    let sourceIndex: [Int]
    let wordStarts: [Int]

    public init(_ text: String) {
        self.text = text
        let source = Array(text)
        var chars: [Character] = []
        var sourceIndex: [Int] = []
        var wordStarts: [Int] = []

        for (i, c) in source.enumerated() where c.isLetter || c.isNumber {
            if Self.startsWord(source, i) { wordStarts.append(chars.count) }
            chars.append(Self.fold(c))
            sourceIndex.append(i)
        }
        self.chars = chars
        self.sourceIndex = sourceIndex
        self.wordStarts = wordStarts
    }

    private static func startsWord(_ s: [Character], _ i: Int) -> Bool {
        guard i > 0 else { return true }
        let c = s[i], prev = s[i - 1]
        if !(prev.isLetter || prev.isNumber) { return true }
        if c.isNumber != prev.isNumber { return true }
        if c.isUppercase {
            if prev.isLowercase { return true }
            if prev.isUppercase, i + 1 < s.count, s[i + 1].isLowercase { return true }
        }
        return false
    }

    static func fold(_ c: Character) -> Character {
        let folded = String(c).folding(
            options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: nil)
        return folded.count == 1 ? folded.first! : c
    }
}

public struct AppEntry: Identifiable, Hashable, Sendable {
    public let path: String
    /// The name Finder shows, followed by any other names in Info.plist.
    public let names: [SearchName]

    public var id: String { path }
    public var name: String { names[0].text }
    public var url: URL { URL(fileURLWithPath: path) }

    public init(path: String, name: String, alternateNames: [String] = []) {
        self.path = path
        var seen: Set<String> = [name]
        self.names = [SearchName(name)]
            + alternateNames.filter { !$0.isEmpty && seen.insert($0).inserted }.map(SearchName.init)
    }
}
