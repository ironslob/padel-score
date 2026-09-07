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

/// How a game is resolved once both sides reach 40.
///
/// Declared from most to fewest advantages, which is also the order the picker shows.
public enum DeuceFormat: String, CaseIterable, Codable, Sendable, Identifiable {
    /// Traditional scoring: advantage repeats until one side wins by two points.
    case advantage
    /// Two advantages are played. If the second is broken, the next point decides the
    /// game. The FIP rule for Premier Padel and the CUPRA FIP Tour.
    case starPoint
    /// One advantage is played. If it is broken, the next point decides the game.
    case silverPoint
    /// No advantage at all — the first point at 40-40 decides the game.
    case goldenPoint

    public var id: String { rawValue }

    public var label: String {
        switch self {
        case .advantage: return "Regular"
        case .starPoint: return "Star point"
        case .silverPoint: return "Silver point"
        case .goldenPoint: return "Golden point"
        }
    }

    /// Short name for the decisive point, shown on the score screen.
    public var decidingPointLabel: String {
        switch self {
        case .advantage: return "Deuce"
        case .starPoint: return "Star Point"
        case .silverPoint: return "Silver Point"
        case .goldenPoint: return "Golden Point"
        }
    }

    /// Two-character form for the score readout and complications.
    public var decidingPointShortLabel: String {
        switch self {
        case .advantage: return "40"
        case .starPoint: return "ST"
        case .silverPoint: return "SP"
        case .goldenPoint: return "GP"
        }
    }

    /// How many advantages may be broken before a single point decides the game.
    /// `nil` means there is no cap: regular scoring keeps cycling until someone wins by two.
    public var advantagesBeforeDecidingPoint: Int? {
        switch self {
        case .advantage: return nil
        case .starPoint: return 2
        case .silverPoint: return 1
        case .goldenPoint: return 0
        }
    }

    /// Whether the next point decides the game once `count` advantages have been broken
    /// in the current game. Zero covers arriving at 40-40 with no advantage played yet.
    public func decidesGame(afterBrokenAdvantages count: Int) -> Bool {
        guard let cap = advantagesBeforeDecidingPoint else { return false }
        return count >= cap
    }

    /// Formats that allow more than one advantage number the deuce and advantage
    /// status lines ("Deuce 2", "Advantage 2") so players can see how close the
    /// decisive point is. A single advantage needs no counting.
    public var numbersDeuceCycles: Bool {
        (advantagesBeforeDecidingPoint ?? 0) > 1
    }
}

/// V1 defaults from product.md. `deuceFormat` is a persisted preference on Watch.
public struct MatchSettings: Codable, Sendable, Equatable {
    /// Quick-undo window on the score screen and game interstitial. Not persisted per match.
    public static let quickUndoTimeoutSeconds: TimeInterval = 3

    /// Auto-end or discard an in-progress match after this much time without a new point.
    public static let inactivityTimeoutSeconds: TimeInterval = 30 * 60

    public static let minWarmUpMinutes = 0
    public static let maxWarmUpMinutes = 30
    public static let defaultWarmUpMinutes = 0
    public static let warmUpMinutePresets = [0, 3, 5, 10]

    public static func clampedWarmUpMinutes(_ value: Int) -> Int {
        min(maxWarmUpMinutes, max(minWarmUpMinutes, value))
    }

    public static func warmUpMinutesLabel(_ minutes: Int) -> String {
        let clamped = clampedWarmUpMinutes(minutes)
        return clamped == 0 ? "No limit" : "\(clamped) min"
    }

    public static func nextWarmUpMinutes(after current: Int) -> Int {
        if let index = warmUpMinutePresets.firstIndex(of: current) {
            return warmUpMinutePresets[(index + 1) % warmUpMinutePresets.count]
        }
        return warmUpMinutePresets.first { $0 > current } ?? warmUpMinutePresets[0]
    }

    public var setsToWin: Int
    /// When true, the match keeps going after each set until manually finished.
    public var continuousPlay: Bool
    public var gamesToWinSet: Int
    public var mustWinByTwoGames: Bool
    /// How a game is decided once both sides reach 40.
    public var deuceFormat: DeuceFormat
    /// When true, the player must choose who is serving at the start of each new set.
    public var askServeAtSetStart: Bool
    /// When true, Us/Them stay fixed on the score buttons (UI "Swap sides each game" off).
    /// Controls layout only; serve always rotates per padel rules regardless of this flag.
    public var fixedServerPositions: Bool
    /// When true, score buttons show "Us" / "Them" instead of "Serving" / "Receiving".
    public var usThemLabels: Bool
    /// When true, a timer runs once after Start Match, before "Who's serving?".
    public var warmUpEnabled: Bool
    /// Optional warm-up time limit in minutes. `0` means no limit — the timer runs until Play.
    public var warmUpMinutes: Int

    public init(
        setsToWin: Int = 2,
        continuousPlay: Bool = false,
        gamesToWinSet: Int = 6,
        mustWinByTwoGames: Bool = true,
        deuceFormat: DeuceFormat = .starPoint,
        askServeAtSetStart: Bool = false,
        fixedServerPositions: Bool = true,
        usThemLabels: Bool = true,
        warmUpEnabled: Bool = true,
        warmUpMinutes: Int = MatchSettings.defaultWarmUpMinutes
    ) {
        self.setsToWin = setsToWin
        self.continuousPlay = continuousPlay
        self.gamesToWinSet = gamesToWinSet
        self.mustWinByTwoGames = mustWinByTwoGames
        self.deuceFormat = deuceFormat
        self.askServeAtSetStart = askServeAtSetStart
        self.fixedServerPositions = fixedServerPositions
        self.usThemLabels = usThemLabels
        self.warmUpEnabled = warmUpEnabled
        self.warmUpMinutes = Self.clampedWarmUpMinutes(warmUpMinutes)
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

    public var shouldWarmUp: Bool {
        warmUpEnabled
    }

    public var hasWarmUpLimit: Bool {
        warmUpMinutes > 0
    }

    public var warmUpDuration: TimeInterval {
        TimeInterval(Self.clampedWarmUpMinutes(warmUpMinutes) * 60)
    }

    private enum CodingKeys: String, CodingKey {
        case setsToWin
        case continuousPlay
        case gamesToWinSet
        case mustWinByTwoGames
        case deuceFormat
        /// Pre-silver-point key. Read for migration, still written so older builds
        /// sharing the archive keep scoring these matches the same way.
        case goldenPointEnabled
        case askServeAtSetStart
        case fixedServerPositions
        case usThemLabels
        case warmUpEnabled
        case warmUpMinutes
        case undoTimeoutSeconds
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        setsToWin = try container.decode(Int.self, forKey: .setsToWin)
        continuousPlay = try container.decodeIfPresent(Bool.self, forKey: .continuousPlay) ?? false
        gamesToWinSet = try container.decode(Int.self, forKey: .gamesToWinSet)
        mustWinByTwoGames = try container.decode(Bool.self, forKey: .mustWinByTwoGames)
        if let format = try container.decodeIfPresent(DeuceFormat.self, forKey: .deuceFormat) {
            deuceFormat = format
        } else {
            // Matches written before silver point existed. The old `goldenPointEnabled`
            // flag played one advantage before the decisive point, which is silver
            // point — so map it there to keep archived scorelines faithful to how
            // they were actually played.
            let legacyGoldenPoint = try container.decodeIfPresent(Bool.self, forKey: .goldenPointEnabled) ?? true
            deuceFormat = legacyGoldenPoint ? .silverPoint : .advantage
        }
        askServeAtSetStart = try container.decodeIfPresent(Bool.self, forKey: .askServeAtSetStart) ?? false
        fixedServerPositions = try container.decodeIfPresent(Bool.self, forKey: .fixedServerPositions) ?? true
        usThemLabels = try container.decodeIfPresent(Bool.self, forKey: .usThemLabels) ?? true
        warmUpEnabled = try container.decodeIfPresent(Bool.self, forKey: .warmUpEnabled) ?? false
        let decodedMinutes = try container.decodeIfPresent(Int.self, forKey: .warmUpMinutes)
            ?? MatchSettings.defaultWarmUpMinutes
        warmUpMinutes = Self.clampedWarmUpMinutes(decodedMinutes)
        // Legacy per-match value is ignored; timeout is always `quickUndoTimeoutSeconds`.
        _ = try container.decodeIfPresent(TimeInterval.self, forKey: .undoTimeoutSeconds)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(setsToWin, forKey: .setsToWin)
        try container.encode(continuousPlay, forKey: .continuousPlay)
        try container.encode(gamesToWinSet, forKey: .gamesToWinSet)
        try container.encode(mustWinByTwoGames, forKey: .mustWinByTwoGames)
        try container.encode(deuceFormat, forKey: .deuceFormat)
        // Older builds only know "some deciding point" vs none, so every capped format
        // maps to true there.
        try container.encode(deuceFormat != .advantage, forKey: .goldenPointEnabled)
        try container.encode(askServeAtSetStart, forKey: .askServeAtSetStart)
        try container.encode(fixedServerPositions, forKey: .fixedServerPositions)
        try container.encode(usThemLabels, forKey: .usThemLabels)
        try container.encode(warmUpEnabled, forKey: .warmUpEnabled)
        try container.encode(warmUpMinutes, forKey: .warmUpMinutes)
    }
}
