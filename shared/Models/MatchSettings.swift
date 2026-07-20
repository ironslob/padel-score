import Foundation

public enum MatchSetFormat: String, CaseIterable, Codable, Sendable, Identifiable {
    case bestOfOne
    case bestOfThree
    case bestOfFive
    case continuous

    public var id: String { rawValue }

    public var label: String {
        switch self {
        case .bestOfOne: return "1 set"
        case .bestOfThree: return "Best of 3"
        case .bestOfFive: return "Best of 5"
        case .continuous: return "Continuous"
        }
    }

    public func apply(to settings: inout MatchSettings) {
        switch self {
        case .bestOfOne:
            settings.setsToWin = 1
            settings.continuousPlay = false
        case .bestOfThree:
            settings.setsToWin = 2
            settings.continuousPlay = false
        case .bestOfFive:
            settings.setsToWin = 3
            settings.continuousPlay = false
        case .continuous:
            settings.continuousPlay = true
        }
    }
}

/// V1 defaults from product.md. `goldenPointEnabled` is a persisted preference on Watch.
public struct MatchSettings: Codable, Sendable, Equatable {
    /// Quick-undo window on the score screen and game interstitial. Not persisted per match.
    public static let quickUndoTimeoutSeconds: TimeInterval = 3

    /// Auto-end or discard an in-progress match after this much time without a new point.
    public static let inactivityTimeoutSeconds: TimeInterval = 30 * 60

    public var setsToWin: Int
    /// When true, the match keeps going after each set until manually finished.
    public var continuousPlay: Bool
    public var gamesToWinSet: Int
    public var mustWinByTwoGames: Bool
    public var goldenPointEnabled: Bool
    /// When true, the player must choose who is serving at the start of each new set.
    public var askServeAtSetStart: Bool
    /// When true, serve does not rotate after games; the side chosen at match start stays fixed.
    /// Default true (UI "Swap sides each game" off).
    public var fixedServerPositions: Bool
    /// When true, score buttons show "Us" / "Them" instead of "Serving" / "Receiving".
    public var usThemLabels: Bool

    public init(
        setsToWin: Int = 2,
        continuousPlay: Bool = false,
        gamesToWinSet: Int = 6,
        mustWinByTwoGames: Bool = true,
        goldenPointEnabled: Bool = true,
        askServeAtSetStart: Bool = false,
        fixedServerPositions: Bool = true,
        usThemLabels: Bool = true
    ) {
        self.setsToWin = setsToWin
        self.continuousPlay = continuousPlay
        self.gamesToWinSet = gamesToWinSet
        self.mustWinByTwoGames = mustWinByTwoGames
        self.goldenPointEnabled = goldenPointEnabled
        self.askServeAtSetStart = askServeAtSetStart
        self.fixedServerPositions = fixedServerPositions
        self.usThemLabels = usThemLabels
    }

    public static let `default` = MatchSettings()

    public var matchSetFormat: MatchSetFormat {
        if continuousPlay { return .continuous }
        switch setsToWin {
        case 1: return .bestOfOne
        case 3: return .bestOfFive
        default: return .bestOfThree
        }
    }

    private enum CodingKeys: String, CodingKey {
        case setsToWin
        case continuousPlay
        case gamesToWinSet
        case mustWinByTwoGames
        case goldenPointEnabled
        case askServeAtSetStart
        case fixedServerPositions
        case usThemLabels
        case undoTimeoutSeconds
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        setsToWin = try container.decode(Int.self, forKey: .setsToWin)
        continuousPlay = try container.decodeIfPresent(Bool.self, forKey: .continuousPlay) ?? false
        gamesToWinSet = try container.decode(Int.self, forKey: .gamesToWinSet)
        mustWinByTwoGames = try container.decode(Bool.self, forKey: .mustWinByTwoGames)
        goldenPointEnabled = try container.decode(Bool.self, forKey: .goldenPointEnabled)
        askServeAtSetStart = try container.decodeIfPresent(Bool.self, forKey: .askServeAtSetStart) ?? false
        fixedServerPositions = try container.decodeIfPresent(Bool.self, forKey: .fixedServerPositions) ?? true
        usThemLabels = try container.decodeIfPresent(Bool.self, forKey: .usThemLabels) ?? true
        // Legacy per-match value is ignored; timeout is always `quickUndoTimeoutSeconds`.
        _ = try container.decodeIfPresent(TimeInterval.self, forKey: .undoTimeoutSeconds)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(setsToWin, forKey: .setsToWin)
        try container.encode(continuousPlay, forKey: .continuousPlay)
        try container.encode(gamesToWinSet, forKey: .gamesToWinSet)
        try container.encode(mustWinByTwoGames, forKey: .mustWinByTwoGames)
        try container.encode(goldenPointEnabled, forKey: .goldenPointEnabled)
        try container.encode(askServeAtSetStart, forKey: .askServeAtSetStart)
        try container.encode(fixedServerPositions, forKey: .fixedServerPositions)
        try container.encode(usThemLabels, forKey: .usThemLabels)
    }
}
