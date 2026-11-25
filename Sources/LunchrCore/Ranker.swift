import Foundation

public struct RankedApp: Identifiable, Sendable {
    public let app: AppEntry
    public let indices: [Int]
    public let isPinned: Bool
    public var id: String { app.path }
}

public enum Ranker {
    /// Highest first. `exactName` sits above `related` so that typing a full app name
    /// always beats something learned from a shorter query.
    private enum Level: Int { case text, related, relatedPin, exactName, picked, pinned }

    public static func rank(
        _ query: Query, apps: [AppEntry], memory: LaunchMemory,
        hidden: Set<String> = [], limit: Int, now: Date = Date()
    ) -> [RankedApp] {
        let picked = memory.choices[query.key] ?? [:]
        let pinned = memory.pins[query.key]
        let related = relatedPicks(query.key, memory)

        struct Scored {
            let app: AppEntry, match: Match, level: Level, recency: Date, score: Double
        }

        var scored: [Scored] = []
        for app in apps where !hidden.contains(app.path) {
            guard let m = Matcher.match(query, app) else { continue }
            var level = Level.text
            var recency = Date.distantPast
            if pinned == app.path {
                level = .pinned
            } else if let date = picked[app.path] {
                level = .picked
                recency = date
            } else if m.kind == .exact {
                level = .exactName
            } else if m.kind > .fuzzy, related.pins.contains(app.path) {
                level = .relatedPin
            } else if m.kind > .fuzzy, let date = related.picks[app.path] {
                level = .related
                recency = date
            }
            // Usage reorders apps inside a match kind but never lifts one into the next.
            let used = memory.frecency(app.path, now: now)
            let score = Double(m.kind.rawValue) * 100 + 80 * used / (used + 3) + 15 * m.quality
            scored.append(Scored(app: app, match: m, level: level, recency: recency, score: score))
        }

        // Loose matches are only worth showing when there's nothing better.
        if scored.contains(where: { $0.match.kind > .fuzzy }) {
            scored.removeAll { $0.match.kind == .fuzzy && $0.level == .text }
        }

        scored.sort { a, b in
            if a.level != b.level { return a.level.rawValue > b.level.rawValue }
            if a.recency != b.recency { return a.recency > b.recency }
            if a.score != b.score { return a.score > b.score }
            return a.app.name.localizedStandardCompare(b.app.name) == .orderedAscending
        }
        return scored.prefix(limit).map {
            RankedApp(app: $0.app, indices: $0.match.indices, isPinned: $0.level == .pinned)
        }
    }

    /// What to show before anything is typed.
    public static func recents(
        apps: [AppEntry], memory: LaunchMemory, hidden: Set<String> = [], limit: Int, now: Date = Date()
    ) -> [RankedApp] {
        apps.filter { !hidden.contains($0.path) }
            .map { ($0, memory.frecency($0.path, now: now)) }
            .filter { $0.1 > 0.05 }
            .sorted { $0.1 > $1.1 }
            .prefix(limit)
            .map { RankedApp(app: $0.0, indices: [], isPinned: false) }
    }

    /// Picks made for a longer or shorter version of this query ("term" teaches "te" and "ter").
    private static func relatedPicks(
        _ key: String, _ memory: LaunchMemory
    ) -> (picks: [String: Date], pins: Set<String>) {
        func isRelated(_ other: String) -> Bool {
            other != key && min(other.count, key.count) >= 2
                && (other.hasPrefix(key) || key.hasPrefix(other))
        }
        var picks: [String: Date] = [:]
        for (other, apps) in memory.choices where isRelated(other) {
            for (path, date) in apps { picks[path] = max(date, picks[path] ?? .distantPast) }
        }
        let pins = memory.pins.filter { isRelated($0.key) }.values
        return (picks, Set(pins))
    }
}
