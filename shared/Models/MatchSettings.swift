import Foundation

/// V1 defaults from product.md. `goldenPointEnabled` is chosen per match at start on Watch.
public struct MatchSettings: Codable, Sendable, Equatable {
    /// Quick-undo window on the score screen and game interstitial. Not persisted per match.
    public static let quickUndoTimeoutSeconds: TimeInterval = 3

    /// Auto-end or discard an in-progress match after this much time without a new point.
    public static let inactivityTimeoutSeconds: TimeInterval = 30 * 60

    public var setsToWin: Int
    public var gamesToWinSet: Int
    public var mustWinByTwoGames: Bool
    public var goldenPointEnabled: Bool

    public init(
        setsToWin: Int = 2,
        gamesToWinSet: Int = 6,
        mustWinByTwoGames: Bool = true,
        goldenPointEnabled: Bool = true
    ) {
        self.setsToWin = setsToWin
        self.gamesToWinSet = gamesToWinSet
        self.mustWinByTwoGames = mustWinByTwoGames
        self.goldenPointEnabled = goldenPointEnabled
    }

    public static let `default` = MatchSettings()

    private enum CodingKeys: String, CodingKey {
        case setsToWin
        case gamesToWinSet
        case mustWinByTwoGames
        case goldenPointEnabled
        case undoTimeoutSeconds
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        setsToWin = try container.decode(Int.self, forKey: .setsToWin)
        gamesToWinSet = try container.decode(Int.self, forKey: .gamesToWinSet)
        mustWinByTwoGames = try container.decode(Bool.self, forKey: .mustWinByTwoGames)
        goldenPointEnabled = try container.decode(Bool.self, forKey: .goldenPointEnabled)
        // Legacy per-match value is ignored; timeout is always `quickUndoTimeoutSeconds`.
        _ = try container.decodeIfPresent(TimeInterval.self, forKey: .undoTimeoutSeconds)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(setsToWin, forKey: .setsToWin)
        try container.encode(gamesToWinSet, forKey: .gamesToWinSet)
        try container.encode(mustWinByTwoGames, forKey: .mustWinByTwoGames)
        try container.encode(goldenPointEnabled, forKey: .goldenPointEnabled)
    }
}
