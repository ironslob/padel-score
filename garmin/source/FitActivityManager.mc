import Toybox.Activity;
import Toybox.ActivityRecording;
import Toybox.FitContributor;
import Toybox.Lang;
import Toybox.System;

// FIT session owner for a live match — Garmin equivalent of HealthKit / Health Services.

class FitActivityManager {
    private const FIELD_MATCH_SCORE = 0;
    private const FIELD_SETS_US = 1;
    private const FIELD_SETS_THEM = 2;
    private const SCORE_FIELD_COUNT = 64;

    private var session as ActivityRecording.Session or Null;
    private var matchScoreField as FitContributor.Field or Null;
    private var setsUsField as FitContributor.Field or Null;
    private var setsThemField as FitContributor.Field or Null;

    function initialize() {
        session = null;
        matchScoreField = null;
        setsUsField = null;
        setsThemField = null;
    }

    function isRecording() as Boolean {
        return session != null && session.isRecording();
    }

    function startSession() as Boolean {
        if (isRecording()) {
            return true;
        }
        if (!(Toybox has :ActivityRecording)) {
            return false;
        }
        if (anotherActivityIsRecording()) {
            return false;
        }

        endSession(false);

        try {
            session = createPadelSession();
            if (session == null) {
                return false;
            }
            createFields();
            if (!session.start()) {
                endSession(false);
                return false;
            }
            return true;
        } catch (ex) {
            System.println("FitActivityManager.startSession failed: " + ex.getErrorMessage());
            endSession(false);
            return false;
        }
    }

    function updateScore(match as MatchState) as Void {
        if (session == null || !session.isRecording()) {
            return;
        }
        if (matchScoreField != null) {
            matchScoreField.setData(joinScoreLines(match.setScoreLines()));
        }
        if (setsUsField != null) {
            setsUsField.setData(match.leftSetsWon);
        }
        if (setsThemField != null) {
            setsThemField.setData(match.rightSetsWon);
        }
    }

    function addLap() as Void {
        if (session == null || !session.isRecording()) {
            return;
        }
        session.addLap();
    }

    function endSession(save as Boolean) as Void {
        if (session == null) {
            clearFields();
            return;
        }
        try {
            if (session.isRecording()) {
                session.stop();
            }
            if (save) {
                session.save();
            } else {
                session.discard();
            }
        } catch (ex) {
            System.println("FitActivityManager.endSession failed: " + ex.getErrorMessage());
        }
        session = null;
        clearFields();
    }

    private function createPadelSession() as ActivityRecording.Session or Null {
        var sport = Activity.SPORT_TENNIS;
        var subSport = Activity.SUB_SPORT_MATCH;
        if (Activity has :SUB_SPORT_PADEL) {
            subSport = Activity.SUB_SPORT_PADEL;
        }

        try {
            return ActivityRecording.createSession({
                :name => "Padel",
                :sport => sport,
                :subSport => subSport
            });
        } catch (ex) {
            System.println("createSession padel/match failed, falling back: " + ex.getErrorMessage());
            try {
                return ActivityRecording.createSession({
                    :name => "Padel",
                    :sport => Activity.SPORT_TENNIS,
                    :subSport => Activity.SUB_SPORT_MATCH
                });
            } catch (ex2) {
                System.println("createSession tennis/match failed: " + ex2.getErrorMessage());
                return null;
            }
        }
    }

    private function createFields() as Void {
        if (session == null) {
            return;
        }
        matchScoreField = session.createField(
            "match_score",
            FIELD_MATCH_SCORE,
            FitContributor.DATA_TYPE_STRING,
            {
                :mesgType => FitContributor.MESG_TYPE_SESSION,
                :count => SCORE_FIELD_COUNT
            }
        );
        setsUsField = session.createField(
            "sets_us",
            FIELD_SETS_US,
            FitContributor.DATA_TYPE_UINT8,
            {
                :mesgType => FitContributor.MESG_TYPE_SESSION,
                :units => "sets"
            }
        );
        setsThemField = session.createField(
            "sets_them",
            FIELD_SETS_THEM,
            FitContributor.DATA_TYPE_UINT8,
            {
                :mesgType => FitContributor.MESG_TYPE_SESSION,
                :units => "sets"
            }
        );
        matchScoreField.setData("");
        setsUsField.setData(0);
        setsThemField.setData(0);
    }

    private function clearFields() as Void {
        matchScoreField = null;
        setsUsField = null;
        setsThemField = null;
    }

    private function anotherActivityIsRecording() as Boolean {
        if (!(Toybox has :Activity)) {
            return false;
        }
        try {
            var info = Activity.getActivityInfo();
            if (info == null || info.timerState == null) {
                return false;
            }
            return info.timerState == Activity.TIMER_STATE_ON
                || info.timerState == Activity.TIMER_STATE_PAUSED;
        } catch (ex) {
            return false;
        }
    }

    private function joinScoreLines(lines as Array<String>) as String {
        var result = "";
        for (var i = 0; i < lines.size(); i += 1) {
            if (i > 0) {
                result += ", ";
            }
            result += lines[i];
        }
        if (result.length() > SCORE_FIELD_COUNT) {
            var trimmed = result.substring(0, SCORE_FIELD_COUNT);
            if (trimmed != null) {
                return trimmed;
            }
        }
        return result;
    }
}
