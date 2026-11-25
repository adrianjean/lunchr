import Foundation

public enum MatchKind: Int, Comparable, Sendable {
    case fuzzy = 1, substring, initials, wordStart, prefix, exact

    public static func < (a: MatchKind, b: MatchKind) -> Bool { a.rawValue < b.rawValue }
}

public struct Match: Sendable {
    public let kind: MatchKind
    /// How tight the match is inside its kind, 0...1.
    public let quality: Double
    /// Character positions in the original name.
    public let indices: [Int]
}

public struct Query: Sendable {
    /// Form used as the key in memory: folded, trimmed, single spaces.
    public let key: String
    let tokens: [[Character]]
    let compact: [Character]

    public init(_ raw: String) {
        let folded = raw.split(whereSeparator: \.isWhitespace).map { $0.map(SearchName.fold) }
        key = folded.map { String($0) }.joined(separator: " ")
        tokens = folded.map { $0.filter { $0.isLetter || $0.isNumber } }.filter { !$0.isEmpty }
        compact = tokens.flatMap { $0 }
    }

    public var isEmpty: Bool { compact.isEmpty }
}

public enum Matcher {
    /// Best match over all of an app's names. Indices are only returned for the displayed name.
    public static func match(_ query: Query, _ app: AppEntry) -> Match? {
        var best: Match?
        for (i, name) in app.names.enumerated() {
            guard let m = match(query, name) else { continue }
            // Another name has to match in a better way, or the displayed one loses its highlight.
            if let b = best, b.kind >= m.kind { continue }
            best = i == 0 ? m : Match(kind: m.kind, quality: m.quality, indices: [])
        }
        return best
    }

    public static func match(_ query: Query, _ name: SearchName) -> Match? {
        let q = query.compact, c = name.chars
        guard !q.isEmpty, q.count <= c.count else { return nil }
        let coverage = Double(q.count) / Double(c.count)

        func result(_ kind: MatchKind, _ quality: Double, _ positions: [Int]) -> Match {
            Match(kind: kind, quality: quality, indices: positions.map { name.sourceIndex[$0] })
        }
        func run(_ start: Int) -> [Int] { Array(start..<(start + q.count)) }
        func matches(_ needle: [Character], at start: Int) -> Bool {
            start + needle.count <= c.count && c[start..<(start + needle.count)].elementsEqual(needle)
        }

        if c == q { return result(.exact, 1, run(0)) }
        if matches(q, at: 0) { return result(.prefix, coverage, run(0)) }
        if let s = name.wordStarts.first(where: { matches(q, at: $0) }) {
            return result(.wordStart, coverage, run(s))
        }

        // "vis cod" → Visual Studio Code
        if query.tokens.count > 1 {
            var positions: [Int] = []
            var from = 0
            for token in query.tokens {
                guard let s = name.wordStarts.first(where: { $0 >= from && matches(token, at: $0) })
                else { positions = []; break }
                positions += s..<(s + token.count)
                from = s + token.count
            }
            if !positions.isEmpty { return result(.wordStart, coverage, positions) }
        }

        // "vsc" → Visual Studio Code
        if q.count >= 2, q.count <= name.wordStarts.count {
            for s in 0...(name.wordStarts.count - q.count) {
                let starts = Array(name.wordStarts[s..<(s + q.count)])
                if starts.map({ c[$0] }) == q {
                    let share = Double(q.count) / Double(name.wordStarts.count)
                    return result(.initials, s == 0 ? share : share / 2, starts)
                }
            }
        }

        guard q.count >= 2 else { return nil }
        if let s = (0...(c.count - q.count)).first(where: { matches(q, at: $0) }) {
            return result(.substring, coverage, run(s))
        }

        // Letters in order, starting at the start of a word, not too spread out.
        var best: (quality: Double, positions: [Int])?
        for start in name.wordStarts where c[start] == q[0] {
            var positions = [start]
            var at = start + 1
            for ch in q.dropFirst() {
                guard let next = c[at...].firstIndex(of: ch) else { break }
                positions.append(next)
                at = next + 1
            }
            guard positions.count == q.count else { continue }
            let quality = Double(q.count) / Double(positions.last! - start + 1)
            if quality >= 0.35, quality > (best?.quality ?? 0) { best = (quality, positions) }
        }
        return best.map { result(.fuzzy, $0.quality, $0.positions) }
    }
}
