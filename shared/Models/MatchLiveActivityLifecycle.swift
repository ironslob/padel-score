import Foundation

public enum MatchLiveActivityAction: Equatable {
    case start(MatchState)
    case update(MatchState)
    case end(dismissImmediately: Bool)
}

/// Pure lifecycle rules for mirroring an active match to a Live Activity.
public enum MatchLiveActivityLifecycle {
    public static func action(
        previousMatchID: UUID?,
        match: MatchState?
    ) -> MatchLiveActivityAction? {
        guard let match else {
            guard previousMatchID != nil else { return nil }
            return .end(dismissImmediately: true)
        }

        switch match.status {
        case .inProgress:
            if previousMatchID == match.id {
                return .update(match)
            }
            return .start(match)
        case .completed, .endedEarly:
            return .end(dismissImmediately: false)
        case .discarded:
            return .end(dismissImmediately: true)
        }
    }
}

#if os(iOS)
import ActivityKit

public struct MatchActivityAttributes: ActivityAttributes {
    public struct ContentState: Codable, Hashable {
        public let gameLeft: String
        public let gameRight: String
        public let setLeft: String
        public let setRight: String
        public let startedAt: Date

        public init(from match: MatchState) {
            let game = match.currentGame.displayPair
            let set = match.currentSet.displayPair
            gameLeft = game.left
            gameRight = game.right
            setLeft = set.left
            setRight = set.right
            startedAt = match.startedAt
        }
    }

    public let matchID: UUID

    public init(matchID: UUID) {
        self.matchID = matchID
    }
}
#endif
