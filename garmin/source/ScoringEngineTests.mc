import Toybox.Lang;
import Toybox.Test;

// Scoring engine smoke tests — run via Monkey C: Run Tests or CI (matco/connectiq-tester).

(:test)
function testLoveToGame(logger as Logger) as Boolean {
    var engine = new ScoringEngine();
    var settings = new MatchSettings();
    var state = engine.startMatch(settings, "test-1", 0);
    state = engine.applySelectServer(state, Side.LEFT, 1);
    Test.assertNotEqual(null, state);
    state = engine.applyPointWon(state, Side.LEFT, 2);
    state = engine.applyPointWon(state, Side.LEFT, 3);
    state = engine.applyPointWon(state, Side.LEFT, 4);
    state = engine.applyPointWon(state, Side.LEFT, 5);
    Test.assertEqual(1, state.currentSet.leftGames);
    return true;
}

// Starts a match pinned to a deuce format and plays to 40-40 without ever
// putting a side above 40.
function startAtDeuce(engine as ScoringEngine, format as DeuceFormat, id as String) as MatchState {
    var settings = new MatchSettings();
    settings.deuceFormat = format;
    // Matches the Swift suite's rotatingSettings, so both sides exercise the
    // same serve-rotation path.
    settings.fixedServerPositions = false;
    var state = engine.startMatch(settings, id, 0);
    state = engine.applySelectServer(state, Side.LEFT, 1);
    var t = 2;
    for (var i = 0; i < 3; i += 1) {
        state = engine.applyPointWon(state, Side.LEFT, t);
        t += 1;
        state = engine.applyPointWon(state, Side.RIGHT, t);
        t += 1;
    }
    return state;
}

(:test)
function testAdvantageWinsGameWhenHeld(logger as Logger) as Boolean {
    var engine = new ScoringEngine();
    var state = startAtDeuce(engine, DeuceFormat.DEUCE_ADVANTAGE, "test-adv-1");
    Test.assertEqual("Deuce", state.gameStatusLine());
    Test.assert(!state.currentGame.isGoldenPointActive);

    state = engine.applyPointWon(state, Side.LEFT, 30);
    Test.assertEqual(Side.LEFT, state.currentGame.advantageSide);
    Test.assertEqual("Advantage", state.gameStatusLine());

    state = engine.applyPointWon(state, Side.LEFT, 31);
    Test.assertEqual(1, state.currentSet.leftGames);
    return true;
}

(:test)
function testAdvantageCyclesIndefinitely(logger as Logger) as Boolean {
    var engine = new ScoringEngine();
    var state = startAtDeuce(engine, DeuceFormat.DEUCE_ADVANTAGE, "test-adv-2");
    var t = 30;
    // Three full advantage-then-broken cycles must never become decisive.
    for (var i = 0; i < 3; i += 1) {
        state = engine.applyPointWon(state, Side.LEFT, t);
        t += 1;
        Test.assertEqual(Side.LEFT, state.currentGame.advantageSide);
        state = engine.applyPointWon(state, Side.RIGHT, t);
        t += 1;
        Test.assertEqual(null, state.currentGame.advantageSide);
        Test.assert(!state.currentGame.isGoldenPointActive);
        Test.assertEqual("Deuce", state.gameStatusLine());
    }
    Test.assertEqual(0, state.currentSet.leftGames);
    Test.assertEqual(0, state.currentSet.rightGames);
    return true;
}

(:test)
function testGoldenPointIsDecisiveImmediatelyAtDeuce(logger as Logger) as Boolean {
    var engine = new ScoringEngine();
    var state = startAtDeuce(engine, DeuceFormat.DEUCE_GOLDEN_POINT, "test-gp-1");
    // No advantage phase at all: 40-40 is already the deciding rally.
    Test.assert(state.currentGame.isGoldenPointActive);
    Test.assertEqual(null, state.currentGame.advantageSide);
    Test.assertEqual("Golden Point", state.gameStatusLine());
    var pair = state.gameDisplayPair();
    Test.assertEqual("GP", pair[0]);
    Test.assertEqual("GP", pair[1]);

    state = engine.applyPointWon(state, Side.RIGHT, 30);
    Test.assertEqual(1, state.currentSet.rightGames);
    Test.assertEqual(0, state.currentSet.leftGames);
    Test.assert(!state.currentGame.isGoldenPointActive);
    return true;
}

(:test)
function testGoldenPointNeverAwardsAdvantage(logger as Logger) as Boolean {
    var engine = new ScoringEngine();
    var state = startAtDeuce(engine, DeuceFormat.DEUCE_GOLDEN_POINT, "test-gp-2");
    state = engine.applyPointWon(state, Side.LEFT, 30);
    // The game is over — the point did not become an advantage.
    Test.assertEqual(1, state.currentSet.leftGames);
    Test.assertEqual(null, state.currentGame.advantageSide);
    return true;
}

(:test)
function testGoldenPointReachedFromUnevenScoreline(logger as Logger) as Boolean {
    // 40-30 → 40-40 must arm the deciding point just the same.
    var engine = new ScoringEngine();
    var settings = new MatchSettings();
    settings.deuceFormat = DeuceFormat.DEUCE_GOLDEN_POINT;
    settings.fixedServerPositions = false;
    var state = engine.startMatch(settings, "test-gp-3", 0);
    state = engine.applySelectServer(state, Side.LEFT, 1);
    state = engine.applyPointWon(state, Side.LEFT, 2);
    state = engine.applyPointWon(state, Side.LEFT, 3);
    state = engine.applyPointWon(state, Side.LEFT, 4); // 40-0
    state = engine.applyPointWon(state, Side.RIGHT, 5);
    state = engine.applyPointWon(state, Side.RIGHT, 6); // 40-30
    Test.assert(!state.currentGame.isGoldenPointActive);
    state = engine.applyPointWon(state, Side.RIGHT, 7); // 40-40
    Test.assert(state.currentGame.isGoldenPointActive);
    return true;
}

(:test)
function testSilverPointPlaysOneAdvantageThenDecides(logger as Logger) as Boolean {
    var engine = new ScoringEngine();
    var state = startAtDeuce(engine, DeuceFormat.DEUCE_SILVER_POINT, "test-sp-1");
    Test.assert(!state.currentGame.isGoldenPointActive);
    Test.assertEqual("Deuce", state.gameStatusLine());

    state = engine.applyPointWon(state, Side.LEFT, 30); // Ad left
    Test.assertEqual(Side.LEFT, state.currentGame.advantageSide);
    Test.assert(!state.currentGame.isGoldenPointActive);

    state = engine.applyPointWon(state, Side.RIGHT, 31); // broken → deciding point
    Test.assert(state.currentGame.isGoldenPointActive);
    Test.assertEqual(null, state.currentGame.advantageSide);
    Test.assertEqual("Silver Point", state.gameStatusLine());
    var pair = state.gameDisplayPair();
    Test.assertEqual("SP", pair[0]);
    Test.assertEqual("SP", pair[1]);

    state = engine.applyPointWon(state, Side.RIGHT, 32);
    Test.assertEqual(1, state.currentSet.rightGames);
    Test.assert(!state.currentGame.isGoldenPointActive);
    return true;
}

(:test)
function testSilverPointAdvantageHolderStillWinsOnSecondPoint(logger as Logger) as Boolean {
    var engine = new ScoringEngine();
    var state = startAtDeuce(engine, DeuceFormat.DEUCE_SILVER_POINT, "test-sp-2");
    state = engine.applyPointWon(state, Side.LEFT, 30); // Ad left
    state = engine.applyPointWon(state, Side.LEFT, 31); // converts, no decider needed
    Test.assertEqual(1, state.currentSet.leftGames);
    return true;
}

(:test)
function testSilverPointDecidingPointWinnableByEitherSide(logger as Logger) as Boolean {
    var engine = new ScoringEngine();
    var state = startAtDeuce(engine, DeuceFormat.DEUCE_SILVER_POINT, "test-sp-4");
    state = engine.applyPointWon(state, Side.RIGHT, 30); // Ad right
    state = engine.applyPointWon(state, Side.LEFT, 31); // broken → deciding point
    Test.assert(state.currentGame.isGoldenPointActive);
    state = engine.applyPointWon(state, Side.LEFT, 32);
    Test.assertEqual(1, state.currentSet.leftGames);
    return true;
}

(:test)
function testUndoSilverPointReturnsToAdvantage(logger as Logger) as Boolean {
    var engine = new ScoringEngine();
    var state = startAtDeuce(engine, DeuceFormat.DEUCE_SILVER_POINT, "test-sp-3");
    state = engine.applyPointWon(state, Side.LEFT, 30);
    state = engine.applyPointWon(state, Side.RIGHT, 31);
    Test.assert(state.currentGame.isGoldenPointActive);
    state = engine.applyUndo(state);
    Test.assert(!state.currentGame.isGoldenPointActive);
    Test.assertEqual(Side.LEFT, state.currentGame.advantageSide);
    return true;
}

(:test)
function testUndoGoldenPointReturnsToFortyThirty(logger as Logger) as Boolean {
    var engine = new ScoringEngine();
    var state = startAtDeuce(engine, DeuceFormat.DEUCE_GOLDEN_POINT, "test-gp-4");
    Test.assert(state.currentGame.isGoldenPointActive);
    state = engine.applyUndo(state);
    Test.assert(!state.currentGame.isGoldenPointActive);
    var pair = state.gameDisplayPair();
    Test.assertEqual("40", pair[0]);
    Test.assertEqual("30", pair[1]);
    return true;
}

(:test)
function testUndoRemovesLastPoint(logger as Logger) as Boolean {
    var engine = new ScoringEngine();
    var settings = new MatchSettings();
    var state = engine.startMatch(settings, "test-3", 0);
    state = engine.applySelectServer(state, Side.LEFT, 1);
    state = engine.applyPointWon(state, Side.LEFT, 2);
    state = engine.applyPointWon(state, Side.RIGHT, 3);
    state = engine.applyUndo(state);
    var pair = state.gameDisplayPair();
    Test.assertEqual("15", pair[0]);
    Test.assertEqual("0", pair[1]);
    return true;
}

(:test)
function testDeuceFormatStringRoundTrip(logger as Logger) as Boolean {
    var formats = [
        DeuceFormat.DEUCE_ADVANTAGE,
        DeuceFormat.DEUCE_SILVER_POINT,
        DeuceFormat.DEUCE_GOLDEN_POINT
    ] as Array<DeuceFormat>;
    for (var i = 0; i < formats.size(); i += 1) {
        var raw = deuceFormatToString(formats[i]);
        Test.assertEqual(formats[i], deuceFormatFromString(raw));
    }
    // Unknown and absent values fall through so callers can apply migration.
    Test.assertEqual(null, deuceFormatFromString(null));
    Test.assertEqual(null, deuceFormatFromString("nonsense"));
    return true;
}

(:test)
function testArchivedMatchesKeepSilverPointBehaviour(logger as Logger) as Boolean {
    // Matches written before this setting existed played one advantage before
    // the decisive point, so they must migrate to silver point, not golden.
    Test.assertEqual(DeuceFormat.DEUCE_SILVER_POINT, deuceFormatFromLegacyArchivedFlag(true));
    Test.assertEqual(DeuceFormat.DEUCE_ADVANTAGE, deuceFormatFromLegacyArchivedFlag(false));
    return true;
}

(:test)
function testPreferenceMigratesFromLegacyGoldenPointToggle(logger as Logger) as Boolean {
    // Deliberately different from the archived-match rule: only an explicit
    // "off" carries over, everything else lands on the new default.
    Test.assertEqual(DeuceFormat.DEUCE_ADVANTAGE, deuceFormatFromLegacyPreference(false));
    Test.assertEqual(DeuceFormat.DEUCE_GOLDEN_POINT, deuceFormatFromLegacyPreference(true));
    Test.assertEqual(DeuceFormat.DEUCE_GOLDEN_POINT, deuceFormatFromLegacyPreference(null));
    return true;
}

(:test)
function testDefaultSettingsUseGoldenPoint(logger as Logger) as Boolean {
    var settings = new MatchSettings();
    Test.assertEqual(DeuceFormat.DEUCE_GOLDEN_POINT, settings.deuceFormat);
    Test.assertEqual(DeuceFormat.DEUCE_GOLDEN_POINT, settings.copy().deuceFormat);
    return true;
}

(:test)
function testSixSixStartsTieBreak(logger as Logger) as Boolean {
    var engine = new ScoringEngine();
    var settings = new MatchSettings();
    var state = engine.startMatch(settings, "test-4", 0);
    state = engine.applySelectServer(state, Side.LEFT, 1);
    for (var set = 0; set < 6; set += 1) {
        for (var g = 0; g < 4; g += 1) {
            state = engine.applyPointWon(state, Side.LEFT, 100 + set * 10 + g);
        }
        for (var g = 0; g < 4; g += 1) {
            state = engine.applyPointWon(state, Side.RIGHT, 200 + set * 10 + g);
        }
    }
    Test.assert(state.currentGame.isTieBreak);
    Test.assertEqual(6, state.currentSet.leftGames);
    Test.assertEqual(6, state.currentSet.rightGames);
    return true;
}

(:test)
function testFinalScoreSummaryFinishMidSetIncludesPartial(logger as Logger) as Boolean {
    var engine = new ScoringEngine();
    var settings = new MatchSettings();
    var state = engine.startMatch(settings, "test-5", 0);
    state = engine.applySelectServer(state, Side.LEFT, 1);
    var t = 2;
    for (var i = 0; i < 3; i += 1) {
        for (var p = 0; p < 4; p += 1) {
            state = engine.applyPointWon(state, Side.LEFT, t);
            t += 1;
        }
    }
    for (var i = 0; i < 2; i += 1) {
        for (var p = 0; p < 4; p += 1) {
            state = engine.applyPointWon(state, Side.RIGHT, t);
            t += 1;
        }
    }
    state = engine.applyPointWon(state, Side.LEFT, t);
    t += 1;
    state = engine.applyPointWon(state, Side.LEFT, t);
    t += 1;
    state = engine.applyPointWon(state, Side.LEFT, t);
    t += 1;
    state = engine.applyPointWon(state, Side.RIGHT, t);
    t += 1;
    state = engine.applyFinish(state, t);
    Test.assertEqual(MatchStatus.COMPLETED, state.status);
    Test.assertEqual("3-2 (40-15)", state.finalScoreSummary());
    Test.assert(state.displaysIncompleteSet());
    return true;
}

(:test)
function testFinalScoreSummaryFinishMidSetAfterCompletedSet(logger as Logger) as Boolean {
    var engine = new ScoringEngine();
    var settings = new MatchSettings();
    var state = engine.startMatch(settings, "test-6", 0);
    state = engine.applySelectServer(state, Side.LEFT, 1);
    var t = 2;
    for (var g = 0; g < 6; g += 1) {
        for (var p = 0; p < 4; p += 1) {
            state = engine.applyPointWon(state, Side.LEFT, t);
            t += 1;
        }
    }
    for (var i = 0; i < 3; i += 1) {
        for (var p = 0; p < 4; p += 1) {
            state = engine.applyPointWon(state, Side.LEFT, t);
            t += 1;
        }
    }
    for (var i = 0; i < 2; i += 1) {
        for (var p = 0; p < 4; p += 1) {
            state = engine.applyPointWon(state, Side.RIGHT, t);
            t += 1;
        }
    }
    state = engine.applyPointWon(state, Side.LEFT, t);
    t += 1;
    state = engine.applyPointWon(state, Side.LEFT, t);
    t += 1;
    state = engine.applyPointWon(state, Side.RIGHT, t);
    t += 1;
    state = engine.applyFinish(state, t);
    Test.assertEqual(MatchStatus.COMPLETED, state.status);
    Test.assertEqual("6-0, 3-2 (30-15)", state.finalScoreSummary());
    Test.assert(state.displaysIncompleteSet());
    return true;
}

(:test)
function testScoreScreenSidesSwapWhenServeRotates(logger as Logger) as Boolean {
    var engine = new ScoringEngine();
    var settings = new MatchSettings();
    settings.fixedServerPositions = false;
    var state = engine.startMatch(settings, "test-7", 0);
    state = engine.applySelectServer(state, Side.LEFT, 1);
    Test.assertEqual(Side.LEFT, state.scoreScreenSides()[0]);
    Test.assertEqual("Us", state.servingRoleLabels()[0]);
    Test.assertEqual("Them", state.servingRoleLabels()[1]);

    for (var p = 0; p < 4; p += 1) {
        state = engine.applyPointWon(state, Side.LEFT, 10 + p);
    }
    Test.assertEqual(Side.RIGHT, state.currentServer);
    Test.assertEqual(Side.RIGHT, state.scoreScreenSides()[0]);
    Test.assertEqual("Them", state.servingRoleLabels()[0]);
    Test.assertEqual("Us", state.servingRoleLabels()[1]);
    Test.assertEqual(Side.RIGHT, state.logicalSideForVisual(Side.LEFT));
    return true;
}

(:test)
function testFixedServerPositionsRotatesServeButKeepsLayout(logger as Logger) as Boolean {
    var engine = new ScoringEngine();
    var settings = new MatchSettings();
    settings.fixedServerPositions = true;
    var state = engine.startMatch(settings, "test-8", 0);
    state = engine.applySelectServer(state, Side.LEFT, 1);
    for (var p = 0; p < 4; p += 1) {
        state = engine.applyPointWon(state, Side.LEFT, 10 + p);
    }
    Test.assertEqual(Side.RIGHT, state.currentServer);
    Test.assertEqual(Side.LEFT, state.scoreScreenSides()[0]);
    Test.assertEqual(Side.RIGHT, state.scoreScreenSides()[1]);
    Test.assertEqual("Us", state.servingRoleLabels()[0]);
    Test.assertEqual("Them", state.servingRoleLabels()[1]);
    return true;
}
