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

    public init(
        gameLeft: String,
        gameRight: String,
        setLeft: String,
        setRight: String,
        isInProgress: Bool,
        updatedAt: Date = Date()
    ) {
        self.gameLeft = gameLeft
        self.gameRight = gameRight
        self.setLeft = setLeft
        self.setRight = setRight
        self.isInProgress = isInProgress
        self.updatedAt = updatedAt
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
            isInProgress: true
        )
    }

    public var gameLabel: String { "\(gameLeft)–\(gameRight)" }
    public var setLabel: String { "\(setLeft)–\(setRight)" }
    public var compactLabel: String {
        isInProgress ? "\(gameLabel) · \(setLabel)" : "No match"
    }
}

/// Persists score snapshots for the watch app and complications via app group.
public enum MatchScoreSnapshotStore {
    public static let appGroupID = "group.com.matthewwilson.padelscore"

    public static func save(_ snapshot: MatchScoreSnapshot) {
        guard let defaults = UserDefaults(suiteName: appGroupID) else { return }
        if let data = try? JSONEncoder().encode(snapshot) {
            defaults.set(data, forKey: MatchScoreSnapshot.storageKey)
        }
    }

    public static func load() -> MatchScoreSnapshot? {
        guard
            let defaults = UserDefaults(suiteName: appGroupID),
            let data = defaults.data(forKey: MatchScoreSnapshot.storageKey),
            let snapshot = try? JSONDecoder().decode(MatchScoreSnapshot.self, from: data)
        else {
            return nil
        }
        return snapshot
    }

    public static func clear() {
        guard let defaults = UserDefaults(suiteName: appGroupID) else { return }
        defaults.removeObject(forKey: MatchScoreSnapshot.storageKey)
    }
}
