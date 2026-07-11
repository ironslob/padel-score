import Foundation

/// Stable read-only score projection for complications and glance surfaces.
public struct MatchScoreSnapshot: Codable, Sendable, Equatable {
    public static let storageKey = "matchScoreSnapshot"

    public let gameLeft: String
    public let gameRight: String
    public let setLeft: String
    public let setRight: String
    public let isInProgress: Bool
    public let updatedAt: Date
    public let startedAt: Date?
    public let isGoldenPointActive: Bool
    public let isTieBreak: Bool
    public let gameStatusLine: String?

    enum CodingKeys: String, CodingKey {
        case gameLeft, gameRight, setLeft, setRight, isInProgress, updatedAt
        case startedAt, isGoldenPointActive, isTieBreak, gameStatusLine
    }

    public init(
        gameLeft: String,
        gameRight: String,
        setLeft: String,
        setRight: String,
        isInProgress: Bool,
        updatedAt: Date = Date(),
        startedAt: Date? = nil,
        isGoldenPointActive: Bool = false,
        isTieBreak: Bool = false,
        gameStatusLine: String? = nil
    ) {
        self.gameLeft = gameLeft
        self.gameRight = gameRight
        self.setLeft = setLeft
        self.setRight = setRight
        self.isInProgress = isInProgress
        self.updatedAt = updatedAt
        self.startedAt = startedAt
        self.isGoldenPointActive = isGoldenPointActive
        self.isTieBreak = isTieBreak
        self.gameStatusLine = gameStatusLine
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        gameLeft = try container.decode(String.self, forKey: .gameLeft)
        gameRight = try container.decode(String.self, forKey: .gameRight)
        setLeft = try container.decode(String.self, forKey: .setLeft)
        setRight = try container.decode(String.self, forKey: .setRight)
        isInProgress = try container.decode(Bool.self, forKey: .isInProgress)
        updatedAt = try container.decode(Date.self, forKey: .updatedAt)
        startedAt = try container.decodeIfPresent(Date.self, forKey: .startedAt)
        isGoldenPointActive = try container.decodeIfPresent(Bool.self, forKey: .isGoldenPointActive) ?? false
        isTieBreak = try container.decodeIfPresent(Bool.self, forKey: .isTieBreak) ?? false
        gameStatusLine = try container.decodeIfPresent(String.self, forKey: .gameStatusLine)
    }

    public init(from match: MatchState?) {
        guard let match, match.status == .inProgress else {
            self.init(
                gameLeft: "-",
                gameRight: "-",
                setLeft: "-",
                setRight: "-",
                isInProgress: false
            )
            return
        }
        let game = match.currentGame.displayPair
        let set = match.currentSet.displayPair
        self.init(
            gameLeft: game.left,
            gameRight: game.right,
            setLeft: set.left,
            setRight: set.right,
            isInProgress: true,
            startedAt: match.startedAt,
            isGoldenPointActive: match.currentGame.isGoldenPointActive,
            isTieBreak: match.currentGame.isTieBreak,
            gameStatusLine: match.currentGame.statusLine
        )
    }

    public var gameLabel: String { "\(gameLeft)–\(gameRight)" }
    public var setLabel: String { "\(setLeft)–\(setRight)" }
    public var compactLabel: String {
        isInProgress ? "\(gameLabel) · \(setLabel)" : "No match"
    }

    public func elapsedLabel(at date: Date = Date()) -> String? {
        guard isInProgress, let startedAt else { return nil }
        return DurationFormatter.elapsed(date.timeIntervalSince(startedAt))
    }
}

/// Persists score snapshots for the watch app and complications via app group.
public enum MatchScoreSnapshotStore {
    public static let appGroupID = "group.com.matthewwilson.padelscore"

    public static func save(_ snapshot: MatchScoreSnapshot, defaults: UserDefaults? = nil) {
        let store = defaults ?? UserDefaults(suiteName: appGroupID)
        guard let store else { return }
        if let data = try? JSONEncoder().encode(snapshot) {
            store.set(data, forKey: MatchScoreSnapshot.storageKey)
        }
    }

    public static func load(defaults: UserDefaults? = nil) -> MatchScoreSnapshot? {
        let store = defaults ?? UserDefaults(suiteName: appGroupID)
        guard
            let store,
            let data = store.data(forKey: MatchScoreSnapshot.storageKey),
            let snapshot = try? JSONDecoder().decode(MatchScoreSnapshot.self, from: data)
        else {
            return nil
        }
        return snapshot
    }

    public static func clear(defaults: UserDefaults? = nil) {
        let store = defaults ?? UserDefaults(suiteName: appGroupID)
        guard let store else { return }
        store.removeObject(forKey: MatchScoreSnapshot.storageKey)
    }
}
