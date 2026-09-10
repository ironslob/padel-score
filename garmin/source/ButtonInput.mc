import Toybox.Lang;
import Toybox.System;
import Toybox.WatchUi;

// Physical-button scoring and navigation for MIP / no-touch Garmin watches,
// and an optional gloves mode on hybrid touch + button devices.
module ButtonInput {
    const SCORING_AUTO = 0;
    const SCORING_ON = 1;
    const SCORING_OFF = 2;

    function isTouchScreen() as Boolean {
        return System.getDeviceSettings().isTouchScreen;
    }

    // Menus need a highlight + Select path when there is no usable touchscreen.
    function needsButtonNav() as Boolean {
        return !isTouchScreen();
    }

    // Up/Down award points when there is no touchscreen, or when the user
    // turns the setting On (gloves / rain on Fenix-class watches).
    // Off is ignored on button-only hardware — there is no other way to score.
    function buttonScoringActive(mode as Number) as Boolean {
        if (!isTouchScreen()) {
            return true;
        }
        return mode == SCORING_ON;
    }

    function cycleScoringMode(mode as Number) as Number {
        if (mode == SCORING_AUTO) {
            return SCORING_ON;
        }
        if (mode == SCORING_ON) {
            return SCORING_OFF;
        }
        return SCORING_AUTO;
    }

    function scoringModeLabel(mode as Number) as String {
        if (mode == SCORING_ON) {
            return "Buttons: On";
        }
        if (mode == SCORING_OFF) {
            return "Buttons: Off";
        }
        return "Buttons: Auto";
    }

    function clampScoringMode(raw as Number) as Number {
        if (raw == SCORING_ON || raw == SCORING_OFF) {
            return raw;
        }
        return SCORING_AUTO;
    }
}

function keyIsUp(keyEvent as WatchUi.KeyEvent) as Boolean {
    return keyEvent.getKey() == WatchUi.KEY_UP;
}

function keyIsDown(keyEvent as WatchUi.KeyEvent) as Boolean {
    return keyEvent.getKey() == WatchUi.KEY_DOWN;
}

function keyIsSelect(keyEvent as WatchUi.KeyEvent) as Boolean {
    return keyEvent.getKey() == WatchUi.KEY_ENTER;
}
