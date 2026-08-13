import Foundation

public enum ScoringError: Error, Equatable, Sendable {
    case matchNotInProgress
    case nothingToUndo
    case matchAlreadyStarted
    case invalidAction
}

/// Pure scoring state machine. No UI, persistence, or networking dependencies.
public struct ScoringEngine: Sendable {
    public init() {}

    /// Creates a new in-progress match.
    public func startMatch(
        settings: MatchSettings = .default,
        id: UUID = UUID(),
        at date: Date = Date()
    ) -> MatchState {
        let event = MatchEvent.matchStarted(at: date)
        return MatchState(
            id: id,
            settings: settings,
            status: .inProgress,
            events: [event],
            startedAt: date,
            currentServer: nil,
            needsServerSelection: true
        )
    }

    /// Applies a single action to the current state.
    public func apply(_ action: MatchAction, to state: MatchState, at date: Date = Date()) throws -> MatchState {
        switch action {
        case .start:
            throw ScoringError.matchAlreadyStarted

        case .selectServer(let side):
            guard state.status == .inProgress else { throw ScoringError.matchNotInProgress }
            guard state.needsServerSelection else { throw ScoringError.invalidAction }
            var next = state
            next.events.append(.serverSelected(side, at: date))
            return replay(events: next.events, onto: blankMatch(from: next))

        case .requestServerSelection:
            guard state.status == .inProgress else { throw ScoringError.matchNotInProgress }
            guard state.isAtSetStart else { throw ScoringError.invalidAction }
            guard !state.needsServerSelection else { return state }
            // No event is recorded: the choice that follows is the fact worth keeping,
            // and replay re-derives the prompt from where the set boundary falls.
            var next = state
            next.currentServer = nil
            next.needsServerSelection = true
            return next

        case .pointWon(let side):
            guard state.status == .inProgress else { throw ScoringError.matchNotInProgress }
            guard !state.needsServerSelection else { throw ScoringError.invalidAction }
            var next = state
            next.events.append(.pointWon(side, at: date))
            var result = replay(events: next.events, onto: blankMatch(from: next))
            if result.status == .completed {
                result.finishedAt = date
                if result.events.last?.kind != .matchFinished {
                    result.events.append(.matchFinished(at: date))
                }
            }
            return result

        case .setDeuceFormat(let format):
            guard state.status == .inProgress else { throw ScoringError.matchNotInProgress }
            guard state.settings.deuceFormat != format else { return state }
            var next = state
            if next.deuceFormatChanges.isEmpty {
                // Open the history with what the match has been played under so far.
                next.deuceFormatChanges.append(
                    DeuceFormatChange(format: next.settings.deuceFormat, at: next.startedAt)
                )
            }
            // Never let a slow clock place the change before a point that has already
            // been scored under the old format.
            let effective = max(date, next.events.last?.timestamp ?? date)
            next.deuceFormatChanges.append(DeuceFormatChange(format: format, at: effective))
            next.settings.deuceFormat = format
            let replayed = replay(events: next.events, onto: blankMatch(from: next))
            // New Serve is not an event; replay would restore the rotated server.
            return restoreServerSelectionPrompt(from: state, onto: replayed)

        case .undo:
            guard state.status == .inProgress else { throw ScoringError.matchNotInProgress }
            guard let index = state.events.lastIndex(where: { $0.kind == .pointWon }) else {
                throw ScoringError.nothingToUndo
            }
            var events = state.events
            events.remove(at: index)
            return replay(events: events, onto: blankMatch(from: state))

        case .finish:
            guard state.status == .inProgress else { throw ScoringError.matchNotInProgress }
            var next = state
            if let winner = naturalWinner(of: state) {
                next.winner = winner
                next.status = .completed
            } else {
                next.status = .endedEarly
            }
            next.finishedAt = date
            next.events.append(.matchFinished(at: date))
            return next

        case .endEarly:
            guard state.status == .inProgress else { throw ScoringError.matchNotInProgress }
            var next = state
            next.status = .endedEarly
            next.finishedAt = date
            next.events.append(.matchEndedEarly(at: date))
            return next

        case .discard:
            guard state.status == .inProgress else { throw ScoringError.matchNotInProgress }
            var next = state
            next.status = .discarded
            next.finishedAt = date
            next.events.append(.matchDiscarded(at: date))
            return next
        }
    }

    /// Rebuilds derived fields from the event stream after a load.
    /// Keeps an in-progress New Serve prompt, which is not itself an event.
    public func rehydrate(_ state: MatchState) -> MatchState {
        let replayed = replay(events: state.events, onto: blankMatch(from: state))
        return restoreServerSelectionPrompt(from: state, onto: replayed)
    }

    /// Rebuilds derived score state from the authoritative event stream.
    public func replay(events: [MatchEvent], onto base: MatchState) -> MatchState {
        var state = base
        state.events = []
        state.currentGame = .zero
        state.currentSet = .zero
        state.completedSets = []
        state.leftSetsWon = 0
        state.rightSetsWon = 0
        state.winner = nil
        state.currentServer = nil
        state.needsServerSelection = true
        state.finishedAt = nil
        state.status = .inProgress

        // Deuce format in force, which mid-match changes move along as replay reaches
        // the point they were made at. With no changes recorded it never moves.
        var pendingFormatChanges = base.deuceFormatChanges.sorted { $0.at < $1.at }
        var deuceFormat = pendingFormatChanges.first?.format ?? base.settings.deuceFormat

        for event in events {
            while let change = pendingFormatChanges.first, change.at < event.timestamp {
                deuceFormat = change.format
                applyDeuceFormat(deuceFormat, to: &state)
                pendingFormatChanges.removeFirst()
            }
            state.events.append(event)
            switch event.kind {
            case .matchStarted:
                state.startedAt = event.timestamp
                state.status = .inProgress
                state.needsServerSelection = true

            case .serverSelected:
                guard let side = event.side, state.status == .inProgress else { continue }
                // A choice made at a set boundary counts even though the match was not
                // waiting for one, because the changeover offers it. Anywhere else the
                // event is stale — an undo has moved the set boundary out from under it.
                guard state.needsServerSelection || state.isAtSetStart else { continue }
                state.currentServer = side
                state.needsServerSelection = false

            case .pointWon:
                guard let side = event.side, state.status == .inProgress else { continue }
                awardPoint(to: side, in: &state, deuceFormat: deuceFormat)

            case .matchFinished:
                state.finishedAt = event.timestamp
                if let winner = naturalWinner(of: state) {
                    state.status = .completed
                    state.winner = winner
                } else {
                    state.status = .endedEarly
                }

            case .matchEndedEarly:
                state.status = .endedEarly
                state.finishedAt = event.timestamp

            case .matchDiscarded:
                state.status = .discarded
                state.finishedAt = event.timestamp
            }
        }

        // A change made after the last point still has to arm (or disarm) the game in
        // progress, otherwise the next point would be scored under the old rule.
        for change in pendingFormatChanges {
            applyDeuceFormat(change.format, to: &state)
        }

        return state
    }

    /// Brings the game in progress into line with a deuce format chosen mid-match.
    /// Completed games are left alone: they keep the result they were played for.
    private func applyDeuceFormat(_ format: DeuceFormat, to state: inout MatchState) {
        guard state.status == .inProgress,
              !state.currentGame.isComplete,
              !state.currentGame.isTieBreak,
              state.currentGame.leftPoints >= 3,
              state.currentGame.rightPoints >= 3
        else { return }

        switch format {
        case .goldenPoint:
            // Golden point has no advantage phase, so an advantage already held is
            // given up and the next rally decides the game.
            state.currentGame.advantageSide = nil
            state.currentGame.isGoldenPointActive = true
        case .silverPoint, .advantage:
            // A pending decisive rally stops being decisive; under silver point the
            // single advantage it allows is still to be played.
            state.currentGame.isGoldenPointActive = false
        }
    }

    // MARK: - Point / game / set / match progression

    private func awardPoint(to side: Side, in state: inout MatchState, deuceFormat: DeuceFormat) {
        guard !state.currentGame.isComplete, state.status == .inProgress else { return }

        if state.currentGame.isTieBreak {
            awardTieBreakPoint(to: side, in: &state)
            return
        }

        // A decisive point is live: this rally ends the game either way.
        if state.currentGame.isGoldenPointActive {
            completeGame(winner: side, in: &state)
            return
        }

        let myPoints = state.currentGame.points(for: side)
        let theirPoints = state.currentGame.points(for: side.opposite)

        // Deuce territory (both at 40+). Golden point never reaches here — it makes
        // the point decisive the moment the game arrives at 40-40, below.
        if myPoints >= 3 && theirPoints >= 3 {
            if state.currentGame.advantageSide == nil {
                state.currentGame.advantageSide = side
            } else if state.currentGame.advantageSide == side {
                completeGame(winner: side, in: &state)
            } else {
                // Advantage broken → back to deuce. Silver point allows exactly one
                // advantage, so the next point decides; regular scoring keeps cycling.
                state.currentGame.advantageSide = nil
                state.currentGame.isGoldenPointActive = deuceFormat == .silverPoint
            }
            return
        }

        // Already at 40 with opponent below 40 → game
        if myPoints >= 3 && theirPoints < 3 {
            completeGame(winner: side, in: &state)
            return
        }

        state.currentGame.setPoints(myPoints + 1, for: side)

        // Golden point: no advantage phase at all, so reaching 40-40 makes the very
        // next rally decisive.
        if deuceFormat == .goldenPoint,
           state.currentGame.leftPoints >= 3,
           state.currentGame.rightPoints >= 3 {
            state.currentGame.isGoldenPointActive = true
        }
    }

    private func awardTieBreakPoint(to side: Side, in state: inout MatchState) {
        let myPoints = state.currentGame.points(for: side)
        state.currentGame.setPoints(myPoints + 1, for: side)

        if state.currentGame.tieBreakTotalPoints % 2 == 1 {
            state.currentServer = state.currentServer?.opposite
        }

        let theirPoints = state.currentGame.points(for: side.opposite)
        if myPoints + 1 >= 7 && (myPoints + 1) - theirPoints >= 2 {
            completeTieBreak(winner: side, in: &state)
        }
    }

    private func completeTieBreak(winner: Side, in state: inout MatchState) {
        state.currentGame.isComplete = true
        state.currentGame.winner = winner
        state.currentSet.setGames(7, for: winner)
        // The side that opened the tie-break receives first in the next set, so
        // serve keeps rotating as if the tie-break were a single game.
        let nextSetServer = tieBreakOpeningServer(in: state)?.opposite
        completeSet(winner: winner, in: &state, nextSetServer: nextSetServer)
    }

    /// The side that served the opening point of the tie-break in progress.
    /// Serve flips after every odd-numbered point, so the opening server follows
    /// from the current server and how many flips have happened.
    private func tieBreakOpeningServer(in state: MatchState) -> Side? {
        guard let server = state.currentServer else { return nil }
        let flips = (state.currentGame.tieBreakTotalPoints + 1) / 2
        return flips.isMultiple(of: 2) ? server : server.opposite
    }

    private func completeGame(winner: Side, in state: inout MatchState) {
        state.currentGame.isComplete = true
        state.currentGame.winner = winner
        state.currentGame.advantageSide = nil
        state.currentGame.isGoldenPointActive = false

        let games = state.currentSet.games(for: winner) + 1
        state.currentSet.setGames(games, for: winner)

        // Serve rotates after every completed game, including the one that ends a
        // set and the one that sends the set to a tie-break.
        let nextServer = state.currentServer?.opposite

        if state.currentSet.leftGames == 6 && state.currentSet.rightGames == 6 {
            state.currentServer = nextServer
            state.currentGame = GameScore(isTieBreak: true)
            return
        }

        if isSetWon(by: winner, set: state.currentSet, settings: state.settings) {
            completeSet(winner: winner, in: &state, nextSetServer: nextServer)
        } else {
            state.currentServer = nextServer
            state.currentGame = .zero
        }
    }

    private func isSetWon(by side: Side, set: SetScore, settings: MatchSettings) -> Bool {
        let my = set.games(for: side)
        let their = set.games(for: side.opposite)
        guard my >= settings.gamesToWinSet else { return false }
        if settings.mustWinByTwoGames {
            return my - their >= 2
        }
        return true
    }

    private func completeSet(winner: Side, in state: inout MatchState, nextSetServer: Side?) {
        state.currentSet.isComplete = true
        state.currentSet.winner = winner
        state.completedSets.append(state.currentSet)

        switch winner {
        case .left: state.leftSetsWon += 1
        case .right: state.rightSetsWon += 1
        }

        if state.settings.continuousPlay {
            state.currentSet = .zero
            state.currentGame = .zero
            beginNextSetServe(nextSetServer, in: &state)
        } else if state.leftSetsWon >= state.settings.setsToWin {
            state.winner = .left
            state.status = .completed
            state.finishedAt = state.events.last?.timestamp
            state.currentGame = .zero
        } else if state.rightSetsWon >= state.settings.setsToWin {
            state.winner = .right
            state.status = .completed
            state.finishedAt = state.events.last?.timestamp
            state.currentGame = .zero
        } else {
            state.currentSet = .zero
            state.currentGame = .zero
            beginNextSetServe(nextSetServer, in: &state)
        }
    }

    /// `requestServerSelection` records no event, so replay restores the rotated
    /// server. Re-apply the prompt when the set is still untouched.
    private func restoreServerSelectionPrompt(from previous: MatchState, onto replayed: MatchState) -> MatchState {
        guard previous.status == .inProgress,
              previous.needsServerSelection,
              replayed.status == .inProgress,
              replayed.isAtSetStart
        else { return replayed }
        var next = replayed
        next.currentServer = nil
        next.needsServerSelection = true
        return next
    }

    /// Carries serve rotation into the new set, unless the player opted to be
    /// asked who serves at the start of each set.
    private func beginNextSetServe(_ nextSetServer: Side?, in state: inout MatchState) {
        if state.settings.askServeAtSetStart {
            state.currentServer = nil
            state.needsServerSelection = true
        } else {
            state.currentServer = nextSetServer
        }
    }

    private func naturalWinner(of state: MatchState) -> Side? {
        if state.settings.continuousPlay {
            if state.leftSetsWon > state.rightSetsWon { return .left }
            if state.rightSetsWon > state.leftSetsWon { return .right }
            return nil
        }
        if state.leftSetsWon >= state.settings.setsToWin { return .left }
        if state.rightSetsWon >= state.settings.setsToWin { return .right }
        return state.winner
    }

    private func blankMatch(from state: MatchState) -> MatchState {
        MatchState(
            id: state.id,
            settings: state.settings,
            status: .inProgress,
            events: [],
            deuceFormatChanges: state.deuceFormatChanges,
            startedAt: state.startedAt
        )
    }
}
