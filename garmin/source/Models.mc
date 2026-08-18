// Domain constants and enums — ported from shared/Models/

enum Side {
    LEFT,
    RIGHT
}

enum MatchStatus {
    IN_PROGRESS,
    COMPLETED,
    ENDED_EARLY,
    DISCARDED
}

enum MatchEventKind {
    MATCH_STARTED,
    SERVER_SELECTED,
    POINT_WON,
    MATCH_FINISHED,
    MATCH_ENDED_EARLY,
    MATCH_DISCARDED
}

enum ScoringError {
    NONE,
    MATCH_NOT_IN_PROGRESS,
    NOTHING_TO_UNDO,
    MATCH_ALREADY_STARTED,
    INVALID_ACTION
}

enum MatchActionType {
    SELECT_SERVER,
    POINT_WON,
    UNDO,
    FINISH,
    END_EARLY,
    DISCARD,
    REQUEST_SERVER_SELECTION,
    COMPLETE_WARM_UP,
    SET_DEUCE_FORMAT
}

// How a game is resolved once both sides reach 40.
enum DeuceFormat {
    // Traditional scoring: advantage repeats until one side wins by two points.
    DEUCE_ADVANTAGE,
    // One advantage is played. If it is broken, the next point decides the game.
    DEUCE_SILVER_POINT,
    // No advantage at all — the first point at 40-40 decides the game.
    DEUCE_GOLDEN_POINT
}

// Persisted as a string so stored values survive enum reordering.
function deuceFormatToString(format as DeuceFormat) as String {
    if (format == DeuceFormat.DEUCE_ADVANTAGE) {
        return "advantage";
    } else if (format == DeuceFormat.DEUCE_SILVER_POINT) {
        return "silverPoint";
    }
    return "goldenPoint";
}

function deuceFormatFromString(raw as String or Null) as DeuceFormat or Null {
    if (raw == null) {
        return null;
    }
    if (raw.equals("advantage")) {
        return DeuceFormat.DEUCE_ADVANTAGE;
    } else if (raw.equals("silverPoint")) {
        return DeuceFormat.DEUCE_SILVER_POINT;
    } else if (raw.equals("goldenPoint")) {
        return DeuceFormat.DEUCE_GOLDEN_POINT;
    }
    return null;
}

// Migration for a match archived before silver point existed. The old
// `goldenPointEnabled` flag played one advantage before the decisive point,
// which is silver point — so map it there to keep archived scorelines faithful
// to how they were actually played.
function deuceFormatFromLegacyArchivedFlag(goldenPointEnabled as Boolean) as DeuceFormat {
    return goldenPointEnabled ? DeuceFormat.DEUCE_SILVER_POINT : DeuceFormat.DEUCE_ADVANTAGE;
}

// Migration for the stored user preference, which deliberately differs from the
// archived-match rule above: someone who turned the old toggle off wanted full
// advantage scoring, so honour that. Everyone else gets the new default, which
// is what the old "Golden Point" label promised.
function deuceFormatFromLegacyPreference(goldenPointEnabled as Boolean or Null) as DeuceFormat {
    if (goldenPointEnabled != null && !goldenPointEnabled) {
        return DeuceFormat.DEUCE_ADVANTAGE;
    }
    return DeuceFormat.DEUCE_GOLDEN_POINT;
}

// Settings label. Kept compact because the settings button renders at
// FONT_MEDIUM and does not truncate.
function deuceFormatLabel(format as DeuceFormat) as String {
    if (format == DeuceFormat.DEUCE_ADVANTAGE) {
        return "Regular";
    } else if (format == DeuceFormat.DEUCE_SILVER_POINT) {
        return "Silver";
    }
    return "Golden";
}

// Name for the decisive point, shown on the score screen.
function deuceFormatDecidingPointLabel(format as DeuceFormat) as String {
    if (format == DeuceFormat.DEUCE_ADVANTAGE) {
        return "Deuce";
    } else if (format == DeuceFormat.DEUCE_SILVER_POINT) {
        return "Silver Point";
    }
    return "Golden Point";
}

// Two-character form for the score readout.
function deuceFormatDecidingPointShortLabel(format as DeuceFormat) as String {
    if (format == DeuceFormat.DEUCE_ADVANTAGE) {
        return "40";
    } else if (format == DeuceFormat.DEUCE_SILVER_POINT) {
        return "SP";
    }
    return "GP";
}

enum MatchSetFormat {
    SET_FORMAT_BEST_OF_ONE,
    SET_FORMAT_BEST_OF_THREE,
    SET_FORMAT_BEST_OF_FIVE,
    SET_FORMAT_CONTINUOUS
}

function matchSetFormatFromSettings(settings as MatchSettings) as MatchSetFormat {
    if (settings.continuousPlay) {
        return MatchSetFormat.SET_FORMAT_CONTINUOUS;
    }
    if (settings.setsToWin == 1) {
        return MatchSetFormat.SET_FORMAT_BEST_OF_ONE;
    }
    if (settings.setsToWin == 3) {
        return MatchSetFormat.SET_FORMAT_BEST_OF_FIVE;
    }
    return MatchSetFormat.SET_FORMAT_BEST_OF_THREE;
}

function applyMatchSetFormat(settings as MatchSettings, format as MatchSetFormat) as Void {
    if (format == MatchSetFormat.SET_FORMAT_BEST_OF_ONE) {
        settings.setsToWin = 1;
        settings.continuousPlay = false;
    } else if (format == MatchSetFormat.SET_FORMAT_BEST_OF_FIVE) {
        settings.setsToWin = 3;
        settings.continuousPlay = false;
    } else if (format == MatchSetFormat.SET_FORMAT_CONTINUOUS) {
        settings.continuousPlay = true;
    } else {
        settings.setsToWin = 2;
        settings.continuousPlay = false;
    }
}

function matchSetFormatLabel(format as MatchSetFormat) as String {
    if (format == MatchSetFormat.SET_FORMAT_BEST_OF_ONE) {
        return "1 set";
    } else if (format == MatchSetFormat.SET_FORMAT_BEST_OF_FIVE) {
        return "Best of 5";
    } else if (format == MatchSetFormat.SET_FORMAT_CONTINUOUS) {
        return "Continuous";
    }
    return "Best of 3";
}

function nextMatchSetFormat(format as MatchSetFormat) as MatchSetFormat {
    if (format == MatchSetFormat.SET_FORMAT_BEST_OF_ONE) {
        return MatchSetFormat.SET_FORMAT_BEST_OF_THREE;
    } else if (format == MatchSetFormat.SET_FORMAT_BEST_OF_THREE) {
        return MatchSetFormat.SET_FORMAT_BEST_OF_FIVE;
    } else if (format == MatchSetFormat.SET_FORMAT_BEST_OF_FIVE) {
        return MatchSetFormat.SET_FORMAT_CONTINUOUS;
    }
    return MatchSetFormat.SET_FORMAT_BEST_OF_ONE;
}

class DeuceFormatChange {
    var format as DeuceFormat;
    var at as Number;

    function initialize(format as DeuceFormat, at as Number) {
        self.format = format;
        self.at = at;
    }
}

class MatchSettings {
    var setsToWin as Number;
    var continuousPlay as Boolean;
    var gamesToWinSet as Number;
    var mustWinByTwoGames as Boolean;
    // How a game is decided once both sides reach 40.
    var deuceFormat as DeuceFormat;
    var askServeAtSetStart as Boolean;
    var fixedServerPositions as Boolean;
    var usThemLabels as Boolean;
    var warmUpEnabled as Boolean;
    var warmUpMinutes as Number;

    static const QUICK_UNDO_TIMEOUT_MS = 3000;
    static const INACTIVITY_TIMEOUT_S = 30 * 60;
    static const WARM_UP_MINUTES_MIN = 0;
    static const WARM_UP_MINUTES_MAX = 30;
    static const WARM_UP_MINUTES_DEFAULT = 0;

    function initialize() {
        setsToWin = 2;
        continuousPlay = false;
        gamesToWinSet = 6;
        mustWinByTwoGames = true;
        deuceFormat = DeuceFormat.DEUCE_GOLDEN_POINT;
        askServeAtSetStart = false;
        fixedServerPositions = true;
        usThemLabels = true;
        warmUpEnabled = true;
        warmUpMinutes = WARM_UP_MINUTES_DEFAULT;
    }

    function copy() as MatchSettings {
        var s = new MatchSettings();
        s.setsToWin = setsToWin;
        s.continuousPlay = continuousPlay;
        s.gamesToWinSet = gamesToWinSet;
        s.mustWinByTwoGames = mustWinByTwoGames;
        s.deuceFormat = deuceFormat;
        s.askServeAtSetStart = askServeAtSetStart;
        s.fixedServerPositions = fixedServerPositions;
        s.usThemLabels = usThemLabels;
        s.warmUpEnabled = warmUpEnabled;
        s.warmUpMinutes = warmUpMinutes;
        return s;
    }

    function shouldWarmUp() as Boolean {
        return warmUpEnabled;
    }
}

function clampWarmUpMinutes(value as Number) as Number {
    if (value < MatchSettings.WARM_UP_MINUTES_MIN) {
        return MatchSettings.WARM_UP_MINUTES_MIN;
    }
    if (value > MatchSettings.WARM_UP_MINUTES_MAX) {
        return MatchSettings.WARM_UP_MINUTES_MAX;
    }
    return value;
}

class GameScore {
    var leftPoints as Number;
    var rightPoints as Number;
    var advantageSide as Side or Null;
    // True while a single decisive rally is in progress: immediately at 40-40 under
    // golden point, or after an advantage is broken under silver point.
    var isGoldenPointActive as Boolean;
    var isTieBreak as Boolean;
    var isComplete as Boolean;
    var winner as Side or Null;

    function initialize() {
        leftPoints = 0;
        rightPoints = 0;
        advantageSide = null;
        isGoldenPointActive = false;
        isTieBreak = false;
        isComplete = false;
        winner = null;
    }

    function pointsFor(side as Side) as Number {
        return side == Side.LEFT ? leftPoints : rightPoints;
    }

    function setPoints(value as Number, side as Side) as Void {
        if (side == Side.LEFT) {
            leftPoints = value;
        } else {
            rightPoints = value;
        }
    }

    function tieBreakTotalPoints() as Number {
        return leftPoints + rightPoints;
    }

    function displayPair(deuceFormat as DeuceFormat) as Array<String> {
        if (isComplete) {
            return ["0", "0"] as Array<String>;
        }
        if (isTieBreak) {
            return [leftPoints.toString(), rightPoints.toString()] as Array<String>;
        }
        if (isGoldenPointActive) {
            var label = deuceFormatDecidingPointShortLabel(deuceFormat);
            return [label, label] as Array<String>;
        }
        if (advantageSide != null) {
            if (advantageSide == Side.LEFT) {
                return ["Ad", "40"] as Array<String>;
            }
            return ["40", "Ad"] as Array<String>;
        }
        if (leftPoints >= 3 && rightPoints >= 3) {
            return ["40", "40"] as Array<String>;
        }
        return [pointLabel(leftPoints), pointLabel(rightPoints)] as Array<String>;
    }

    function statusLine(deuceFormat as DeuceFormat) as String or Null {
        if (isTieBreak) {
            return "Tie-break";
        }
        if (isGoldenPointActive) {
            return deuceFormatDecidingPointLabel(deuceFormat);
        }
        if (advantageSide != null) {
            return "Advantage";
        }
        if (leftPoints >= 3 && rightPoints >= 3) {
            return "Deuce";
        }
        return null;
    }

    function tieBreakNotice() as String or Null {
        if (!isTieBreak) {
            return null;
        }
        var total = tieBreakTotalPoints();
        if (total <= 0) {
            return null;
        }
        if (total % 6 == 0) {
            return "Change sides";
        }
        if (total % 2 == 1) {
            return "Change serve";
        }
        return null;
    }

    private function pointLabel(points as Number) as String {
        if (points == 0) {
            return "0";
        } else if (points == 1) {
            return "15";
        } else if (points == 2) {
            return "30";
        }
        return "40";
    }
}

class SetScore {
    var leftGames as Number;
    var rightGames as Number;
    var isComplete as Boolean;
    var winner as Side or Null;

    function initialize() {
        leftGames = 0;
        rightGames = 0;
        isComplete = false;
        winner = null;
    }

    function gamesFor(side as Side) as Number {
        return side == Side.LEFT ? leftGames : rightGames;
    }

    function setGames(value as Number, side as Side) as Void {
        if (side == Side.LEFT) {
            leftGames = value;
        } else {
            rightGames = value;
        }
    }

    function displayPair() as Array<String> {
        return [leftGames.toString(), rightGames.toString()] as Array<String>;
    }
}

class MatchEvent {
    var kind as MatchEventKind;
    var side as Side or Null;
    var timestamp as Number;

    function initialize(kind as MatchEventKind, side as Side or Null, timestamp as Number) {
        self.kind = kind;
        self.side = side;
        self.timestamp = timestamp;
    }
}

class MatchState {
    var id as String;
    var settings as MatchSettings;
    var status as MatchStatus;
    var events as Array<MatchEvent>;
    var deuceFormatChanges as Array<DeuceFormatChange>;
    var startedAt as Number;
    var finishedAt as Number or Null;

    var currentGame as GameScore;
    var currentSet as SetScore;
    var completedSets as Array<SetScore>;
    var leftSetsWon as Number;
    var rightSetsWon as Number;
    var winner as Side or Null;
    var currentServer as Side or Null;
    var needsServerSelection as Boolean;
    var needsWarmUp as Boolean;

    function initialize(id as String, settings as MatchSettings, startedAt as Number) {
        self.id = id;
        self.settings = settings;
        self.status = MatchStatus.IN_PROGRESS;
        self.events = [] as Array<MatchEvent>;
        self.deuceFormatChanges = [] as Array<DeuceFormatChange>;
        self.startedAt = startedAt;
        self.finishedAt = null;
        self.currentGame = new GameScore();
        self.currentSet = new SetScore();
        self.completedSets = [] as Array<SetScore>;
        self.leftSetsWon = 0;
        self.rightSetsWon = 0;
        self.winner = null;
        self.currentServer = null;
        self.needsServerSelection = true;
        self.needsWarmUp = false;
    }

    function hasScoredPoints() as Boolean {
        for (var i = 0; i < events.size(); i += 1) {
            if (events[i].kind == MatchEventKind.POINT_WON) {
                return true;
            }
        }
        return false;
    }

    function isAtSetStart() as Boolean {
        return currentSet.leftGames == 0 && currentSet.rightGames == 0
            && currentGame.leftPoints == 0 && currentGame.rightPoints == 0
            && currentGame.advantageSide == null && !currentGame.isGoldenPointActive
            && !currentGame.isTieBreak && !currentGame.isComplete;
    }

    function canChooseNewServer() as Boolean {
        return status == MatchStatus.IN_PROGRESS && !needsServerSelection && isAtSetStart()
            && completedSets.size() > 0;
    }

    function isWaitingForFirstServe() as Boolean {
        return status == MatchStatus.IN_PROGRESS && needsServerSelection && isAtSetStart()
            && completedSets.size() == 0 && !hasScoredPoints();
    }

    function warmUpRemaining(now as Number) as Number {
        if (!needsWarmUp) {
            return 0;
        }
        var remaining = (startedAt + settings.warmUpMinutes * 60) - now;
        return remaining > 0 ? remaining : 0;
    }

    function warmUpElapsed(now as Number) as Number {
        var elapsed = now - startedAt;
        return elapsed > 0 ? elapsed : 0;
    }

    function isWarmUpExpired(now as Number) as Boolean {
        if (!needsWarmUp || settings.warmUpMinutes <= 0) {
            return false;
        }
        return warmUpRemaining(now) <= 0;
    }

    function lastScoringActivityAt() as Number {
        for (var i = events.size() - 1; i >= 0; i -= 1) {
            if (events[i].kind == MatchEventKind.POINT_WON) {
                return events[i].timestamp;
            }
        }
        return startedAt;
    }

    function isInactive(now as Number) as Boolean {
        if (status != MatchStatus.IN_PROGRESS) {
            return false;
        }
        return (now - lastScoringActivityAt()) >= MatchSettings.INACTIVITY_TIMEOUT_S;
    }

    function matchSetsDisplay() as Array<String> {
        return [leftSetsWon.toString(), rightSetsWon.toString()] as Array<String>;
    }

    // Logical sides mapped onto score-screen positions.
    // When swap-sides is on (fixedServerPositions == false), serving team is visual left.
    // When off, Us/Them stay fixed as logical left/right.
    function scoreScreenSides() as Array<Side> {
        if (settings.fixedServerPositions) {
            return [Side.LEFT, Side.RIGHT] as Array<Side>;
        }
        if (currentServer == Side.RIGHT) {
            return [Side.RIGHT, Side.LEFT] as Array<Side>;
        }
        return [Side.LEFT, Side.RIGHT] as Array<Side>;
    }

    // Game point labels for the current game, using this match's deuce format.
    function gameDisplayPair() as Array<String> {
        return currentGame.displayPair(settings.deuceFormat);
    }

    // Status line for the current game ("Deuce", "Golden Point", …), or null.
    function gameStatusLine() as String or Null {
        return currentGame.statusLine(settings.deuceFormat);
    }

    function scoreScreenGameDisplay() as Array<String> {
        return remapForScoreScreen(gameDisplayPair());
    }

    function scoreScreenSetDisplay() as Array<String> {
        return remapForScoreScreen(currentSet.displayPair());
    }

    function servingRoleLabels() as Array<String> {
        if (settings.usThemLabels) {
            var sides = scoreScreenSides();
            return [sideDisplayName(sides[0]), sideDisplayName(sides[1])] as Array<String>;
        }
        if (currentServer == null) {
            return ["", ""] as Array<String>;
        }
        var sides = scoreScreenSides();
        var leftLabel = sides[0] == currentServer ? "Serving" : "Receiving";
        var rightLabel = sides[1] == currentServer ? "Serving" : "Receiving";
        return [leftLabel, rightLabel] as Array<String>;
    }

    function logicalSideForVisual(visual as Side) as Side {
        var sides = scoreScreenSides();
        return visual == Side.LEFT ? sides[0] : sides[1];
    }

    function visualSideForLogical(logical as Side) as Side {
        var sides = scoreScreenSides();
        return sides[0] == logical ? Side.LEFT : Side.RIGHT;
    }

    private function remapForScoreScreen(pair as Array<String>) as Array<String> {
        if (settings.fixedServerPositions) {
            return pair;
        }
        if (currentServer == Side.RIGHT) {
            return [pair[1], pair[0]] as Array<String>;
        }
        return pair;
    }

    function setScoreLines() as Array<String> {
        var lines = [] as Array<String>;
        for (var i = 0; i < completedSets.size(); i += 1) {
            var set = completedSets[i];
            lines.add(set.leftGames.toString() + "-" + set.rightGames.toString());
        }
        if (status == MatchStatus.IN_PROGRESS || status == MatchStatus.ENDED_EARLY || status == MatchStatus.COMPLETED) {
            if (!currentSet.isComplete) {
                lines.add(currentSet.leftGames.toString() + "-" + currentSet.rightGames.toString());
            }
        }
        return lines;
    }

    function finalScoreSummary() as String {
        var lines = [] as Array<String>;
        for (var i = 0; i < completedSets.size(); i += 1) {
            var set = completedSets[i];
            lines.add(set.leftGames.toString() + "-" + set.rightGames.toString());
        }
        var partial = partialSetLineForIncompleteTerminal();
        if (partial != null) {
            lines.add(partial);
        }
        return joinLines(lines);
    }

    function displaysIncompleteSet() as Boolean {
        if (currentSet.isComplete) {
            return false;
        }
        if (status == MatchStatus.IN_PROGRESS) {
            return true;
        }
        if (status == MatchStatus.COMPLETED || status == MatchStatus.ENDED_EARLY) {
            return currentSet.leftGames > 0 || currentSet.rightGames > 0 || hasInProgressGameScore();
        }
        return false;
    }

    private function partialSetLineForIncompleteTerminal() as String or Null {
        if ((status != MatchStatus.ENDED_EARLY && status != MatchStatus.COMPLETED) || currentSet.isComplete) {
            return null;
        }
        if (currentSet.leftGames == 0 && currentSet.rightGames == 0 && !hasInProgressGameScore()) {
            return null;
        }
        var line = currentSet.leftGames.toString() + "-" + currentSet.rightGames.toString();
        var gameLabel = inProgressGameScoreLabel();
        if (gameLabel != null) {
            line += " (" + gameLabel + ")";
        }
        return line;
    }

    private function hasInProgressGameScore() as Boolean {
        return currentGame.leftPoints > 0 || currentGame.rightPoints > 0
            || currentGame.advantageSide != null || currentGame.isGoldenPointActive
            || currentGame.isTieBreak;
    }

    private function inProgressGameScoreLabel() as String or Null {
        if (!hasInProgressGameScore()) {
            return null;
        }
        var pair = gameDisplayPair();
        return pair[0] + "-" + pair[1];
    }

    private function joinLines(lines as Array<String>) as String {
        var result = "";
        for (var i = 0; i < lines.size(); i += 1) {
            if (i > 0) {
                result += ", ";
            }
            result += lines[i];
        }
        return result;
    }
}

function oppositeSide(side as Side) as Side {
    return side == Side.LEFT ? Side.RIGHT : Side.LEFT;
}

function statusDisplayName(status as MatchStatus) as String {
    if (status == MatchStatus.IN_PROGRESS) {
        return "In Progress";
    } else if (status == MatchStatus.COMPLETED) {
        return "Completed";
    } else if (status == MatchStatus.ENDED_EARLY) {
        return "Ended Early";
    }
    return "Discarded";
}

function sideDisplayName(side as Side) as String {
    return side == Side.LEFT ? "Us" : "Them";
}
