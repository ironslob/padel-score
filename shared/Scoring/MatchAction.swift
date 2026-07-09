import Foundation

/// Actions the scoring engine accepts.
public enum MatchAction: Equatable, Sendable {
    case start(settings: MatchSettings)
    case selectServer(Side)
    case pointWon(Side)
    case undo
    case finish
    case endEarly
    case discard
}
