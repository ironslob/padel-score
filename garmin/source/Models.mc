// Domain constants and enums — ported from shared/Models/

import Toybox.Lang;

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

// How a game is resolved once both sides reach 40.
// DEUCE_ADVANTAGE: traditional advantage until two clear.
// DEUCE_SILVER_POINT: one advantage, then decisive point if broken.
// DEUCE_GOLDEN_POINT: first point at 40-40 wins.
// DEUCE_STAR_POINT: two advantages, then decisive point if the second is broken.
// Appended at the end so existing integer values stay stable; UI order is via
// deuceFormatOrder() (Regular → Star → Silver → Golden).
enum DeuceFormat {
    DEUCE_ADVANTAGE,
    DEUCE_SILVER_POINT,
    DEUCE_GOLDEN_POINT,
    DEUCE_STAR_POINT
}

enum MatchSetFormat {
    SET_FORMAT_BEST_OF_ONE,
    SET_FORMAT_BEST_OF_THREE,
    SET_FORMAT_BEST_OF_FIVE,
    SET_FORMAT_CONTINUOUS,
    // Appended so existing integer preference values 0–3 stay stable.
    SET_FORMAT_BEST_OF_THREE_MATCH_TB
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
    // When true, the deciding set is a 10-point match tie-break.
    var decidingSetIsMatchTieBreak as Boolean;
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
        decidingSetIsMatchTieBreak = false;
        deuceFormat = DEUCE_STAR_POINT;
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
        s.decidingSetIsMatchTieBreak = decidingSetIsMatchTieBreak;
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

class GameScore {
    var leftPoints as Number;
    var rightPoints as Number;
    var advantageSide as Side or Null;
    // True while a single decisive rally is in progress under any capped deuce
    // format (golden at 40-40, silver after one broken advantage, star after two).
    // Historical name kept for archive compatibility.
    var isGoldenPointActive as Boolean;
    // How many times advantage has been broken in this game. Reconstructed by
    // replay; used by capped formats to know when the next rally decides.
    var brokenAdvantageCount as Number;
    var isTieBreak as Boolean;
    var isComplete as Boolean;
    var winner as Side or Null;

    function initialize() {
        leftPoints = 0;
        rightPoints = 0;
        advantageSide = null;
        isGoldenPointActive = false;
        brokenAdvantageCount = 0;
        isTieBreak = false;
        isComplete = false;
        winner = null;
    }

    function pointsFor(side as Side) as Number {
        return side == LEFT ? leftPoints : rightPoints;
    }

    function setPoints(value as Number, side as Side) as Void {
        if (side == LEFT) {
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
            if (advantageSide == LEFT) {
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
            if (deuceFormatNumbersDeuceCycles(deuceFormat)) {
                return "Advantage " + (brokenAdvantageCount + 1).toString();
            }
            return "Advantage";
        }
        if (leftPoints >= 3 && rightPoints >= 3) {
            if (deuceFormatNumbersDeuceCycles(deuceFormat)) {
                return "Deuce " + (brokenAdvantageCount + 1).toString();
            }
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
        return side == LEFT ? leftGames : rightGames;
    }

    function setGames(value as Number, side as Side) as Void {
        if (side == LEFT) {
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
        self.status = IN_PROGRESS;
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
            if (events[i].kind == POINT_WON) {
                return true;
            }
        }
        return false;
    }

    function isAtSetStart() as Boolean {
        return currentSet.leftGames == 0 && currentSet.rightGames == 0
            && currentGame.leftPoints == 0 && currentGame.rightPoints == 0
            && currentGame.advantageSide == null && !currentGame.isGoldenPointActive
            && currentGame.brokenAdvantageCount == 0
            && !currentGame.isComplete;
    }

    // A 10-point match/super tie-break used as the deciding set (game TB at 0–0).
    function isMatchTieBreak() as Boolean {
        return currentGame.isTieBreak && currentSet.leftGames == 0 && currentSet.rightGames == 0;
    }

    function canChooseNewServer() as Boolean {
        return status == IN_PROGRESS && !needsServerSelection && isAtSetStart()
            && completedSets.size() > 0;
    }

    function isWaitingForFirstServe() as Boolean {
        return status == IN_PROGRESS && needsServerSelection && isAtSetStart()
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
            if (events[i].kind == POINT_WON) {
                return events[i].timestamp;
            }
        }
        return startedAt;
    }

    function isInactive(now as Number) as Boolean {
        if (status != IN_PROGRESS) {
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
            return [LEFT, RIGHT] as Array<Side>;
        }
        if (currentServer == RIGHT) {
            return [RIGHT, LEFT] as Array<Side>;
        }
        return [LEFT, RIGHT] as Array<Side>;
    }

    // Game point labels for the current game, using this match's deuce format.
    function gameDisplayPair() as Array<String> {
        return currentGame.displayPair(settings.deuceFormat);
    }

    // Status line for the current game ("Deuce", "Golden Point", …), or null.
    function gameStatusLine() as String or Null {
        if (isMatchTieBreak()) {
            return "Super TB";
        }
        return currentGame.statusLine(settings.deuceFormat);
    }

    function scoreScreenGameDisplay() as Array<String> {
        return remapForScoreScreen(gameDisplayPair());
    }

    function scoreScreenSetDisplay() as Array<String> {
        if (isMatchTieBreak()) {
            return remapForScoreScreen(matchSetsDisplay());
        }
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
        return visual == LEFT ? sides[0] : sides[1];
    }

    function visualSideForLogical(logical as Side) as Side {
        var sides = scoreScreenSides();
        return sides[0] == logical ? LEFT : RIGHT;
    }

    private function remapForScoreScreen(pair as Array<String>) as Array<String> {
        if (settings.fixedServerPositions) {
            return pair;
        }
        if (currentServer == RIGHT) {
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
        if (status == IN_PROGRESS || status == ENDED_EARLY || status == COMPLETED) {
            if (!currentSet.isComplete) {
                if (isMatchTieBreak()) {
                    lines.add(currentGame.leftPoints.toString() + "-" + currentGame.rightPoints.toString());
                } else {
                    lines.add(currentSet.leftGames.toString() + "-" + currentSet.rightGames.toString());
                }
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
        if (status == IN_PROGRESS) {
            return true;
        }
        if (status == COMPLETED || status == ENDED_EARLY) {
            return currentSet.leftGames > 0 || currentSet.rightGames > 0 || hasInProgressGameScore();
        }
        return false;
    }

    private function partialSetLineForIncompleteTerminal() as String or Null {
        if ((status != ENDED_EARLY && status != COMPLETED) || currentSet.isComplete) {
            return null;
        }
        if (currentSet.leftGames == 0 && currentSet.rightGames == 0 && !hasInProgressGameScore()) {
            return null;
        }
        if (isMatchTieBreak()) {
            return currentGame.leftPoints.toString() + "-" + currentGame.rightPoints.toString();
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

// Module-level helpers live after enums and classes (Monkey C compile order).
function deuceFormatToString(format as DeuceFormat) as String {
    if (format == DEUCE_ADVANTAGE) {
        return "advantage";
    } else if (format == DEUCE_SILVER_POINT) {
        return "silverPoint";
    } else if (format == DEUCE_STAR_POINT) {
        return "starPoint";
    } else if (format == DEUCE_GOLDEN_POINT) {
        return "goldenPoint";
    }
    return "goldenPoint";
}

function deuceFormatFromString(raw as String or Null) as DeuceFormat or Null {
    if (raw == null) {
        return null;
    }
    if (raw.equals("advantage")) {
        return DEUCE_ADVANTAGE;
    } else if (raw.equals("silverPoint")) {
        return DEUCE_SILVER_POINT;
    } else if (raw.equals("goldenPoint")) {
        return DEUCE_GOLDEN_POINT;
    } else if (raw.equals("starPoint")) {
        return DEUCE_STAR_POINT;
    }
    return null;
}

function deuceFormatFromLegacyArchivedFlag(goldenPointEnabled as Boolean) as DeuceFormat {
    return goldenPointEnabled ? DEUCE_SILVER_POINT : DEUCE_ADVANTAGE;
}

function deuceFormatFromLegacyPreference(goldenPointEnabled as Boolean or Null) as DeuceFormat {
    if (goldenPointEnabled != null && !goldenPointEnabled) {
        return DEUCE_ADVANTAGE;
    }
    return DEUCE_STAR_POINT;
}

function deuceFormatLabel(format as DeuceFormat) as String {
    if (format == DEUCE_ADVANTAGE) {
        return "Regular";
    } else if (format == DEUCE_STAR_POINT) {
        return "Star";
    } else if (format == DEUCE_SILVER_POINT) {
        return "Silver";
    }
    return "Golden";
}

function deuceFormatDecidingPointLabel(format as DeuceFormat) as String {
    if (format == DEUCE_ADVANTAGE) {
        return "Deuce";
    } else if (format == DEUCE_STAR_POINT) {
        return "Star Point";
    } else if (format == DEUCE_SILVER_POINT) {
        return "Silver Point";
    }
    return "Golden Point";
}

function deuceFormatDecidingPointShortLabel(format as DeuceFormat) as String {
    if (format == DEUCE_ADVANTAGE) {
        return "40";
    } else if (format == DEUCE_STAR_POINT) {
        return "ST";
    } else if (format == DEUCE_SILVER_POINT) {
        return "SP";
    }
    return "GP";
}

// Cap: null/negative means unlimited (regular). 0 = golden, 1 = silver, 2 = star.
function deuceFormatAdvantagesBeforeDecidingPoint(format as DeuceFormat) as Number or Null {
    if (format == DEUCE_STAR_POINT) {
        return 2;
    } else if (format == DEUCE_SILVER_POINT) {
        return 1;
    } else if (format == DEUCE_GOLDEN_POINT) {
        return 0;
    }
    return null;
}

function deuceFormatDecidesGame(format as DeuceFormat, brokenAdvantages as Number) as Boolean {
    var cap = deuceFormatAdvantagesBeforeDecidingPoint(format);
    if (cap == null) {
        return false;
    }
    return brokenAdvantages >= (cap as Number);
}

function deuceFormatNumbersDeuceCycles(format as DeuceFormat) as Boolean {
    var cap = deuceFormatAdvantagesBeforeDecidingPoint(format);
    return cap != null && (cap as Number) > 1;
}

// Picker order: Regular → Star → Silver → Golden (most advantages to fewest).
function deuceFormatOrder() as Array<DeuceFormat> {
    return [
        DEUCE_ADVANTAGE,
        DEUCE_STAR_POINT,
        DEUCE_SILVER_POINT,
        DEUCE_GOLDEN_POINT
    ] as Array<DeuceFormat>;
}

function deuceFormatAfter(current as DeuceFormat) as DeuceFormat {
    var order = deuceFormatOrder();
    for (var i = 0; i < order.size(); i += 1) {
        if (order[i] == current) {
            return order[(i + 1) % order.size()];
        }
    }
    return order[0];
}

function matchSetFormatFromSettings(settings as MatchSettings) as MatchSetFormat {
    if (settings.continuousPlay) {
        return SET_FORMAT_CONTINUOUS;
    }
    if (settings.setsToWin == 1) {
        return SET_FORMAT_BEST_OF_ONE;
    }
    if (settings.setsToWin == 3) {
        return SET_FORMAT_BEST_OF_FIVE;
    }
    if (settings.decidingSetIsMatchTieBreak) {
        return SET_FORMAT_BEST_OF_THREE_MATCH_TB;
    }
    return SET_FORMAT_BEST_OF_THREE;
}

function applyMatchSetFormat(settings as MatchSettings, format as MatchSetFormat) as Void {
    if (format == SET_FORMAT_BEST_OF_ONE) {
        settings.setsToWin = 1;
        settings.continuousPlay = false;
        settings.decidingSetIsMatchTieBreak = false;
    } else if (format == SET_FORMAT_BEST_OF_THREE_MATCH_TB) {
        settings.setsToWin = 2;
        settings.continuousPlay = false;
        settings.decidingSetIsMatchTieBreak = true;
    } else if (format == SET_FORMAT_BEST_OF_FIVE) {
        settings.setsToWin = 3;
        settings.continuousPlay = false;
        settings.decidingSetIsMatchTieBreak = false;
    } else if (format == SET_FORMAT_CONTINUOUS) {
        settings.continuousPlay = true;
        settings.decidingSetIsMatchTieBreak = false;
    } else {
        settings.setsToWin = 2;
        settings.continuousPlay = false;
        settings.decidingSetIsMatchTieBreak = false;
    }
}

function matchSetFormatLabel(format as MatchSetFormat) as String {
    if (format == SET_FORMAT_BEST_OF_ONE) {
        return "1 set";
    } else if (format == SET_FORMAT_BEST_OF_THREE_MATCH_TB) {
        return "2 sets + TB";
    } else if (format == SET_FORMAT_BEST_OF_FIVE) {
        return "Best of 5";
    } else if (format == SET_FORMAT_CONTINUOUS) {
        return "Continuous";
    }
    return "Best of 3";
}

function nextMatchSetFormat(format as MatchSetFormat) as MatchSetFormat {
    if (format == SET_FORMAT_BEST_OF_ONE) {
        return SET_FORMAT_BEST_OF_THREE;
    } else if (format == SET_FORMAT_BEST_OF_THREE) {
        return SET_FORMAT_BEST_OF_THREE_MATCH_TB;
    } else if (format == SET_FORMAT_BEST_OF_THREE_MATCH_TB) {
        return SET_FORMAT_BEST_OF_FIVE;
    } else if (format == SET_FORMAT_BEST_OF_FIVE) {
        return SET_FORMAT_CONTINUOUS;
    }
    return SET_FORMAT_BEST_OF_ONE;
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

function oppositeSide(side as Side) as Side {
    return side == LEFT ? RIGHT : LEFT;
}

function statusDisplayName(status as MatchStatus) as String {
    if (status == IN_PROGRESS) {
        return "In Progress";
    } else if (status == COMPLETED) {
        return "Completed";
    } else if (status == ENDED_EARLY) {
        return "Ended Early";
    }
    return "Discarded";
}

function sideDisplayName(side as Side) as String {
    return side == LEFT ? "Us" : "Them";
}
