import Foundation

/// What the user picked, for which query, and how often each app is opened.
public struct LaunchMemory: Codable, Equatable, Sendable {
    public struct Usage: Codable, Equatable, Sendable {
        public var score: Double
        public var last: Date
    }

    /// query → app path → when it was last picked
    public private(set) var choices: [String: [String: Date]] = [:]
    /// query → app path
    public private(set) var pins: [String: String] = [:]
    /// app path → usage
    public private(set) var usage: [String: Usage] = [:]

    private static let halfLife: TimeInterval = 14 * 86_400
    private static let maxQueries = 1_000

    public init() {}

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        choices = try c.decodeIfPresent([String: [String: Date]].self, forKey: .choices) ?? [:]
        pins = try c.decodeIfPresent([String: String].self, forKey: .pins) ?? [:]
        usage = try c.decodeIfPresent([String: Usage].self, forKey: .usage) ?? [:]
    }

    public mutating func recordLaunch(_ path: String, query: Query, now: Date = Date()) {
        usage[path] = Usage(score: frecency(path, now: now) + 1, last: now)
        guard !query.isEmpty else { return }
        choices[query.key, default: [:]][path] = now
        if choices.count > Self.maxQueries,
           let oldest = choices.min(by: { newest($0.value) < newest($1.value) })?.key {
            choices[oldest] = nil
        }
    }

    public mutating func pin(_ path: String, query: Query) {
        guard !query.isEmpty else { return }
        pins[query.key] = path
    }

    public mutating func unpin(_ queryKey: String) { pins[queryKey] = nil }

    public mutating func forget(_ queryKey: String) {
        choices[queryKey] = nil
        pins[queryKey] = nil
    }

    public mutating func forgetAll() { self = LaunchMemory() }

    /// Opens, each losing half its weight every two weeks.
    public func frecency(_ path: String, now: Date = Date()) -> Double {
        guard let u = usage[path] else { return 0 }
        return u.score * pow(0.5, max(0, now.timeIntervalSince(u.last)) / Self.halfLife)
    }

    private func newest(_ picks: [String: Date]) -> Date { picks.values.max() ?? .distantPast }
}
