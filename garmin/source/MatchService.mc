import Toybox.Application;
import Toybox.Lang;
import Toybox.System;
import Toybox.Time;

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
        if (activeMatch == null || activeMatch.status != IN_PROGRESS) {
            return;
        }
        var updated = engine.applyPointWon(activeMatch, side, Time.now().value());
        if (updated == null) {
            return;
        }
        activeMatch = updated;
        if (activeMatch.status == COMPLETED) {
            finalizeActiveMatch();
        } else {
            persist();
            expireInactiveMatchIfNeeded();
        }
    }

    function selectServer(side as Side) as Void {
        if (activeMatch == null || activeMatch.status != IN_PROGRESS) {
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

    function requestServerSelection() as Void {
        if (activeMatch == null || activeMatch.status != IN_PROGRESS) {
            return;
        }
        var updated = engine.applyRequestServerSelection(activeMatch);
        if (updated == null) {
            return;
        }
        activeMatch = updated;
        persist();
        expireInactiveMatchIfNeeded();
    }

    function completeWarmUp() as Void {
        if (activeMatch == null || activeMatch.status != IN_PROGRESS) {
            return;
        }
        var updated = engine.applyCompleteWarmUp(activeMatch);
        if (updated == null) {
            return;
        }
        activeMatch = updated;
        persist();
    }

    function undoLastPoint() as Void {
        if (activeMatch == null || activeMatch.status != IN_PROGRESS) {
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
        if (activeMatch == null || activeMatch.status != IN_PROGRESS) {
            return false;
        }
        for (var i = 0; i < activeMatch.events.size(); i += 1) {
            if (activeMatch.events[i].kind == POINT_WON) {
                return true;
            }
        }
        return false;
    }

    function finishMatch() as Void {
        if (activeMatch == null || activeMatch.status != IN_PROGRESS) {
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
        if (activeMatch == null || activeMatch.status != IN_PROGRESS) {
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
        if (activeMatch == null || activeMatch.status != IN_PROGRESS) {
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
        if (activeMatch.status == DISCARDED) {
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
        if (activeMatch == null || activeMatch.status != IN_PROGRESS) {
            return;
        }
        activeMatch.settings.usThemLabels = usThemLabels;
        activeMatch.settings.fixedServerPositions = fixedServerPositions;
        activeMatch.settings.askServeAtSetStart = askServeAtSetStart;
        persist();
    }

    function getDeuceFormat() as DeuceFormat {
        var raw = Application.Properties.getValue("deuceFormat");
        var format = null;
        if (raw != null) {
            format = deuceFormatFromString(raw.toString());
        }
        if (format != null) {
            return format;
        }
        var legacy = Application.Properties.getValue("goldenPointEnabled");
        return deuceFormatFromLegacyPreference(legacy as Boolean or Null);
    }

    function setDeuceFormat(format as DeuceFormat) as Void {
        Application.Properties.setValue("deuceFormat", deuceFormatToString(format));
        if (activeMatch != null && activeMatch.status == IN_PROGRESS) {
            var updated = engine.applySetDeuceFormat(activeMatch, format, Time.now().value());
            if (updated != null) {
                activeMatch = updated;
                persist();
            }
        }
    }

    // Advances the setting through Regular → Star → Silver → Golden → Regular.
    function cycleDeuceFormat() as DeuceFormat {
        var next = deuceFormatAfter(getDeuceFormat());
        setDeuceFormat(next);
        return next;
    }

    // Swap-sides-each-game is the user-facing inverse of fixedServerPositions.
    function getRotateServeEnabled() as Boolean {
        var value = Application.Properties.getValue("rotateServeEnabled");
        if (value == null) {
            return false;
        }
        return value as Boolean;
    }

    function setRotateServeEnabled(enabled as Boolean) as Void {
        Application.Properties.setValue("rotateServeEnabled", enabled);
        if (activeMatch != null && activeMatch.status == IN_PROGRESS) {
            activeMatch.settings.fixedServerPositions = !enabled;
            persist();
        }
    }

    function getUsThemLabels() as Boolean {
        var value = Application.Properties.getValue("usThemLabels");
        if (value == null) {
            return true;
        }
        return value as Boolean;
    }

    function setUsThemLabels(enabled as Boolean) as Void {
        Application.Properties.setValue("usThemLabels", enabled);
        if (activeMatch != null && activeMatch.status == IN_PROGRESS) {
            activeMatch.settings.usThemLabels = enabled;
            persist();
        }
    }

    function cycleUsThemLabels() as Boolean {
        var next = !getUsThemLabels();
        setUsThemLabels(next);
        return next;
    }

    function getAskServeAtSetStart() as Boolean {
        var value = Application.Properties.getValue("askServeAtSetStart");
        if (value == null) {
            return false;
        }
        return value as Boolean;
    }

    function setAskServeAtSetStart(enabled as Boolean) as Void {
        Application.Properties.setValue("askServeAtSetStart", enabled);
        if (activeMatch != null && activeMatch.status == IN_PROGRESS) {
            activeMatch.settings.askServeAtSetStart = enabled;
            persist();
        }
    }

    function cycleAskServeAtSetStart() as Boolean {
        var next = !getAskServeAtSetStart();
        setAskServeAtSetStart(next);
        return next;
    }

    function getMatchSetFormat() as MatchSetFormat {
        var raw = Application.Properties.getValue("matchSetFormat");
        if (raw != null) {
            var value = raw as Number;
            if (value == SET_FORMAT_BEST_OF_ONE
                || value == SET_FORMAT_BEST_OF_THREE
                || value == SET_FORMAT_BEST_OF_THREE_MATCH_TB
                || value == SET_FORMAT_BEST_OF_FIVE
                || value == SET_FORMAT_CONTINUOUS) {
                return value as MatchSetFormat;
            }
        }
        return SET_FORMAT_BEST_OF_THREE;
    }

    function setMatchSetFormat(format as MatchSetFormat) as Void {
        Application.Properties.setValue("matchSetFormat", format as Number);
    }

    function cycleMatchSetFormat() as MatchSetFormat {
        var next = nextMatchSetFormat(getMatchSetFormat());
        setMatchSetFormat(next);
        return next;
    }

    function getWarmUpEnabled() as Boolean {
        var value = Application.Properties.getValue("warmUpEnabled");
        if (value == null) {
            return true;
        }
        return value as Boolean;
    }

    function setWarmUpEnabled(enabled as Boolean) as Void {
        Application.Properties.setValue("warmUpEnabled", enabled);
    }

    function cycleWarmUpEnabled() as Boolean {
        var next = !getWarmUpEnabled();
        setWarmUpEnabled(next);
        return next;
    }

    function getWarmUpMinutes() as Number {
        var value = Application.Properties.getValue("warmUpMinutes");
        if (value == null) {
            return MatchSettings.WARM_UP_MINUTES_DEFAULT;
        }
        return clampWarmUpMinutes(value as Number);
    }

    function setWarmUpMinutes(minutes as Number) as Void {
        Application.Properties.setValue("warmUpMinutes", clampWarmUpMinutes(minutes));
    }

    function cycleWarmUpMinutes() as Number {
        var current = getWarmUpMinutes();
        var presets = [0, 3, 5, 10] as Array<Number>;
        var next = presets[0];
        var found = false;
        for (var i = 0; i < presets.size(); i += 1) {
            if (presets[i] == current) {
                next = presets[(i + 1) % presets.size()];
                found = true;
                break;
            }
            if (!found && presets[i] > current) {
                next = presets[i];
                found = true;
                break;
            }
        }
        setWarmUpMinutes(next);
        return next;
    }

    function settingsForNewMatch() as MatchSettings {
        var settings = new MatchSettings();
        settings.deuceFormat = getDeuceFormat();
        settings.fixedServerPositions = !getRotateServeEnabled();
        settings.usThemLabels = getUsThemLabels();
        settings.askServeAtSetStart = getAskServeAtSetStart();
        applyMatchSetFormat(settings, getMatchSetFormat());
        settings.warmUpEnabled = getWarmUpEnabled();
        settings.warmUpMinutes = getWarmUpMinutes();
        return settings;
    }

    private function finalizeActiveMatch() as Void {
        if (activeMatch == null) {
            return;
        }
        if (activeMatch.status != DISCARDED) {
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
            if (matches[i].status != DISCARDED) {
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
        return status == COMPLETED
            || status == ENDED_EARLY
            || status == DISCARDED;
    }

    private function generateMatchId() as String {
        return Time.now().value().toString() + "-" + System.getTimer().toString();
    }
}
