package com.padelscore.domain

import java.time.Instant
import java.util.UUID

/** Pure scoring state machine. No UI, persistence, or networking dependencies. */
class ScoringEngine {
    fun startMatch(
        settings: MatchSettings = MatchSettings(),
        id: UUID = UUID.randomUUID(),
        at: Instant = Instant.now(),
    ): MatchState {
        val event = MatchEvent.matchStarted(at)
        return MatchState(
            id = id,
            settings = settings,
            status = MatchStatus.InProgress,
            events = listOf(event),
            startedAt = at,
            currentServer = null,
            needsServerSelection = true,
            needsWarmUp = settings.shouldWarmUp,
        )
    }

    fun apply(action: MatchAction, state: MatchState, at: Instant = Instant.now()): MatchState {
        when (action) {
            is MatchAction.Start -> throw ScoringError.MatchAlreadyStarted

            is MatchAction.SelectServer -> {
                if (state.status != MatchStatus.InProgress) throw ScoringError.MatchNotInProgress
                if (!state.needsServerSelection) throw ScoringError.InvalidAction
                val next = state.deepCopy()
                next.events = next.events + MatchEvent.serverSelected(action.side, at)
                return replay(next.events, blankMatch(next))
            }

            MatchAction.RequestServerSelection -> {
                if (state.status != MatchStatus.InProgress) throw ScoringError.MatchNotInProgress
                if (!state.isAtSetStart) throw ScoringError.InvalidAction
                if (state.needsServerSelection) return state
                val next = state.deepCopy()
                next.currentServer = null
                next.needsServerSelection = true
                return next
            }

            MatchAction.CompleteWarmUp -> {
                if (state.status != MatchStatus.InProgress) throw ScoringError.MatchNotInProgress
                if (!state.needsWarmUp) return state
                if (!state.isWaitingForFirstServe) return state
                val warmed = state.deepCopy()
                warmed.needsWarmUp = false
                return warmed
            }

            is MatchAction.PointWon -> {
                if (state.status != MatchStatus.InProgress) throw ScoringError.MatchNotInProgress
                if (state.needsServerSelection) throw ScoringError.InvalidAction
                val next = state.deepCopy()
                next.events = next.events + MatchEvent.pointWon(action.side, at)
                val result = replay(next.events, blankMatch(next))
                if (result.status == MatchStatus.Completed) {
                    result.finishedAt = at
                    if (result.events.lastOrNull()?.kind != MatchEventKind.MatchFinished) {
                        result.events = result.events + MatchEvent.matchFinished(at)
                    }
                }
                return result
            }

            is MatchAction.SetDeuceFormat -> {
                if (state.status != MatchStatus.InProgress) throw ScoringError.MatchNotInProgress
                if (state.settings.deuceFormat == action.format) return state
                val next = state.deepCopy()
                if (next.deuceFormatChanges.isEmpty()) {
                    next.deuceFormatChanges = listOf(
                        DeuceFormatChange(format = next.settings.deuceFormat, at = next.startedAt),
                    )
                }
                val lastEventAt = next.events.lastOrNull()?.timestamp ?: at
                val effective = maxOf(at, lastEventAt)
                next.deuceFormatChanges = next.deuceFormatChanges +
                    DeuceFormatChange(format = action.format, at = effective)
                next.settings = next.settings.copy(deuceFormat = action.format)
                val replayed = replay(next.events, blankMatch(next))
                return restoreWarmUp(
                    from = state,
                    onto = restoreServerSelectionPrompt(from = state, onto = replayed),
                )
            }

            MatchAction.Undo -> {
                if (state.status != MatchStatus.InProgress) throw ScoringError.MatchNotInProgress
                val index = state.events.indexOfLast { it.kind == MatchEventKind.PointWon }
                if (index < 0) throw ScoringError.NothingToUndo
                val events = state.events.toMutableList().also { it.removeAt(index) }
                return replay(events, blankMatch(state))
            }

            MatchAction.Finish -> {
                if (state.status != MatchStatus.InProgress) throw ScoringError.MatchNotInProgress
                val next = state.deepCopy()
                val winner = naturalWinner(next)
                if (winner != null) {
                    next.winner = winner
                    next.status = MatchStatus.Completed
                } else {
                    next.status = MatchStatus.EndedEarly
                }
                next.finishedAt = at
                next.events = next.events + MatchEvent.matchFinished(at)
                return next
            }

            MatchAction.EndEarly -> {
                if (state.status != MatchStatus.InProgress) throw ScoringError.MatchNotInProgress
                val next = state.deepCopy()
                next.status = MatchStatus.EndedEarly
                next.finishedAt = at
                next.events = next.events + MatchEvent.matchEndedEarly(at)
                return next
            }

            MatchAction.Discard -> {
                if (state.status != MatchStatus.InProgress) throw ScoringError.MatchNotInProgress
                val next = state.deepCopy()
                next.status = MatchStatus.Discarded
                next.finishedAt = at
                next.events = next.events + MatchEvent.matchDiscarded(at)
                return next
            }
        }
    }

    fun rehydrate(state: MatchState): MatchState {
        val replayed = replay(state.events, blankMatch(state))
        val withServe = restoreServerSelectionPrompt(from = state, onto = replayed)
        return restoreWarmUp(from = state, onto = withServe)
    }

    fun replay(events: List<MatchEvent>, base: MatchState): MatchState {
        val state = blankMatch(base)
        state.events = emptyList()
        state.currentGame = GameScore()
        state.currentSet = SetScore()
        state.completedSets = emptyList()
        state.leftSetsWon = 0
        state.rightSetsWon = 0
        state.winner = null
        state.currentServer = null
        state.needsServerSelection = true
        state.finishedAt = null
        state.status = MatchStatus.InProgress

        val pendingFormatChanges = base.deuceFormatChanges.sortedBy { it.at }.toMutableList()
        var deuceFormat = pendingFormatChanges.firstOrNull()?.format ?: base.settings.deuceFormat

        for (event in events) {
            while (pendingFormatChanges.isNotEmpty() && pendingFormatChanges.first().at < event.timestamp) {
                deuceFormat = pendingFormatChanges.first().format
                applyDeuceFormat(deuceFormat, state)
                pendingFormatChanges.removeAt(0)
            }
            state.events = state.events + event
            when (event.kind) {
                MatchEventKind.MatchStarted -> {
                    state.startedAt = event.timestamp
                    state.status = MatchStatus.InProgress
                    state.needsServerSelection = true
                }

                MatchEventKind.ServerSelected -> {
                    val side = event.side
                    if (side == null || state.status != MatchStatus.InProgress) continue
                    if (!(state.needsServerSelection || state.isAtSetStart)) continue
                    state.currentServer = side
                    state.needsServerSelection = false
                }

                MatchEventKind.PointWon -> {
                    val side = event.side
                    if (side == null || state.status != MatchStatus.InProgress) continue
                    awardPoint(side, state, deuceFormat)
                }

                MatchEventKind.MatchFinished -> {
                    state.finishedAt = event.timestamp
                    val winner = naturalWinner(state)
                    if (winner != null) {
                        state.status = MatchStatus.Completed
                        state.winner = winner
                    } else {
                        state.status = MatchStatus.EndedEarly
                    }
                }

                MatchEventKind.MatchEndedEarly -> {
                    state.status = MatchStatus.EndedEarly
                    state.finishedAt = event.timestamp
                }

                MatchEventKind.MatchDiscarded -> {
                    state.status = MatchStatus.Discarded
                    state.finishedAt = event.timestamp
                }
            }
        }

        for (change in pendingFormatChanges) {
            applyDeuceFormat(change.format, state)
        }

        return state
    }

    private fun applyDeuceFormat(format: DeuceFormat, state: MatchState) {
        if (state.status != MatchStatus.InProgress) return
        if (state.currentGame.isComplete) return
        if (state.currentGame.isTieBreak) return
        if (state.currentGame.leftPoints < 3 || state.currentGame.rightPoints < 3) return

        when (format) {
            DeuceFormat.GoldenPoint -> {
                state.currentGame.advantageSide = null
                state.currentGame.isGoldenPointActive = true
            }
            DeuceFormat.SilverPoint, DeuceFormat.Advantage -> {
                state.currentGame.isGoldenPointActive = false
            }
        }
    }

    private fun awardPoint(side: Side, state: MatchState, deuceFormat: DeuceFormat) {
        if (state.currentGame.isComplete || state.status != MatchStatus.InProgress) return

        if (state.currentGame.isTieBreak) {
            awardTieBreakPoint(side, state)
            return
        }

        if (state.currentGame.isGoldenPointActive) {
            completeGame(side, state)
            return
        }

        val myPoints = state.currentGame.points(side)
        val theirPoints = state.currentGame.points(side.opposite)

        if (myPoints >= 3 && theirPoints >= 3) {
            when {
                state.currentGame.advantageSide == null -> {
                    state.currentGame.advantageSide = side
                }
                state.currentGame.advantageSide == side -> {
                    completeGame(side, state)
                }
                else -> {
                    state.currentGame.advantageSide = null
                    state.currentGame.isGoldenPointActive = deuceFormat == DeuceFormat.SilverPoint
                }
            }
            return
        }

        if (myPoints >= 3 && theirPoints < 3) {
            completeGame(side, state)
            return
        }

        state.currentGame.setPoints(myPoints + 1, side)

        if (deuceFormat == DeuceFormat.GoldenPoint &&
            state.currentGame.leftPoints >= 3 &&
            state.currentGame.rightPoints >= 3
        ) {
            state.currentGame.isGoldenPointActive = true
        }
    }

    private fun awardTieBreakPoint(side: Side, state: MatchState) {
        val myPoints = state.currentGame.points(side)
        state.currentGame.setPoints(myPoints + 1, side)

        if (state.currentGame.tieBreakTotalPoints % 2 == 1) {
            state.currentServer = state.currentServer?.opposite
        }

        val theirPoints = state.currentGame.points(side.opposite)
        if (myPoints + 1 >= 7 && (myPoints + 1) - theirPoints >= 2) {
            completeTieBreak(side, state)
        }
    }

    private fun completeTieBreak(winner: Side, state: MatchState) {
        state.currentGame.isComplete = true
        state.currentGame.winner = winner
        state.currentSet.setGames(7, winner)
        val nextSetServer = tieBreakOpeningServer(state)?.opposite
        completeSet(winner, state, nextSetServer)
    }

    private fun tieBreakOpeningServer(state: MatchState): Side? {
        val server = state.currentServer ?: return null
        val flips = (state.currentGame.tieBreakTotalPoints + 1) / 2
        return if (flips % 2 == 0) server else server.opposite
    }

    private fun completeGame(winner: Side, state: MatchState) {
        state.currentGame.isComplete = true
        state.currentGame.winner = winner
        state.currentGame.advantageSide = null
        state.currentGame.isGoldenPointActive = false

        val games = state.currentSet.games(winner) + 1
        state.currentSet.setGames(games, winner)

        val nextServer = state.currentServer?.opposite

        if (state.currentSet.leftGames == 6 && state.currentSet.rightGames == 6) {
            state.currentServer = nextServer
            state.currentGame = GameScore(isTieBreak = true)
            return
        }

        if (isSetWon(winner, state.currentSet, state.settings)) {
            completeSet(winner, state, nextServer)
        } else {
            state.currentServer = nextServer
            state.currentGame = GameScore()
        }
    }

    private fun isSetWon(side: Side, set: SetScore, settings: MatchSettings): Boolean {
        val mine = set.games(side)
        val theirs = set.games(side.opposite)
        if (mine < settings.gamesToWinSet) return false
        return if (settings.mustWinByTwoGames) mine - theirs >= 2 else true
    }

    private fun completeSet(winner: Side, state: MatchState, nextSetServer: Side?) {
        state.currentSet.isComplete = true
        state.currentSet.winner = winner
        state.completedSets = state.completedSets + state.currentSet.copy()

        when (winner) {
            Side.Left -> state.leftSetsWon += 1
            Side.Right -> state.rightSetsWon += 1
        }

        if (state.settings.continuousPlay) {
            state.currentSet = SetScore()
            state.currentGame = GameScore()
            beginNextSetServe(nextSetServer, state)
        } else if (state.leftSetsWon >= state.settings.setsToWin) {
            state.winner = Side.Left
            state.status = MatchStatus.Completed
            state.finishedAt = state.events.lastOrNull()?.timestamp
            state.currentGame = GameScore()
        } else if (state.rightSetsWon >= state.settings.setsToWin) {
            state.winner = Side.Right
            state.status = MatchStatus.Completed
            state.finishedAt = state.events.lastOrNull()?.timestamp
            state.currentGame = GameScore()
        } else {
            state.currentSet = SetScore()
            state.currentGame = GameScore()
            beginNextSetServe(nextSetServer, state)
        }
    }

    private fun restoreServerSelectionPrompt(from: MatchState, onto: MatchState): MatchState {
        if (from.status != MatchStatus.InProgress) return onto
        if (!from.needsServerSelection) return onto
        if (onto.status != MatchStatus.InProgress) return onto
        if (!onto.isAtSetStart) return onto
        val next = onto.deepCopy()
        next.currentServer = null
        next.needsServerSelection = true
        return next
    }

    private fun restoreWarmUp(from: MatchState, onto: MatchState): MatchState {
        if (from.status != MatchStatus.InProgress) return onto
        if (!from.needsWarmUp) return onto
        if (onto.status != MatchStatus.InProgress) return onto
        if (!onto.isWaitingForFirstServe) return onto
        val next = onto.deepCopy()
        next.needsWarmUp = true
        return next
    }

    private fun beginNextSetServe(nextSetServer: Side?, state: MatchState) {
        if (state.settings.askServeAtSetStart) {
            state.currentServer = null
            state.needsServerSelection = true
        } else {
            state.currentServer = nextSetServer
        }
    }

    private fun naturalWinner(state: MatchState): Side? {
        if (state.settings.continuousPlay) {
            if (state.leftSetsWon > state.rightSetsWon) return Side.Left
            if (state.rightSetsWon > state.leftSetsWon) return Side.Right
            return null
        }
        if (state.leftSetsWon >= state.settings.setsToWin) return Side.Left
        if (state.rightSetsWon >= state.settings.setsToWin) return Side.Right
        return state.winner
    }

    private fun blankMatch(from: MatchState): MatchState = MatchState(
        id = from.id,
        settings = from.settings.copy(),
        status = MatchStatus.InProgress,
        events = emptyList(),
        deuceFormatChanges = from.deuceFormatChanges.toList(),
        startedAt = from.startedAt,
    )
}
