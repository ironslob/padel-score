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
            currentServer: settings.fixedServerPositions ? .left : nil,
            needsServerSelection: !settings.fixedServerPositions
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
            }
            next.status = .completed
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
        state.needsServerSelection = !state.settings.fixedServerPositions
        state.finishedAt = nil
        state.status = .inProgress

        for event in events {
            state.events.append(event)
            switch event.kind {
            case .matchStarted:
                state.startedAt = event.timestamp
                state.status = .inProgress
                if state.settings.fixedServerPositions {
                    state.currentServer = .left
                    state.needsServerSelection = false
                } else {
                    state.needsServerSelection = true
                }

            case .serverSelected:
                guard let side = event.side, state.status == .inProgress, state.needsServerSelection else { continue }
                state.currentServer = side
                state.needsServerSelection = false

            case .pointWon:
                guard let side = event.side, state.status == .inProgress else { continue }
                awardPoint(to: side, in: &state)

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

        return state
    }

    // MARK: - Point / game / set / match progression

    private func awardPoint(to side: Side, in state: inout MatchState) {
        guard !state.currentGame.isComplete, state.status == .inProgress else { return }

        if state.currentGame.isTieBreak {
            awardTieBreakPoint(to: side, in: &state)
            return
        }

        if state.currentGame.isGoldenPointActive {
            completeGame(winner: side, in: &state)
            return
        }

        let myPoints = state.currentGame.points(for: side)
        let theirPoints = state.currentGame.points(for: side.opposite)

        // Deuce territory (both at 40+)
        if myPoints >= 3 && theirPoints >= 3 {
            if state.currentGame.advantageSide == nil {
                state.currentGame.advantageSide = side
            } else if state.currentGame.advantageSide == side {
                completeGame(winner: side, in: &state)
            } else {
                // Advantage broken → back to deuce; golden point activates if enabled.
                state.currentGame.advantageSide = nil
                state.currentGame.isGoldenPointActive = state.settings.goldenPointEnabled
            }
            return
        }

        // Already at 40 with opponent below 40 → game
        if myPoints >= 3 && theirPoints < 3 {
            completeGame(winner: side, in: &state)
            return
        }

        state.currentGame.setPoints(myPoints + 1, for: side)
    }

    private func awardTieBreakPoint(to side: Side, in state: inout MatchState) {
        let myPoints = state.currentGame.points(for: side)
        state.currentGame.setPoints(myPoints + 1, for: side)

        if state.currentGame.tieBreakTotalPoints % 2 == 1,
           !state.settings.fixedServerPositions {
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
        completeSet(winner: winner, in: &state)
    }

    private func completeGame(winner: Side, in state: inout MatchState) {
        state.currentGame.isComplete = true
        state.currentGame.winner = winner
        state.currentGame.advantageSide = nil
        state.currentGame.isGoldenPointActive = false

        let games = state.currentSet.games(for: winner) + 1
        state.currentSet.setGames(games, for: winner)

        if state.currentSet.leftGames == 6 && state.currentSet.rightGames == 6 {
            state.currentGame = GameScore(isTieBreak: true)
            return
        }

        if isSetWon(by: winner, set: state.currentSet, settings: state.settings) {
            completeSet(winner: winner, in: &state)
        } else {
            if !state.settings.fixedServerPositions {
                state.currentServer = state.currentServer?.opposite
            }
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

    private func completeSet(winner: Side, in state: inout MatchState) {
        state.currentSet.isComplete = true
        state.currentSet.winner = winner
        state.completedSets.append(state.currentSet)

        switch winner {
        case .left: state.leftSetsWon += 1
        case .right: state.rightSetsWon += 1
        }

        if state.leftSetsWon >= state.settings.setsToWin {
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
            if state.settings.askServeAtSetStart, !state.settings.fixedServerPositions {
                state.currentServer = nil
                state.needsServerSelection = true
            }
        }
    }

    private func naturalWinner(of state: MatchState) -> Side? {
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
            startedAt: state.startedAt
        )
    }
}
