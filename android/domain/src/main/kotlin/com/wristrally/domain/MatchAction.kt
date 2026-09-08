package com.wristrally.domain

/** Actions the scoring engine accepts. */
sealed class MatchAction {
    data class Start(val settings: MatchSettings) : MatchAction()
    data class SelectServer(val side: Side) : MatchAction()

    /** Puts the set in progress back to asking who serves. */
    data object RequestServerSelection : MatchAction()

    /** Ends the pre-match warm-up so the player can choose who serves. */
    data object CompleteWarmUp : MatchAction()
    data class PointWon(val side: Side) : MatchAction()

    /** Changes how games are decided at 40-40 from now on. */
    data class SetDeuceFormat(val format: DeuceFormat) : MatchAction()
    data object Undo : MatchAction()
    data object Finish : MatchAction()
    data object EndEarly : MatchAction()
    data object Discard : MatchAction()
}

sealed class ScoringError : Exception() {
    data object MatchNotInProgress : ScoringError()
    data object NothingToUndo : ScoringError()
    data object MatchAlreadyStarted : ScoringError()
    data object InvalidAction : ScoringError()
}
