import Foundation

/// Actions the scoring engine accepts.
public enum MatchAction: Equatable, Sendable {
    case start(settings: MatchSettings)
    case selectServer(Side)
    /// Puts the set in progress back to asking who serves, for when the players
    /// rearranged themselves at the changeover.
    case requestServerSelection
    case pointWon(Side)
    /// Changes how games are decided at 40-40 from now on, without touching games
    /// already played.
    case setDeuceFormat(DeuceFormat)
    case undo
    case finish
    case endEarly
    case discard
}
