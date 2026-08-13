import Toybox.Application;
import Toybox.Lang;

// Local persistence — ported from shared/Persistence/MatchStore.swift

class MatchStore {
    private const ACTIVE_KEY = "activeMatch";
    private const ARCHIVE_KEY = "matchArchive";

    function loadActiveMatch() as MatchState or Null {
        var data = Application.Storage.getValue(ACTIVE_KEY);
        if (data == null) {
            return null;
        }
        return deserializeMatch(data as Dictionary);
    }

    function saveActiveMatch(match as MatchState or Null) as Void {
        if (match == null) {
            Application.Storage.deleteValue(ACTIVE_KEY);
        } else {
            Application.Storage.setValue(ACTIVE_KEY, serializeMatch(match));
        }
    }

    function loadArchivedMatches() as Array<MatchState> {
        var data = Application.Storage.getValue(ARCHIVE_KEY);
        if (data == null) {
            return [] as Array<MatchState>;
        }
        var items = data as Array;
        var matches = [] as Array<MatchState>;
        for (var i = 0; i < items.size(); i += 1) {
            var match = deserializeMatch(items[i] as Dictionary);
            if (match != null) {
                matches.add(match);
            }
        }
        return sortByStartedAt(matches);
    }

    function archiveMatch(match as MatchState) as Void {
        var matches = loadArchivedMatches();
        matches = removeById(matches, match.id);
        matches.add(match);
        matches = sortByStartedAt(matches);
        saveArchive(matches);
    }

    function replaceArchive(matches as Array<MatchState>) as Void {
        saveArchive(matches);
    }

    private function saveArchive(matches as Array<MatchState>) as Void {
        var items = [] as Array;
        for (var i = 0; i < matches.size(); i += 1) {
            items.add(serializeMatch(matches[i]));
        }
        Application.Storage.setValue(ARCHIVE_KEY, items);
    }

    private function removeById(matches as Array<MatchState>, id as String) as Array<MatchState> {
        var result = [] as Array<MatchState>;
        for (var i = 0; i < matches.size(); i += 1) {
            if (matches[i].id != id) {
                result.add(matches[i]);
            }
        }
        return result;
    }

    private function sortByStartedAt(matches as Array<MatchState>) as Array<MatchState> {
        // Simple insertion sort (archive is small).
        for (var i = 1; i < matches.size(); i += 1) {
            var j = i;
            while (j > 0 && matches[j - 1].startedAt < matches[j].startedAt) {
                var temp = matches[j - 1];
                matches[j - 1] = matches[j];
                matches[j] = temp;
                j -= 1;
            }
        }
        return matches;
    }

    private function serializeMatch(match as MatchState) as Dictionary {
        return {
            "id" => match.id,
            "settings" => serializeSettings(match.settings),
            "status" => match.status as Number,
            "events" => serializeEvents(match.events),
            "deuceFormatChanges" => serializeDeuceFormatChanges(match.deuceFormatChanges),
            "startedAt" => match.startedAt,
            "finishedAt" => match.finishedAt,
            "needsServerSelection" => match.needsServerSelection
        } as Dictionary;
    }

    private function serializeSettings(settings as MatchSettings) as Dictionary {
        return {
            "setsToWin" => settings.setsToWin,
            "continuousPlay" => settings.continuousPlay,
            "gamesToWinSet" => settings.gamesToWinSet,
            "mustWinByTwoGames" => settings.mustWinByTwoGames,
            "deuceFormat" => deuceFormatToString(settings.deuceFormat),
            // Pre-silver-point key, still written so an older build reading this
            // store keeps scoring these matches the same way.
            "goldenPointEnabled" => settings.deuceFormat != DeuceFormat.DEUCE_ADVANTAGE,
            "askServeAtSetStart" => settings.askServeAtSetStart,
            "fixedServerPositions" => settings.fixedServerPositions,
            "usThemLabels" => settings.usThemLabels
        } as Dictionary;
    }

    private function serializeEvents(events as Array<MatchEvent>) as Array {
        var items = [] as Array;
        for (var i = 0; i < events.size(); i += 1) {
            var e = events[i];
            var item = {
                "kind" => e.kind as Number,
                "timestamp" => e.timestamp
            } as Dictionary;
            if (e.side != null) {
                item.put("side", e.side as Number);
            }
            items.add(item);
        }
        return items;
    }

    private function deserializeMatch(data as Dictionary) as MatchState or Null {
        if (!data.hasKey("id") || !data.hasKey("settings") || !data.hasKey("startedAt")) {
            return null;
        }
        var settings = deserializeSettings(data.get("settings") as Dictionary);
        var startedAt = data.get("startedAt") as Number;
        var state = new MatchState(data.get("id") as String, settings, startedAt);
        if (data.hasKey("status")) {
            state.status = data.get("status") as MatchStatus;
        }
        if (data.hasKey("finishedAt")) {
            state.finishedAt = data.get("finishedAt") as Number;
        }
        var events = deserializeEvents(data.get("events") as Array);
        if (data.hasKey("deuceFormatChanges")) {
            state.deuceFormatChanges = deserializeDeuceFormatChanges(data.get("deuceFormatChanges") as Array);
        }
        var engine = new ScoringEngine();
        var replayed = engine.replay(events, state);
        if (data.hasKey("needsServerSelection") && (data.get("needsServerSelection") as Boolean)
            && replayed.status == MatchStatus.IN_PROGRESS && replayed.isAtSetStart()) {
            replayed.currentServer = null;
            replayed.needsServerSelection = true;
        }
        return replayed;
    }

    private function deserializeSettings(data as Dictionary) as MatchSettings {
        var settings = new MatchSettings();
        if (data.hasKey("setsToWin")) { settings.setsToWin = data.get("setsToWin") as Number; }
        if (data.hasKey("continuousPlay")) { settings.continuousPlay = data.get("continuousPlay") as Boolean; }
        if (data.hasKey("gamesToWinSet")) { settings.gamesToWinSet = data.get("gamesToWinSet") as Number; }
        if (data.hasKey("mustWinByTwoGames")) { settings.mustWinByTwoGames = data.get("mustWinByTwoGames") as Boolean; }
        var format = null;
        if (data.hasKey("deuceFormat")) {
            var rawFormat = data.get("deuceFormat");
            if (rawFormat != null) {
                format = deuceFormatFromString(rawFormat.toString());
            }
        }
        if (format != null) {
            settings.deuceFormat = format;
        } else if (data.hasKey("goldenPointEnabled")) {
            var legacyGoldenPoint = data.get("goldenPointEnabled") as Boolean;
            settings.deuceFormat = deuceFormatFromLegacyArchivedFlag(legacyGoldenPoint);
        }
        if (data.hasKey("askServeAtSetStart")) { settings.askServeAtSetStart = data.get("askServeAtSetStart") as Boolean; }
        if (data.hasKey("fixedServerPositions")) { settings.fixedServerPositions = data.get("fixedServerPositions") as Boolean; }
        if (data.hasKey("usThemLabels")) { settings.usThemLabels = data.get("usThemLabels") as Boolean; }
        return settings;
    }

    private function deserializeEvents(items as Array) as Array<MatchEvent> {
        var events = [] as Array<MatchEvent>;
        for (var i = 0; i < items.size(); i += 1) {
            var item = items[i] as Dictionary;
            var side = null;
            if (item.hasKey("side")) {
                side = item.get("side") as Side;
            }
            events.add(new MatchEvent(
                item.get("kind") as MatchEventKind,
                side,
                item.get("timestamp") as Number
            ));
        }
        return events;
    }

    private function serializeDeuceFormatChanges(changes as Array<DeuceFormatChange>) as Array {
        var items = [] as Array;
        for (var i = 0; i < changes.size(); i += 1) {
            items.add({
                "format" => deuceFormatToString(changes[i].format),
                "at" => changes[i].at
            } as Dictionary);
        }
        return items;
    }

    private function deserializeDeuceFormatChanges(items as Array) as Array<DeuceFormatChange> {
        var changes = [] as Array<DeuceFormatChange>;
        for (var i = 0; i < items.size(); i += 1) {
            var item = items[i] as Dictionary;
            var format = deuceFormatFromString(item.get("format") as String);
            if (format != null) {
                changes.add(new DeuceFormatChange(format, item.get("at") as Number));
            }
        }
        return changes;
    }
}
