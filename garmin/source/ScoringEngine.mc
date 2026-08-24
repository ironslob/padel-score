// Pure scoring state machine — ported from shared/Scoring/ScoringEngine.swift

class ScoringEngine {

    function startMatch(settings as MatchSettings, id as String, at as Number) as MatchState {
        var state = new MatchState(id, settings.copy(), at);
        state.events.add(new MatchEvent(MatchEventKind.MATCH_STARTED, null, at));
        state.needsWarmUp = settings.shouldWarmUp();
        return state;
    }

    function applySelectServer(state as MatchState, side as Side, at as Number) as MatchState or Null {
        if (state.status != MatchStatus.IN_PROGRESS || !state.needsServerSelection) {
            return null;
        }
        var next = copyStateShell(state);
        next.events = copyEvents(state.events);
        next.events.add(new MatchEvent(MatchEventKind.SERVER_SELECTED, side, at));
        return replay(next.events, blankMatch(state));
    }

    function applyRequestServerSelection(state as MatchState) as MatchState or Null {
        if (state.status != MatchStatus.IN_PROGRESS || !state.isAtSetStart()) {
            return null;
        }
        if (state.needsServerSelection) {
            return state;
        }
        var next = copyStateShell(state);
        next.events = copyEvents(state.events);
        next.deuceFormatChanges = copyDeuceFormatChanges(state.deuceFormatChanges);
        next.currentServer = null;
        next.needsServerSelection = true;
        return next;
    }

    function applyCompleteWarmUp(state as MatchState) as MatchState or Null {
        if (state.status != MatchStatus.IN_PROGRESS) {
            return null;
        }
        if (!state.needsWarmUp || !state.isWaitingForFirstServe()) {
            return state;
        }
        var next = copyStateShell(state);
        next.events = copyEvents(state.events);
        next.deuceFormatChanges = copyDeuceFormatChanges(state.deuceFormatChanges);
        next.needsWarmUp = false;
        return next;
    }

    function applySetDeuceFormat(state as MatchState, format as DeuceFormat, at as Number) as MatchState or Null {
        if (state.status != MatchStatus.IN_PROGRESS) {
            return null;
        }
        if (state.settings.deuceFormat == format) {
            return state;
        }
        var next = copyStateShell(state);
        next.events = copyEvents(state.events);
        next.deuceFormatChanges = copyDeuceFormatChanges(state.deuceFormatChanges);
        if (next.deuceFormatChanges.size() == 0) {
            next.deuceFormatChanges.add(new DeuceFormatChange(next.settings.deuceFormat, next.startedAt));
        }
        var lastEventAt = next.events.size() > 0 ? next.events[next.events.size() - 1].timestamp : at;
        var effective = at > lastEventAt ? at : lastEventAt;
        next.deuceFormatChanges.add(new DeuceFormatChange(format, effective));
        next.settings.deuceFormat = format;
        var replayed = replay(next.events, blankMatch(next));
        return restoreWarmUp(state, restoreServerSelectionPrompt(state, replayed));
    }

    function applyPointWon(state as MatchState, side as Side, at as Number) as MatchState or Null {
        if (state.status != MatchStatus.IN_PROGRESS || state.needsServerSelection) {
            return null;
        }
        var next = copyStateShell(state);
        next.events = copyEvents(state.events);
        next.events.add(new MatchEvent(MatchEventKind.POINT_WON, side, at));
        var result = replay(next.events, blankMatch(state));
        if (result.status == MatchStatus.COMPLETED) {
            result.finishedAt = at;
            if (result.events.size() == 0 || result.events[result.events.size() - 1].kind != MatchEventKind.MATCH_FINISHED) {
                result.events.add(new MatchEvent(MatchEventKind.MATCH_FINISHED, null, at));
            }
        }
        return result;
    }

    function applyUndo(state as MatchState) as MatchState or Null {
        if (state.status != MatchStatus.IN_PROGRESS) {
            return null;
        }
        var index = -1;
        for (var i = state.events.size() - 1; i >= 0; i -= 1) {
            if (state.events[i].kind == MatchEventKind.POINT_WON) {
                index = i;
                break;
            }
        }
        if (index < 0) {
            return null;
        }
        var events = copyEvents(state.events);
        events = removeEventAt(events, index);
        return replay(events, blankMatch(state));
    }

    function applyFinish(state as MatchState, at as Number) as MatchState or Null {
        if (state.status != MatchStatus.IN_PROGRESS) {
            return null;
        }
        var next = copyStateShell(state);
        next.events = copyEvents(state.events);
        var winner = naturalWinner(state);
        if (winner != null) {
            next.winner = winner;
            next.status = MatchStatus.COMPLETED;
        } else {
            next.status = MatchStatus.ENDED_EARLY;
        }
        next.finishedAt = at;
        next.events.add(new MatchEvent(MatchEventKind.MATCH_FINISHED, null, at));
        return next;
    }

    function applyEndEarly(state as MatchState, at as Number) as MatchState or Null {
        if (state.status != MatchStatus.IN_PROGRESS) {
            return null;
        }
        var next = copyStateShell(state);
        next.events = copyEvents(state.events);
        next.status = MatchStatus.ENDED_EARLY;
        next.finishedAt = at;
        next.events.add(new MatchEvent(MatchEventKind.MATCH_ENDED_EARLY, null, at));
        return next;
    }

    function applyDiscard(state as MatchState, at as Number) as MatchState or Null {
        if (state.status != MatchStatus.IN_PROGRESS) {
            return null;
        }
        var next = copyStateShell(state);
        next.events = copyEvents(state.events);
        next.status = MatchStatus.DISCARDED;
        next.finishedAt = at;
        next.events.add(new MatchEvent(MatchEventKind.MATCH_DISCARDED, null, at));
        return next;
    }

    function replay(events as Array<MatchEvent>, base as MatchState) as MatchState {
        var state = blankMatch(base);
        state.events = [] as Array<MatchEvent>;

        var pending = copyDeuceFormatChanges(base.deuceFormatChanges);
        pending = sortDeuceFormatChanges(pending);
        var deuceFormat = pending.size() > 0 ? pending[0].format : base.settings.deuceFormat;

        for (var i = 0; i < events.size(); i += 1) {
            var event = events[i];
            while (pending.size() > 0 && pending[0].at < event.timestamp) {
                deuceFormat = pending[0].format;
                applyDeuceFormat(deuceFormat, state);
                pending = removeFirstChange(pending);
            }
            state.events.add(event);
            switch (event.kind) {
                case MatchEventKind.MATCH_STARTED:
                    state.startedAt = event.timestamp;
                    state.status = MatchStatus.IN_PROGRESS;
                    state.needsServerSelection = true;
                    break;
                case MatchEventKind.SERVER_SELECTED:
                    if (event.side != null && state.status == MatchStatus.IN_PROGRESS
                        && (state.needsServerSelection || state.isAtSetStart())) {
                        state.currentServer = event.side;
                        state.needsServerSelection = false;
                    }
                    break;
                case MatchEventKind.POINT_WON:
                    if (event.side != null && state.status == MatchStatus.IN_PROGRESS) {
                        awardPoint(event.side, state, deuceFormat);
                    }
                    break;
                case MatchEventKind.MATCH_FINISHED:
                    state.finishedAt = event.timestamp;
                    var winner = naturalWinner(state);
                    if (winner != null) {
                        state.status = MatchStatus.COMPLETED;
                        state.winner = winner;
                    } else {
                        state.status = MatchStatus.ENDED_EARLY;
                    }
                    break;
                case MatchEventKind.MATCH_ENDED_EARLY:
                    state.status = MatchStatus.ENDED_EARLY;
                    state.finishedAt = event.timestamp;
                    break;
                case MatchEventKind.MATCH_DISCARDED:
                    state.status = MatchStatus.DISCARDED;
                    state.finishedAt = event.timestamp;
                    break;
            }
        }
        for (var j = 0; j < pending.size(); j += 1) {
            applyDeuceFormat(pending[j].format, state);
        }
        return state;
    }

    function rehydrate(state as MatchState) as MatchState {
        var replayed = replay(state.events, blankMatch(state));
        return restoreWarmUp(state, restoreServerSelectionPrompt(state, replayed));
    }

    private function restoreServerSelectionPrompt(previous as MatchState, replayed as MatchState) as MatchState {
        if (previous.status != MatchStatus.IN_PROGRESS || !previous.needsServerSelection
            || replayed.status != MatchStatus.IN_PROGRESS || !replayed.isAtSetStart()) {
            return replayed;
        }
        replayed.currentServer = null;
        replayed.needsServerSelection = true;
        return replayed;
    }

    private function restoreWarmUp(previous as MatchState, replayed as MatchState) as MatchState {
        if (previous.status != MatchStatus.IN_PROGRESS || !previous.needsWarmUp
            || replayed.status != MatchStatus.IN_PROGRESS || !replayed.isWaitingForFirstServe()) {
            return replayed;
        }
        replayed.needsWarmUp = true;
        return replayed;
    }

    private function applyDeuceFormat(format as DeuceFormat, state as MatchState) as Void {
        if (state.status != MatchStatus.IN_PROGRESS || state.currentGame.isComplete
            || state.currentGame.isTieBreak
            || state.currentGame.leftPoints < 3 || state.currentGame.rightPoints < 3) {
            return;
        }
        if (format == DeuceFormat.DEUCE_GOLDEN_POINT) {
            state.currentGame.advantageSide = null;
            state.currentGame.isGoldenPointActive = true;
        } else {
            state.currentGame.isGoldenPointActive = false;
        }
    }

    private function awardPoint(side as Side, state as MatchState, deuceFormat as DeuceFormat) as Void {
        if (state.currentGame.isComplete || state.status != MatchStatus.IN_PROGRESS) {
            return;
        }
        if (state.currentGame.isTieBreak) {
            awardTieBreakPoint(side, state);
            return;
        }
        // A decisive point is live: this rally ends the game either way.
        if (state.currentGame.isGoldenPointActive) {
            completeGame(side, state);
            return;
        }

        var myPoints = state.currentGame.pointsFor(side);
        var theirPoints = state.currentGame.pointsFor(oppositeSide(side));

        // Deuce territory (both at 40+). Golden point never reaches here — it makes
        // the point decisive the moment the game arrives at 40-40, below.
        if (myPoints >= 3 && theirPoints >= 3) {
            if (state.currentGame.advantageSide == null) {
                state.currentGame.advantageSide = side;
            } else if (state.currentGame.advantageSide == side) {
                completeGame(side, state);
            } else {
                // Advantage broken → back to deuce. Silver point allows exactly one
                // advantage, so the next point decides; regular scoring keeps cycling.
                state.currentGame.advantageSide = null;
                state.currentGame.isGoldenPointActive =
                    deuceFormat == DeuceFormat.DEUCE_SILVER_POINT;
            }
            return;
        }

        if (myPoints >= 3 && theirPoints < 3) {
            completeGame(side, state);
            return;
        }

        state.currentGame.setPoints(myPoints + 1, side);

        // Golden point: no advantage phase at all, so reaching 40-40 makes the very
        // next rally decisive.
        if (deuceFormat == DeuceFormat.DEUCE_GOLDEN_POINT
            && state.currentGame.leftPoints >= 3
            && state.currentGame.rightPoints >= 3) {
            state.currentGame.isGoldenPointActive = true;
        }
    }

    private function awardTieBreakPoint(side as Side, state as MatchState) as Void {
        var myPoints = state.currentGame.pointsFor(side);
        state.currentGame.setPoints(myPoints + 1, side);

        if (state.currentGame.tieBreakTotalPoints() % 2 == 1) {
            if (state.currentServer != null) {
                state.currentServer = oppositeSide(state.currentServer);
            }
        }

        var theirPoints = state.currentGame.pointsFor(oppositeSide(side));
        if (myPoints + 1 >= 7 && (myPoints + 1) - theirPoints >= 2) {
            completeTieBreak(side, state);
        }
    }

    private function completeTieBreak(winner as Side, state as MatchState) as Void {
        state.currentGame.isComplete = true;
        state.currentGame.winner = winner;
        state.currentSet.setGames(7, winner);
        var nextSetServer = null;
        var opener = tieBreakOpeningServer(state);
        if (opener != null) {
            nextSetServer = oppositeSide(opener);
        }
        completeSet(winner, state, nextSetServer);
    }

    private function tieBreakOpeningServer(state as MatchState) as Side or Null {
        if (state.currentServer == null) {
            return null;
        }
        var flips = (state.currentGame.tieBreakTotalPoints() + 1) / 2;
        return (flips % 2 == 0) ? state.currentServer : oppositeSide(state.currentServer);
    }

    private function completeGame(winner as Side, state as MatchState) as Void {
        state.currentGame.isComplete = true;
        state.currentGame.winner = winner;
        state.currentGame.advantageSide = null;
        state.currentGame.isGoldenPointActive = false;

        var games = state.currentSet.gamesFor(winner) + 1;
        state.currentSet.setGames(games, winner);

        var nextServer = null;
        if (state.currentServer != null) {
            nextServer = oppositeSide(state.currentServer);
        }

        if (state.currentSet.leftGames == 6 && state.currentSet.rightGames == 6) {
            state.currentServer = nextServer;
            var tieBreak = new GameScore();
            tieBreak.isTieBreak = true;
            state.currentGame = tieBreak;
            return;
        }

        if (isSetWon(winner, state.currentSet, state.settings)) {
            completeSet(winner, state, nextServer);
        } else {
            state.currentServer = nextServer;
            state.currentGame = new GameScore();
        }
    }

    private function isSetWon(side as Side, set as SetScore, settings as MatchSettings) as Boolean {
        var my = set.gamesFor(side);
        var their = set.gamesFor(oppositeSide(side));
        if (my < settings.gamesToWinSet) {
            return false;
        }
        if (settings.mustWinByTwoGames) {
            return (my - their) >= 2;
        }
        return true;
    }

    private function completeSet(winner as Side, state as MatchState, nextSetServer as Side or Null) as Void {
        state.currentSet.isComplete = true;
        state.currentSet.winner = winner;
        state.completedSets.add(copySetScore(state.currentSet));

        if (winner == Side.LEFT) {
            state.leftSetsWon += 1;
        } else {
            state.rightSetsWon += 1;
        }

        if (state.settings.continuousPlay) {
            state.currentSet = new SetScore();
            state.currentGame = new GameScore();
            beginNextSetServe(nextSetServer, state);
        } else if (state.leftSetsWon >= state.settings.setsToWin) {
            state.winner = Side.LEFT;
            state.status = MatchStatus.COMPLETED;
            state.finishedAt = state.events[state.events.size() - 1].timestamp;
            state.currentGame = new GameScore();
        } else if (state.rightSetsWon >= state.settings.setsToWin) {
            state.winner = Side.RIGHT;
            state.status = MatchStatus.COMPLETED;
            state.finishedAt = state.events[state.events.size() - 1].timestamp;
            state.currentGame = new GameScore();
        } else {
            state.currentSet = new SetScore();
            state.currentGame = new GameScore();
            beginNextSetServe(nextSetServer, state);
        }
    }

    private function beginNextSetServe(nextSetServer as Side or Null, state as MatchState) as Void {
        if (state.settings.askServeAtSetStart) {
            state.currentServer = null;
            state.needsServerSelection = true;
        } else {
            state.currentServer = nextSetServer;
        }
    }

    private function naturalWinner(state as MatchState) as Side or Null {
        if (state.settings.continuousPlay) {
            if (state.leftSetsWon > state.rightSetsWon) {
                return Side.LEFT;
            }
            if (state.rightSetsWon > state.leftSetsWon) {
                return Side.RIGHT;
            }
            return null;
        }
        if (state.leftSetsWon >= state.settings.setsToWin) {
            return Side.LEFT;
        }
        if (state.rightSetsWon >= state.settings.setsToWin) {
            return Side.RIGHT;
        }
        return state.winner;
    }

    private function blankMatch(from as MatchState) as MatchState {
        var blank = new MatchState(from.id, from.settings.copy(), from.startedAt);
        blank.deuceFormatChanges = copyDeuceFormatChanges(from.deuceFormatChanges);
        return blank;
    }

    private function copyStateShell(state as MatchState) as MatchState {
        var copy = new MatchState(state.id, state.settings.copy(), state.startedAt);
        copy.status = state.status;
        copy.finishedAt = state.finishedAt;
        copy.currentGame = state.currentGame;
        copy.currentSet = state.currentSet;
        copy.completedSets = state.completedSets;
        copy.leftSetsWon = state.leftSetsWon;
        copy.rightSetsWon = state.rightSetsWon;
        copy.winner = state.winner;
        copy.currentServer = state.currentServer;
        copy.needsServerSelection = state.needsServerSelection;
        copy.needsWarmUp = state.needsWarmUp;
        copy.deuceFormatChanges = copyDeuceFormatChanges(state.deuceFormatChanges);
        return copy;
    }

    private function copyDeuceFormatChanges(changes as Array<DeuceFormatChange>) as Array<DeuceFormatChange> {
        var copy = [] as Array<DeuceFormatChange>;
        for (var i = 0; i < changes.size(); i += 1) {
            copy.add(new DeuceFormatChange(changes[i].format, changes[i].at));
        }
        return copy;
    }

    private function sortDeuceFormatChanges(changes as Array<DeuceFormatChange>) as Array<DeuceFormatChange> {
        var copy = copyDeuceFormatChanges(changes);
        for (var i = 1; i < copy.size(); i += 1) {
            var j = i;
            while (j > 0 && copy[j - 1].at > copy[j].at) {
                var temp = copy[j - 1];
                copy[j - 1] = copy[j];
                copy[j] = temp;
                j -= 1;
            }
        }
        return copy;
    }

    private function removeFirstChange(changes as Array<DeuceFormatChange>) as Array<DeuceFormatChange> {
        var copy = [] as Array<DeuceFormatChange>;
        for (var i = 1; i < changes.size(); i += 1) {
            copy.add(changes[i]);
        }
        return copy;
    }

    private function copyEvents(events as Array<MatchEvent>) as Array<MatchEvent> {
        var copy = [] as Array<MatchEvent>;
        for (var i = 0; i < events.size(); i += 1) {
            var e = events[i];
            copy.add(new MatchEvent(e.kind, e.side, e.timestamp));
        }
        return copy;
    }

    private function removeEventAt(events as Array<MatchEvent>, index as Number) as Array<MatchEvent> {
        var copy = [] as Array<MatchEvent>;
        for (var i = 0; i < events.size(); i += 1) {
            if (i != index) {
                copy.add(events[i]);
            }
        }
        return copy;
    }

    private function copySetScore(set as SetScore) as SetScore {
        var copy = new SetScore();
        copy.leftGames = set.leftGames;
        copy.rightGames = set.rightGames;
        copy.isComplete = set.isComplete;
        copy.winner = set.winner;
        return copy;
    }
}
