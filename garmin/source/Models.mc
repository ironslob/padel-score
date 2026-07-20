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
    DISCARD
}

class MatchSettings {
    var setsToWin as Number;
    var continuousPlay as Boolean;
    var gamesToWinSet as Number;
    var mustWinByTwoGames as Boolean;
    var goldenPointEnabled as Boolean;
    var askServeAtSetStart as Boolean;
    var fixedServerPositions as Boolean;
    var usThemLabels as Boolean;

    static const QUICK_UNDO_TIMEOUT_MS = 3000;
    static const INACTIVITY_TIMEOUT_MS = 30 * 60 * 1000;

    function initialize() {
        setsToWin = 2;
        continuousPlay = false;
        gamesToWinSet = 6;
        mustWinByTwoGames = true;
        goldenPointEnabled = true;
        askServeAtSetStart = false;
        fixedServerPositions = false;
        usThemLabels = true;
    }

    function copy() as MatchSettings {
        var s = new MatchSettings();
        s.setsToWin = setsToWin;
        s.continuousPlay = continuousPlay;
        s.gamesToWinSet = gamesToWinSet;
        s.mustWinByTwoGames = mustWinByTwoGames;
        s.goldenPointEnabled = goldenPointEnabled;
        s.askServeAtSetStart = askServeAtSetStart;
        s.fixedServerPositions = fixedServerPositions;
        s.usThemLabels = usThemLabels;
        return s;
    }
}

class GameScore {
    var leftPoints as Number;
    var rightPoints as Number;
    var advantageSide as Side or Null;
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

    function displayPair() as Array<String> {
        if (isComplete) {
            return ["0", "0"] as Array<String>;
        }
        if (isTieBreak) {
            return [leftPoints.toString(), rightPoints.toString()] as Array<String>;
        }
        if (isGoldenPointActive) {
            return ["GP", "GP"] as Array<String>;
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

    function statusLine() as String or Null {
        if (isTieBreak) {
            return "Tie-break";
        }
        if (isGoldenPointActive) {
            return "Golden Point";
        }
        if (advantageSide != null) {
            return "Advantage";
        }
        if (leftPoints >= 3 && rightPoints >= 3) {
            return "Deuce";
        }
        return null;
    }

    function tieBreakNotice(fixedServerPositions as Boolean) as String or Null {
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
        if (total % 2 == 1 && !fixedServerPositions) {
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

    function initialize(id as String, settings as MatchSettings, startedAt as Number) {
        self.id = id;
        self.settings = settings;
        self.status = MatchStatus.IN_PROGRESS;
        self.events = [] as Array<MatchEvent>;
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
    }

    function hasScoredPoints() as Boolean {
        for (var i = 0; i < events.size(); i += 1) {
            if (events[i].kind == MatchEventKind.POINT_WON) {
                return true;
            }
        }
        return false;
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
        return (now - lastScoringActivityAt()) >= MatchSettings.INACTIVITY_TIMEOUT_MS;
    }

    function matchSetsDisplay() as Array<String> {
        return [leftSetsWon.toString(), rightSetsWon.toString()] as Array<String>;
    }

    function servingRoleLabels() as Array<String> {
        if (settings.usThemLabels) {
            return ["Us", "Them"] as Array<String>;
        }
        if (currentServer == Side.LEFT) {
            return ["Serving", "Receiving"] as Array<String>;
        } else if (currentServer == Side.RIGHT) {
            return ["Receiving", "Serving"] as Array<String>;
        }
        return ["", ""] as Array<String>;
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
        var pair = currentGame.displayPair();
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
