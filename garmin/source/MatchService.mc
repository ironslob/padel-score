// Match lifecycle coordinator — ported from shared/Services/MatchService.swift

class MatchService {
    private var engine as ScoringEngine;
    private var store as MatchStore;
    var activeMatch as MatchState or Null;
    var archivedMatches as Array<MatchState>;
    var isRestored as Boolean;

    function initialize() {
        engine = new ScoringEngine();
        store = new MatchStore();
        activeMatch = null;
        archivedMatches = [] as Array<MatchState>;
        isRestored = false;
    }

    function restore() as Void {
        activeMatch = store.loadActiveMatch();
        archivedMatches = filterDiscarded(store.loadArchivedMatches());
        isRestored = true;
        expireInactiveMatchIfNeeded();
    }

    function startMatch(settings as MatchSettings or Null) as Void {
        if (activeMatch != null) {
            return;
        }
        var matchSettings = settings != null ? settings.copy() : new MatchSettings();
        var id = generateMatchId();
        activeMatch = engine.startMatch(matchSettings, id, Time.now().value());
        persist();
    }

    function awardPoint(side as Side) as Void {
        if (activeMatch == null || activeMatch.status != MatchStatus.IN_PROGRESS) {
            return;
        }
        var updated = engine.applyPointWon(activeMatch, side, Time.now().value());
        if (updated == null) {
            return;
        }
        activeMatch = updated;
        if (activeMatch.status == MatchStatus.COMPLETED) {
            finalizeActiveMatch();
        } else {
            persist();
            expireInactiveMatchIfNeeded();
        }
    }

    function selectServer(side as Side) as Void {
        if (activeMatch == null || activeMatch.status != MatchStatus.IN_PROGRESS) {
            return;
        }
        var updated = engine.applySelectServer(activeMatch, side, Time.now().value());
        if (updated == null) {
            return;
        }
        activeMatch = updated;
        persist();
        expireInactiveMatchIfNeeded();
    }

    function undoLastPoint() as Void {
        if (activeMatch == null || activeMatch.status != MatchStatus.IN_PROGRESS) {
            return;
        }
        var updated = engine.applyUndo(activeMatch);
        if (updated == null) {
            return;
        }
        activeMatch = updated;
        persist();
        expireInactiveMatchIfNeeded();
    }

    function canUndo() as Boolean {
        if (activeMatch == null || activeMatch.status != MatchStatus.IN_PROGRESS) {
            return false;
        }
        for (var i = 0; i < activeMatch.events.size(); i += 1) {
            if (activeMatch.events[i].kind == MatchEventKind.POINT_WON) {
                return true;
            }
        }
        return false;
    }

    function finishMatch() as Void {
        if (activeMatch == null || activeMatch.status != MatchStatus.IN_PROGRESS) {
            return;
        }
        var updated = engine.applyFinish(activeMatch, Time.now().value());
        if (updated == null) {
            return;
        }
        activeMatch = updated;
        finalizeActiveMatch();
    }

    function endMatchEarly() as Void {
        if (activeMatch == null || activeMatch.status != MatchStatus.IN_PROGRESS) {
            return;
        }
        var updated = engine.applyEndEarly(activeMatch, Time.now().value());
        if (updated == null) {
            return;
        }
        activeMatch = updated;
        finalizeActiveMatch();
    }

    function discardMatch() as Void {
        if (activeMatch == null || activeMatch.status != MatchStatus.IN_PROGRESS) {
            return;
        }
        var updated = engine.applyDiscard(activeMatch, Time.now().value());
        if (updated == null) {
            return;
        }
        activeMatch = null;
        store.saveActiveMatch(null);
    }

    function acknowledgeCompletedMatch() as Void {
        if (activeMatch == null) {
            store.saveActiveMatch(null);
            return;
        }
        if (activeMatch.status == MatchStatus.DISCARDED) {
            activeMatch = null;
            store.saveActiveMatch(null);
            return;
        }
        if (isTerminal(activeMatch.status)) {
            if (!archiveContains(activeMatch.id)) {
                store.archiveMatch(activeMatch);
                archivedMatches = filterDiscarded(store.loadArchivedMatches());
            }
        }
        activeMatch = null;
        store.saveActiveMatch(null);
    }

    function expireInactiveMatchIfNeeded() as Void {
        if (activeMatch == null || !activeMatch.isInactive(Time.now().value())) {
            return;
        }
        if (activeMatch.hasScoredPoints()) {
            endMatchEarly();
        } else {
            discardMatch();
        }
    }

    function syncActiveMatchPreferences(usThemLabels as Boolean, fixedServerPositions as Boolean, askServeAtSetStart as Boolean) as Void {
        if (activeMatch == null || activeMatch.status != MatchStatus.IN_PROGRESS) {
            return;
        }
        activeMatch.settings.usThemLabels = usThemLabels;
        activeMatch.settings.fixedServerPositions = fixedServerPositions;
        activeMatch.settings.askServeAtSetStart = askServeAtSetStart;
        persist();
    }

    function getGoldenPointEnabled() as Boolean {
        var value = Application.Properties.getValue("goldenPointEnabled");
        if (value == null) {
            return true;
        }
        return value as Boolean;
    }

    function setGoldenPointEnabled(enabled as Boolean) as Void {
        Application.Properties.setValue("goldenPointEnabled", enabled);
    }

    // Rotate serve is the user-facing inverse of fixedServerPositions.
    function getRotateServeEnabled() as Boolean {
        var value = Application.Properties.getValue("rotateServeEnabled");
        if (value == null) {
            return false;
        }
        return value as Boolean;
    }

    function setRotateServeEnabled(enabled as Boolean) as Void {
        Application.Properties.setValue("rotateServeEnabled", enabled);
        if (activeMatch != null && activeMatch.status == MatchStatus.IN_PROGRESS) {
            activeMatch.settings.fixedServerPositions = !enabled;
            persist();
        }
    }

    private function finalizeActiveMatch() as Void {
        if (activeMatch == null) {
            return;
        }
        if (activeMatch.status != MatchStatus.DISCARDED) {
            store.archiveMatch(activeMatch);
            archivedMatches = filterDiscarded(store.loadArchivedMatches());
        }
        store.saveActiveMatch(activeMatch);
    }

    private function persist() as Void {
        store.saveActiveMatch(activeMatch);
    }

    private function filterDiscarded(matches as Array<MatchState>) as Array<MatchState> {
        var result = [] as Array<MatchState>;
        for (var i = 0; i < matches.size(); i += 1) {
            if (matches[i].status != MatchStatus.DISCARDED) {
                result.add(matches[i]);
            }
        }
        return result;
    }

    private function archiveContains(id as String) as Boolean {
        for (var i = 0; i < archivedMatches.size(); i += 1) {
            if (archivedMatches[i].id == id) {
                return true;
            }
        }
        return false;
    }

    private function isTerminal(status as MatchStatus) as Boolean {
        return status == MatchStatus.COMPLETED
            || status == MatchStatus.ENDED_EARLY
            || status == MatchStatus.DISCARDED;
    }

    private function generateMatchId() as String {
        return Time.now().value().toString() + "-" + System.getTimer().toString();
    }
}
