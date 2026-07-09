import Foundation

/// V1 defaults from product.md — not user-configurable yet.
public struct MatchSettings: Codable, Sendable, Equatable {
    public var setsToWin: Int
    public var gamesToWinSet: Int
    public var mustWinByTwoGames: Bool
    public var goldenPointEnabled: Bool
    public var undoTimeoutSeconds: TimeInterval

    public init(
        setsToWin: Int = 2,
        gamesToWinSet: Int = 6,
        mustWinByTwoGames: Bool = true,
        goldenPointEnabled: Bool = true,
        undoTimeoutSeconds: TimeInterval = 3
    ) {
        self.setsToWin = setsToWin
        self.gamesToWinSet = gamesToWinSet
        self.mustWinByTwoGames = mustWinByTwoGames
        self.goldenPointEnabled = goldenPointEnabled
        self.undoTimeoutSeconds = undoTimeoutSeconds
    }

    public static let `default` = MatchSettings()
}
