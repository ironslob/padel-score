import Foundation

/// Point display values within a game.
public enum PointDisplay: Equatable, Sendable {
    case love
    case fifteen
    case thirty
    case forty
    case advantage
    case deuce
    case goldenPoint

    public var label: String {
        switch self {
        case .love: return "0"
        case .fifteen: return "15"
        case .thirty: return "30"
        case .forty: return "40"
        case .advantage: return "Ad"
        case .deuce: return "Deuce"
        case .goldenPoint: return "GP"
        }
    }
}

/// Transient notice shown during a tie-break after certain points.
public enum TieBreakNotice: Equatable, Sendable {
    case changeServe
    case changeSides
}

/// Mutable projection of the current game (derived from events).
public struct GameScore: Codable, Sendable, Equatable {
    /// 0 = love, 1 = 15, 2 = 30, 3 = 40 (or tie-break point count when `isTieBreak`)
    public var leftPoints: Int
    public var rightPoints: Int
    public var advantageSide: Side?
    public var isGoldenPointActive: Bool
    public var isTieBreak: Bool
    public var isComplete: Bool
    public var winner: Side?

    public init(
        leftPoints: Int = 0,
        rightPoints: Int = 0,
        advantageSide: Side? = nil,
        isGoldenPointActive: Bool = false,
        isTieBreak: Bool = false,
        isComplete: Bool = false,
        winner: Side? = nil
    ) {
        self.leftPoints = leftPoints
        self.rightPoints = rightPoints
        self.advantageSide = advantageSide
        self.isGoldenPointActive = isGoldenPointActive
        self.isTieBreak = isTieBreak
        self.isComplete = isComplete
        self.winner = winner
    }

    public static let zero = GameScore()

    public func points(for side: Side) -> Int {
        switch side {
        case .left: return leftPoints
        case .right: return rightPoints
        }
    }

    public mutating func setPoints(_ value: Int, for side: Side) {
        switch side {
        case .left: leftPoints = value
        case .right: rightPoints = value
        }
    }

    public var tieBreakTotalPoints: Int {
        leftPoints + rightPoints
    }

    /// Notice to show after the most recent tie-break point, if any.
    public var tieBreakNotice: TieBreakNotice? {
        guard isTieBreak else { return nil }
        let total = tieBreakTotalPoints
        guard total > 0 else { return nil }
        if total % 6 == 0 { return .changeSides }
        if total % 2 == 1 { return .changeServe }
        return nil
    }

    /// Labels for left and right suitable for the score screen.
    public var displayPair: (left: String, right: String) {
        if isComplete {
            return ("0", "0")
        }
        if isTieBreak {
            return (String(leftPoints), String(rightPoints))
        }
        if isGoldenPointActive {
            return ("GP", "GP")
        }
        if let advantageSide {
            switch advantageSide {
            case .left: return ("Ad", "40")
            case .right: return ("40", "Ad")
            }
        }
        if leftPoints >= 3 && rightPoints >= 3 {
            return ("40", "40")
        }
        return (Self.label(for: leftPoints), Self.label(for: rightPoints))
    }

    public var statusLine: String? {
        if isTieBreak {
            return "Tie-break"
        }
        if isGoldenPointActive {
            return "Golden Point"
        }
        if advantageSide != nil {
            return "Advantage"
        }
        if leftPoints >= 3 && rightPoints >= 3 {
            return "Deuce"
        }
        return nil
    }

    private static func label(for points: Int) -> String {
        switch points {
        case 0: return "0"
        case 1: return "15"
        case 2: return "30"
        default: return "40"
        }
    }
}

public struct SetScore: Codable, Sendable, Equatable {
    public var leftGames: Int
    public var rightGames: Int
    public var isComplete: Bool
    public var winner: Side?

    public init(
        leftGames: Int = 0,
        rightGames: Int = 0,
        isComplete: Bool = false,
        winner: Side? = nil
    ) {
        self.leftGames = leftGames
        self.rightGames = rightGames
        self.isComplete = isComplete
        self.winner = winner
    }

    public static let zero = SetScore()

    public func games(for side: Side) -> Int {
        switch side {
        case .left: return leftGames
        case .right: return rightGames
        }
    }

    public mutating func setGames(_ value: Int, for side: Side) {
        switch side {
        case .left: leftGames = value
        case .right: rightGames = value
        }
    }

    public var displayPair: (left: String, right: String) {
        (String(leftGames), String(rightGames))
    }
}

/// Full match record + derived score projection.
public struct MatchState: Codable, Sendable, Equatable, Identifiable {
    public var id: UUID
    public var settings: MatchSettings
    public var status: MatchStatus
    public var events: [MatchEvent]
    public var startedAt: Date
    public var finishedAt: Date?

    // Derived / cached projection
    public var currentGame: GameScore
    public var currentSet: SetScore
    public var completedSets: [SetScore]
    public var leftSetsWon: Int
    public var rightSetsWon: Int
    public var winner: Side?
    public var currentServer: Side?
    public var needsServerSelection: Bool

    public init(
        id: UUID = UUID(),
        settings: MatchSettings = .default,
        status: MatchStatus = .inProgress,
        events: [MatchEvent] = [],
        startedAt: Date = Date(),
        finishedAt: Date? = nil,
        currentGame: GameScore = .zero,
        currentSet: SetScore = .zero,
        completedSets: [SetScore] = [],
        leftSetsWon: Int = 0,
        rightSetsWon: Int = 0,
        winner: Side? = nil,
        currentServer: Side? = nil,
        needsServerSelection: Bool = true
    ) {
        self.id = id
        self.settings = settings
        self.status = status
        self.events = events
        self.startedAt = startedAt
        self.finishedAt = finishedAt
        self.currentGame = currentGame
        self.currentSet = currentSet
        self.completedSets = completedSets
        self.leftSetsWon = leftSetsWon
        self.rightSetsWon = rightSetsWon
        self.winner = winner
        self.currentServer = currentServer
        self.needsServerSelection = needsServerSelection
    }

    public var duration: TimeInterval {
        let end = finishedAt ?? Date()
        return end.timeIntervalSince(startedAt)
    }

    public var hasScoredPoints: Bool {
        events.contains { $0.kind == .pointWon }
    }

    public var lastScoringActivityAt: Date {
        events.last(where: { $0.kind == .pointWon })?.timestamp ?? startedAt
    }

    public func isInactive(at date: Date = Date()) -> Bool {
        guard status == .inProgress else { return false }
        return date.timeIntervalSince(lastScoringActivityAt) >= MatchSettings.inactivityTimeoutSeconds
    }

    public var matchSetsDisplay: (left: String, right: String) {
        (String(leftSetsWon), String(rightSetsWon))
    }

    /// Role labels for the score screen (left / right).
    public var servingRoleLabels: (left: String, right: String) {
        if settings.usThemLabels {
            return ("Us", "Them")
        }
        if settings.fixedServerPositions {
            return ("Serving", "Receiving")
        }
        switch currentServer {
        case .left: return ("Serving", "Receiving")
        case .right: return ("Receiving", "Serving")
        case .none: return ("", "")
        }
    }

    /// Tie-break notice for display, respecting fixed server positions.
    public var activeTieBreakNotice: TieBreakNotice? {
        guard let notice = currentGame.tieBreakNotice else { return nil }
        if settings.fixedServerPositions, notice == .changeServe { return nil }
        return notice
    }

    /// Completed set lines plus the current set if the match is still in progress.
    public var setScoreLines: [String] {
        var lines = completedSets.map { "\($0.leftGames)-\($0.rightGames)" }
        if status == .inProgress || status == .endedEarly {
            if !currentSet.isComplete {
                lines.append("\(currentSet.leftGames)-\(currentSet.rightGames)")
            }
        }
        return lines
    }

    public var finalScoreSummary: String {
        var lines = completedSets.map { "\($0.leftGames)-\($0.rightGames)" }
        if let partialSetLine = partialSetLineForEarlyEnd {
            lines.append(partialSetLine)
        }
        return lines.joined(separator: ", ")
    }

    /// Games in the incomplete set when a match ends early, including the in-progress game if any.
    private var partialSetLineForEarlyEnd: String? {
        guard status == .endedEarly, !currentSet.isComplete else { return nil }
        guard currentSet.leftGames > 0 || currentSet.rightGames > 0 || hasInProgressGameScore else {
            return nil
        }
        var line = "\(currentSet.leftGames)-\(currentSet.rightGames)"
        if let gameScore = inProgressGameScoreLabel {
            line += " (\(gameScore))"
        }
        return line
    }

    private var hasInProgressGameScore: Bool {
        currentGame.leftPoints > 0 || currentGame.rightPoints > 0
            || currentGame.advantageSide != nil || currentGame.isGoldenPointActive
            || currentGame.isTieBreak
    }

    private var inProgressGameScoreLabel: String? {
        guard hasInProgressGameScore else { return nil }
        let pair = currentGame.displayPair
        return "\(pair.left)-\(pair.right)"
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case settings
        case status
        case events
        case startedAt
        case finishedAt
        case currentGame
        case currentSet
        case completedSets
        case leftSetsWon
        case rightSetsWon
        case winner
        case currentServer
        case needsServerSelection
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        settings = try container.decode(MatchSettings.self, forKey: .settings)
        status = try container.decode(MatchStatus.self, forKey: .status)
        events = try container.decode([MatchEvent].self, forKey: .events)
        startedAt = try container.decode(Date.self, forKey: .startedAt)
        finishedAt = try container.decodeIfPresent(Date.self, forKey: .finishedAt)
        currentGame = try container.decodeIfPresent(GameScore.self, forKey: .currentGame) ?? .zero
        currentSet = try container.decodeIfPresent(SetScore.self, forKey: .currentSet) ?? .zero
        completedSets = try container.decodeIfPresent([SetScore].self, forKey: .completedSets) ?? []
        leftSetsWon = try container.decodeIfPresent(Int.self, forKey: .leftSetsWon) ?? 0
        rightSetsWon = try container.decodeIfPresent(Int.self, forKey: .rightSetsWon) ?? 0
        winner = try container.decodeIfPresent(Side.self, forKey: .winner)
        currentServer = try container.decodeIfPresent(Side.self, forKey: .currentServer)
        needsServerSelection = try container.decodeIfPresent(Bool.self, forKey: .needsServerSelection) ?? true
    }
}
