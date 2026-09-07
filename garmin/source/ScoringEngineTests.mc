import Toybox.Lang;
import Toybox.Test;

// Scoring engine smoke tests — run via Monkey C: Run Tests or CI (matco/connectiq-tester).

(:test)
function testLoveToGame(logger as Logger) as Boolean {
    var engine = new ScoringEngine();
    var settings = new MatchSettings();
    var state = engine.startMatch(settings, "test-1", 0);
    state = engine.applySelectServer(state, LEFT, 1);
    Test.assert(state != null);
    state = engine.applyPointWon(state, LEFT, 2);
    state = engine.applyPointWon(state, LEFT, 3);
    state = engine.applyPointWon(state, LEFT, 4);
    state = engine.applyPointWon(state, LEFT, 5);
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
    state = engine.applySelectServer(state, LEFT, 1);
    var t = 2;
    for (var i = 0; i < 3; i += 1) {
        state = engine.applyPointWon(state, LEFT, t);
        t += 1;
        state = engine.applyPointWon(state, RIGHT, t);
        t += 1;
    }
    return state;
}

(:test)
function testAdvantageWinsGameWhenHeld(logger as Logger) as Boolean {
    var engine = new ScoringEngine();
    var state = startAtDeuce(engine, DEUCE_ADVANTAGE, "test-adv-1");
    Test.assertEqual("Deuce", state.gameStatusLine());
    Test.assert(!state.currentGame.isGoldenPointActive);

    state = engine.applyPointWon(state, LEFT, 30);
    Test.assertEqual(LEFT, state.currentGame.advantageSide);
    Test.assertEqual("Advantage", state.gameStatusLine());

    state = engine.applyPointWon(state, LEFT, 31);
    Test.assertEqual(1, state.currentSet.leftGames);
    return true;
}

(:test)
function testAdvantageCyclesIndefinitely(logger as Logger) as Boolean {
    var engine = new ScoringEngine();
    var state = startAtDeuce(engine, DEUCE_ADVANTAGE, "test-adv-2");
    var t = 30;
    // Three full advantage-then-broken cycles must never become decisive.
    for (var i = 0; i < 3; i += 1) {
        state = engine.applyPointWon(state, LEFT, t);
        t += 1;
        Test.assertEqual(LEFT, state.currentGame.advantageSide);
        state = engine.applyPointWon(state, RIGHT, t);
        t += 1;
        Test.assert(state.currentGame.advantageSide == null);
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
    var state = startAtDeuce(engine, DEUCE_GOLDEN_POINT, "test-gp-1");
    // No advantage phase at all: 40-40 is already the deciding rally.
    Test.assert(state.currentGame.isGoldenPointActive);
    Test.assert(state.currentGame.advantageSide == null);
    Test.assertEqual("Golden Point", state.gameStatusLine());
    var pair = state.gameDisplayPair();
    Test.assertEqual("GP", pair[0]);
    Test.assertEqual("GP", pair[1]);

    state = engine.applyPointWon(state, RIGHT, 30);
    Test.assertEqual(1, state.currentSet.rightGames);
    Test.assertEqual(0, state.currentSet.leftGames);
    Test.assert(!state.currentGame.isGoldenPointActive);
    return true;
}

(:test)
function testGoldenPointNeverAwardsAdvantage(logger as Logger) as Boolean {
    var engine = new ScoringEngine();
    var state = startAtDeuce(engine, DEUCE_GOLDEN_POINT, "test-gp-2");
    state = engine.applyPointWon(state, LEFT, 30);
    // The game is over — the point did not become an advantage.
    Test.assertEqual(1, state.currentSet.leftGames);
    Test.assert(state.currentGame.advantageSide == null);
    return true;
}

(:test)
function testGoldenPointReachedFromUnevenScoreline(logger as Logger) as Boolean {
    // 40-30 → 40-40 must arm the deciding point just the same.
    var engine = new ScoringEngine();
    var settings = new MatchSettings();
    settings.deuceFormat = DEUCE_GOLDEN_POINT;
    settings.fixedServerPositions = false;
    var state = engine.startMatch(settings, "test-gp-3", 0);
    state = engine.applySelectServer(state, LEFT, 1);
    state = engine.applyPointWon(state, LEFT, 2);
    state = engine.applyPointWon(state, LEFT, 3);
    state = engine.applyPointWon(state, LEFT, 4); // 40-0
    state = engine.applyPointWon(state, RIGHT, 5);
    state = engine.applyPointWon(state, RIGHT, 6); // 40-30
    Test.assert(!state.currentGame.isGoldenPointActive);
    state = engine.applyPointWon(state, RIGHT, 7); // 40-40
    Test.assert(state.currentGame.isGoldenPointActive);
    return true;
}

(:test)
function testSilverPointPlaysOneAdvantageThenDecides(logger as Logger) as Boolean {
    var engine = new ScoringEngine();
    var state = startAtDeuce(engine, DEUCE_SILVER_POINT, "test-sp-1");
    Test.assert(!state.currentGame.isGoldenPointActive);
    Test.assertEqual("Deuce", state.gameStatusLine());

    state = engine.applyPointWon(state, LEFT, 30); // Ad left
    Test.assertEqual(LEFT, state.currentGame.advantageSide);
    Test.assert(!state.currentGame.isGoldenPointActive);

    state = engine.applyPointWon(state, RIGHT, 31); // broken → deciding point
    Test.assert(state.currentGame.isGoldenPointActive);
    Test.assert(state.currentGame.advantageSide == null);
    Test.assertEqual("Silver Point", state.gameStatusLine());
    var pair = state.gameDisplayPair();
    Test.assertEqual("SP", pair[0]);
    Test.assertEqual("SP", pair[1]);

    state = engine.applyPointWon(state, RIGHT, 32);
    Test.assertEqual(1, state.currentSet.rightGames);
    Test.assert(!state.currentGame.isGoldenPointActive);
    return true;
}

(:test)
function testSilverPointAdvantageHolderStillWinsOnSecondPoint(logger as Logger) as Boolean {
    var engine = new ScoringEngine();
    var state = startAtDeuce(engine, DEUCE_SILVER_POINT, "test-sp-2");
    state = engine.applyPointWon(state, LEFT, 30); // Ad left
    state = engine.applyPointWon(state, LEFT, 31); // converts, no decider needed
    Test.assertEqual(1, state.currentSet.leftGames);
    return true;
}

(:test)
function testSilverPointDecidingPointWinnableByEitherSide(logger as Logger) as Boolean {
    var engine = new ScoringEngine();
    var state = startAtDeuce(engine, DEUCE_SILVER_POINT, "test-sp-4");
    state = engine.applyPointWon(state, RIGHT, 30); // Ad right
    state = engine.applyPointWon(state, LEFT, 31); // broken → deciding point
    Test.assert(state.currentGame.isGoldenPointActive);
    state = engine.applyPointWon(state, LEFT, 32);
    Test.assertEqual(1, state.currentSet.leftGames);
    return true;
}

(:test)
function testSilverPointStatusLinesAreNotNumbered(logger as Logger) as Boolean {
    // One advantage needs no counting, so silver keeps the plain labels.
    var engine = new ScoringEngine();
    var state = startAtDeuce(engine, DEUCE_SILVER_POINT, "test-sp-5");
    Test.assertEqual("Deuce", state.gameStatusLine());
    state = engine.applyPointWon(state, LEFT, 30);
    Test.assertEqual("Advantage", state.gameStatusLine());
    return true;
}

(:test)
function testStarPointPlaysTwoAdvantagesThenDecides(logger as Logger) as Boolean {
    var engine = new ScoringEngine();
    var state = startAtDeuce(engine, DEUCE_STAR_POINT, "test-st-1");
    Test.assert(!state.currentGame.isGoldenPointActive);
    Test.assertEqual("Deuce 1", state.gameStatusLine());
    Test.assertEqual("40", state.gameDisplayPair()[0]);

    state = engine.applyPointWon(state, LEFT, 30); // Ad left
    Test.assertEqual(LEFT, state.currentGame.advantageSide);
    Test.assert(!state.currentGame.isGoldenPointActive);
    Test.assertEqual("Advantage 1", state.gameStatusLine());
    Test.assertEqual("Ad", state.gameDisplayPair()[0]);

    state = engine.applyPointWon(state, RIGHT, 31); // first advantage broken → not decisive yet
    Test.assert(state.currentGame.advantageSide == null);
    Test.assert(!state.currentGame.isGoldenPointActive);
    Test.assertEqual(1, state.currentGame.brokenAdvantageCount);
    Test.assertEqual("Deuce 2", state.gameStatusLine());
    Test.assertEqual("40", state.gameDisplayPair()[0]);

    state = engine.applyPointWon(state, RIGHT, 32); // Ad right
    Test.assertEqual(RIGHT, state.currentGame.advantageSide);
    Test.assertEqual("Advantage 2", state.gameStatusLine());

    state = engine.applyPointWon(state, LEFT, 33); // second advantage broken → star point
    Test.assert(state.currentGame.isGoldenPointActive);
    Test.assert(state.currentGame.advantageSide == null);
    Test.assertEqual(2, state.currentGame.brokenAdvantageCount);
    Test.assertEqual("Star Point", state.gameStatusLine());
    var pair = state.gameDisplayPair();
    Test.assertEqual("ST", pair[0]);
    Test.assertEqual("ST", pair[1]);

    state = engine.applyPointWon(state, RIGHT, 34);
    Test.assertEqual(1, state.currentSet.rightGames);
    Test.assertEqual(0, state.currentSet.leftGames);
    Test.assert(!state.currentGame.isGoldenPointActive);
    Test.assertEqual(0, state.currentGame.brokenAdvantageCount);
    return true;
}

(:test)
function testStarPointAdvantageHolderWinsOnEitherCycle(logger as Logger) as Boolean {
    var engine = new ScoringEngine();
    // First advantage converted: no second cycle, no star point.
    var state = startAtDeuce(engine, DEUCE_STAR_POINT, "test-st-2");
    state = engine.applyPointWon(state, LEFT, 30);
    state = engine.applyPointWon(state, LEFT, 31);
    Test.assertEqual(1, state.currentSet.leftGames);

    // Second advantage converted.
    var t = 32;
    for (var i = 0; i < 3; i += 1) {
        state = engine.applyPointWon(state, LEFT, t);
        t += 1;
        state = engine.applyPointWon(state, RIGHT, t);
        t += 1;
    }
    state = engine.applyPointWon(state, LEFT, t); // Ad left
    t += 1;
    state = engine.applyPointWon(state, RIGHT, t); // broken
    t += 1;
    state = engine.applyPointWon(state, RIGHT, t); // Ad right
    t += 1;
    state = engine.applyPointWon(state, RIGHT, t); // converts
    Test.assertEqual(1, state.currentSet.rightGames);
    Test.assert(!state.currentGame.isGoldenPointActive);
    return true;
}

(:test)
function testStarPointDecidingPointWinnableByEitherSide(logger as Logger) as Boolean {
    var engine = new ScoringEngine();
    var state = startAtDeuce(engine, DEUCE_STAR_POINT, "test-st-3");
    state = engine.applyPointWon(state, LEFT, 30);
    state = engine.applyPointWon(state, RIGHT, 31);
    state = engine.applyPointWon(state, RIGHT, 32);
    state = engine.applyPointWon(state, LEFT, 33); // second break → star point
    Test.assert(state.currentGame.isGoldenPointActive);
    // The side that just lost its advantage can still take the game.
    state = engine.applyPointWon(state, RIGHT, 34);
    Test.assertEqual(1, state.currentSet.rightGames);
    return true;
}

(:test)
function testStarPointIsNotSilverPoint(logger as Logger) as Boolean {
    // One broken advantage under star point must not arm the deciding point.
    var engine = new ScoringEngine();
    var state = startAtDeuce(engine, DEUCE_STAR_POINT, "test-st-4");
    state = engine.applyPointWon(state, LEFT, 30);
    state = engine.applyPointWon(state, RIGHT, 31);
    Test.assert(!state.currentGame.isGoldenPointActive);
    state = engine.applyPointWon(state, LEFT, 32);
    // Second advantage is a real advantage: converting it wins the game.
    state = engine.applyPointWon(state, LEFT, 33);
    Test.assertEqual(1, state.currentSet.leftGames);
    return true;
}

(:test)
function testUndoStarPointReturnsToSecondAdvantage(logger as Logger) as Boolean {
    var engine = new ScoringEngine();
    var state = startAtDeuce(engine, DEUCE_STAR_POINT, "test-st-5");
    state = engine.applyPointWon(state, LEFT, 30);
    state = engine.applyPointWon(state, RIGHT, 31);
    state = engine.applyPointWon(state, RIGHT, 32);
    state = engine.applyPointWon(state, LEFT, 33);
    Test.assert(state.currentGame.isGoldenPointActive);

    state = engine.applyUndo(state);
    Test.assert(!state.currentGame.isGoldenPointActive);
    Test.assertEqual(RIGHT, state.currentGame.advantageSide);
    Test.assertEqual(1, state.currentGame.brokenAdvantageCount);
    Test.assertEqual("Advantage 2", state.gameStatusLine());
    return true;
}

(:test)
function testChangingToStarPointAtDeuceLeavesTwoAdvantagesToPlay(logger as Logger) as Boolean {
    var engine = new ScoringEngine();
    var state = startAtDeuce(engine, DEUCE_GOLDEN_POINT, "test-st-change-1");
    Test.assert(state.currentGame.isGoldenPointActive);

    state = engine.applySetDeuceFormat(state, DEUCE_STAR_POINT, 30);
    Test.assert(!state.currentGame.isGoldenPointActive);
    Test.assertEqual("Deuce 1", state.gameStatusLine());

    state = engine.applyPointWon(state, LEFT, 31);
    state = engine.applyPointWon(state, RIGHT, 32);
    Test.assert(!state.currentGame.isGoldenPointActive);
    state = engine.applyPointWon(state, LEFT, 33);
    state = engine.applyPointWon(state, RIGHT, 34);
    Test.assert(state.currentGame.isGoldenPointActive);
    Test.assertEqual("Star Point", state.gameStatusLine());
    return true;
}

(:test)
function testChangingFromSilverPointDeciderToStarPointLeavesOneAdvantageToPlay(logger as Logger) as Boolean {
    var engine = new ScoringEngine();
    var state = startAtDeuce(engine, DEUCE_SILVER_POINT, "test-st-change-2");
    state = engine.applyPointWon(state, LEFT, 30);
    state = engine.applyPointWon(state, RIGHT, 31); // silver point armed after one break
    Test.assert(state.currentGame.isGoldenPointActive);

    // Star point allows two; one has been used, so one advantage remains.
    state = engine.applySetDeuceFormat(state, DEUCE_STAR_POINT, 32);
    Test.assert(!state.currentGame.isGoldenPointActive);
    Test.assertEqual("Deuce 2", state.gameStatusLine());

    state = engine.applyPointWon(state, LEFT, 33);
    Test.assertEqual("Advantage 2", state.gameStatusLine());
    state = engine.applyPointWon(state, RIGHT, 34);
    Test.assert(state.currentGame.isGoldenPointActive);
    Test.assertEqual("Star Point", state.gameStatusLine());
    return true;
}

(:test)
function testChangingToACappedFormatAfterItsAdvantagesWereUsedArmsTheDecider(logger as Logger) as Boolean {
    var engine = new ScoringEngine();
    // Regular scoring: two advantages broken, a third one held.
    var state = startAtDeuce(engine, DEUCE_ADVANTAGE, "test-st-change-3");
    state = engine.applyPointWon(state, LEFT, 30);
    state = engine.applyPointWon(state, RIGHT, 31);
    state = engine.applyPointWon(state, LEFT, 32);
    state = engine.applyPointWon(state, RIGHT, 33);
    state = engine.applyPointWon(state, LEFT, 34);
    Test.assertEqual(LEFT, state.currentGame.advantageSide);

    // Star point allows only two and both are spent, so — like switching to golden —
    // the advantage held is given up and the next rally decides.
    state = engine.applySetDeuceFormat(state, DEUCE_STAR_POINT, 35);
    Test.assert(state.currentGame.isGoldenPointActive);
    Test.assert(state.currentGame.advantageSide == null);
    Test.assertEqual("Star Point", state.gameStatusLine());

    state = engine.applyPointWon(state, RIGHT, 36);
    Test.assertEqual(1, state.currentSet.rightGames);
    return true;
}

(:test)
function testChangingToSilverPointAfterOneBrokenAdvantageArmsTheDecider(logger as Logger) as Boolean {
    var engine = new ScoringEngine();
    var state = startAtDeuce(engine, DEUCE_ADVANTAGE, "test-sp-change-1");
    state = engine.applyPointWon(state, LEFT, 30);
    state = engine.applyPointWon(state, RIGHT, 31); // silver's single advantage already played
    Test.assert(!state.currentGame.isGoldenPointActive);

    state = engine.applySetDeuceFormat(state, DEUCE_SILVER_POINT, 32);
    Test.assert(state.currentGame.isGoldenPointActive);
    Test.assertEqual("Silver Point", state.gameStatusLine());
    return true;
}

(:test)
function testChangingFromStarPointDeciderToRegularDisarmsIt(logger as Logger) as Boolean {
    var engine = new ScoringEngine();
    var state = startAtDeuce(engine, DEUCE_STAR_POINT, "test-st-change-4");
    state = engine.applyPointWon(state, LEFT, 30);
    state = engine.applyPointWon(state, RIGHT, 31);
    state = engine.applyPointWon(state, LEFT, 32);
    state = engine.applyPointWon(state, RIGHT, 33);
    Test.assert(state.currentGame.isGoldenPointActive);

    state = engine.applySetDeuceFormat(state, DEUCE_ADVANTAGE, 34);
    Test.assert(!state.currentGame.isGoldenPointActive);
    Test.assertEqual("Deuce", state.gameStatusLine());
    state = engine.applyPointWon(state, LEFT, 35);
    Test.assertEqual(LEFT, state.currentGame.advantageSide);
    Test.assertEqual(0, state.currentSet.leftGames);
    return true;
}

(:test)
function testUndoSilverPointReturnsToAdvantage(logger as Logger) as Boolean {
    var engine = new ScoringEngine();
    var state = startAtDeuce(engine, DEUCE_SILVER_POINT, "test-sp-3");
    state = engine.applyPointWon(state, LEFT, 30);
    state = engine.applyPointWon(state, RIGHT, 31);
    Test.assert(state.currentGame.isGoldenPointActive);
    state = engine.applyUndo(state);
    Test.assert(!state.currentGame.isGoldenPointActive);
    Test.assertEqual(LEFT, state.currentGame.advantageSide);
    return true;
}

(:test)
function testUndoGoldenPointReturnsToFortyThirty(logger as Logger) as Boolean {
    var engine = new ScoringEngine();
    var state = startAtDeuce(engine, DEUCE_GOLDEN_POINT, "test-gp-4");
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
    state = engine.applySelectServer(state, LEFT, 1);
    state = engine.applyPointWon(state, LEFT, 2);
    state = engine.applyPointWon(state, RIGHT, 3);
    state = engine.applyUndo(state);
    var pair = state.gameDisplayPair();
    Test.assertEqual("15", pair[0]);
    Test.assertEqual("0", pair[1]);
    return true;
}

(:test)
function testDeuceFormatStringRoundTrip(logger as Logger) as Boolean {
    var formats = [
        DEUCE_ADVANTAGE,
        DEUCE_SILVER_POINT,
        DEUCE_GOLDEN_POINT,
        DEUCE_STAR_POINT
    ] as Array<DeuceFormat>;
    for (var i = 0; i < formats.size(); i += 1) {
        var raw = deuceFormatToString(formats[i]);
        Test.assertEqual(formats[i], deuceFormatFromString(raw));
    }
    // Raw values are shared with the Swift enum.
    Test.assertEqual("starPoint", deuceFormatToString(DEUCE_STAR_POINT));
    // Unknown and absent values fall through so callers can apply migration.
    Test.assert(deuceFormatFromString(null) == null);
    Test.assert(deuceFormatFromString("nonsense") == null);
    return true;
}

(:test)
function testDeuceFormatsCycleFromMostToFewestAdvantages(logger as Logger) as Boolean {
    Test.assertEqual(DEUCE_STAR_POINT, deuceFormatAfter(DEUCE_ADVANTAGE));
    Test.assertEqual(DEUCE_SILVER_POINT, deuceFormatAfter(DEUCE_STAR_POINT));
    Test.assertEqual(DEUCE_GOLDEN_POINT, deuceFormatAfter(DEUCE_SILVER_POINT));
    Test.assertEqual(DEUCE_ADVANTAGE, deuceFormatAfter(DEUCE_GOLDEN_POINT));

    Test.assert(deuceFormatAdvantagesBeforeDecidingPoint(DEUCE_ADVANTAGE) == null);
    Test.assertEqual(2, deuceFormatAdvantagesBeforeDecidingPoint(DEUCE_STAR_POINT));
    Test.assertEqual(1, deuceFormatAdvantagesBeforeDecidingPoint(DEUCE_SILVER_POINT));
    Test.assertEqual(0, deuceFormatAdvantagesBeforeDecidingPoint(DEUCE_GOLDEN_POINT));
    return true;
}

(:test)
function testArchivedMatchesKeepSilverPointBehaviour(logger as Logger) as Boolean {
    // Matches written before this setting existed played one advantage before
    // the decisive point, so they must migrate to silver point, not golden.
    Test.assertEqual(DEUCE_SILVER_POINT, deuceFormatFromLegacyArchivedFlag(true));
    Test.assertEqual(DEUCE_ADVANTAGE, deuceFormatFromLegacyArchivedFlag(false));
    return true;
}

(:test)
function testPreferenceMigratesFromLegacyGoldenPointToggle(logger as Logger) as Boolean {
    // Deliberately different from the archived-match rule: only an explicit
    // "off" carries over, everything else lands on the product default.
    Test.assertEqual(DEUCE_ADVANTAGE, deuceFormatFromLegacyPreference(false));
    Test.assertEqual(DEUCE_STAR_POINT, deuceFormatFromLegacyPreference(true));
    Test.assertEqual(DEUCE_STAR_POINT, deuceFormatFromLegacyPreference(null));
    return true;
}

(:test)
function testDefaultSettingsUseStarPoint(logger as Logger) as Boolean {
    var settings = new MatchSettings();
    Test.assertEqual(DEUCE_STAR_POINT, settings.deuceFormat);
    Test.assertEqual(DEUCE_STAR_POINT, settings.copy().deuceFormat);
    return true;
}

(:test)
function testSixSixStartsTieBreak(logger as Logger) as Boolean {
    var engine = new ScoringEngine();
    var settings = new MatchSettings();
    var state = engine.startMatch(settings, "test-4", 0);
    state = engine.applySelectServer(state, LEFT, 1);
    for (var set = 0; set < 6; set += 1) {
        for (var g = 0; g < 4; g += 1) {
            state = engine.applyPointWon(state, LEFT, 100 + set * 10 + g);
        }
        for (var g = 0; g < 4; g += 1) {
            state = engine.applyPointWon(state, RIGHT, 200 + set * 10 + g);
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
    state = engine.applySelectServer(state, LEFT, 1);
    var t = 2;
    for (var i = 0; i < 3; i += 1) {
        for (var p = 0; p < 4; p += 1) {
            state = engine.applyPointWon(state, LEFT, t);
            t += 1;
        }
    }
    for (var i = 0; i < 2; i += 1) {
        for (var p = 0; p < 4; p += 1) {
            state = engine.applyPointWon(state, RIGHT, t);
            t += 1;
        }
    }
    state = engine.applyPointWon(state, LEFT, t);
    t += 1;
    state = engine.applyPointWon(state, LEFT, t);
    t += 1;
    state = engine.applyPointWon(state, LEFT, t);
    t += 1;
    state = engine.applyPointWon(state, RIGHT, t);
    t += 1;
    state = engine.applyFinish(state, t);
    Test.assertEqual(ENDED_EARLY, state.status);
    Test.assertEqual("3-2 (40-15)", state.finalScoreSummary());
    Test.assert(state.displaysIncompleteSet());
    return true;
}

(:test)
function testFinalScoreSummaryFinishMidSetAfterCompletedSet(logger as Logger) as Boolean {
    var engine = new ScoringEngine();
    var settings = new MatchSettings();
    var state = engine.startMatch(settings, "test-6", 0);
    state = engine.applySelectServer(state, LEFT, 1);
    var t = 2;
    for (var g = 0; g < 6; g += 1) {
        for (var p = 0; p < 4; p += 1) {
            state = engine.applyPointWon(state, LEFT, t);
            t += 1;
        }
    }
    for (var i = 0; i < 3; i += 1) {
        for (var p = 0; p < 4; p += 1) {
            state = engine.applyPointWon(state, LEFT, t);
            t += 1;
        }
    }
    for (var i = 0; i < 2; i += 1) {
        for (var p = 0; p < 4; p += 1) {
            state = engine.applyPointWon(state, RIGHT, t);
            t += 1;
        }
    }
    state = engine.applyPointWon(state, LEFT, t);
    t += 1;
    state = engine.applyPointWon(state, LEFT, t);
    t += 1;
    state = engine.applyPointWon(state, RIGHT, t);
    t += 1;
    state = engine.applyFinish(state, t);
    Test.assertEqual(ENDED_EARLY, state.status);
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
    state = engine.applySelectServer(state, LEFT, 1);
    Test.assertEqual(LEFT, state.scoreScreenSides()[0]);
    Test.assertEqual("Us", state.servingRoleLabels()[0]);
    Test.assertEqual("Them", state.servingRoleLabels()[1]);

    for (var p = 0; p < 4; p += 1) {
        state = engine.applyPointWon(state, LEFT, 10 + p);
    }
    Test.assertEqual(RIGHT, state.currentServer);
    Test.assertEqual(RIGHT, state.scoreScreenSides()[0]);
    Test.assertEqual("Them", state.servingRoleLabels()[0]);
    Test.assertEqual("Us", state.servingRoleLabels()[1]);
    Test.assertEqual(RIGHT, state.logicalSideForVisual(LEFT));
    return true;
}

(:test)
function testFixedServerPositionsRotatesServeButKeepsLayout(logger as Logger) as Boolean {
    var engine = new ScoringEngine();
    var settings = new MatchSettings();
    settings.fixedServerPositions = true;
    var state = engine.startMatch(settings, "test-8", 0);
    state = engine.applySelectServer(state, LEFT, 1);
    for (var p = 0; p < 4; p += 1) {
        state = engine.applyPointWon(state, LEFT, 10 + p);
    }
    Test.assertEqual(RIGHT, state.currentServer);
    Test.assertEqual(LEFT, state.scoreScreenSides()[0]);
    Test.assertEqual(RIGHT, state.scoreScreenSides()[1]);
    Test.assertEqual("Us", state.servingRoleLabels()[0]);
    Test.assertEqual("Them", state.servingRoleLabels()[1]);
    return true;
}

function winGames(engine as ScoringEngine, state as MatchState, side as Side, games as Number, t as Number) as MatchState {
    for (var g = 0; g < games; g += 1) {
        for (var p = 0; p < 4; p += 1) {
            var next = engine.applyPointWon(state, side, t);
            if (next == null) {
                return state;
            }
            state = next;
            t += 1;
        }
    }
    return state;
}

(:test)
function testServeRotatesIntoFirstGameOfNextSet(logger as Logger) as Boolean {
    var engine = new ScoringEngine();
    var settings = new MatchSettings();
    settings.fixedServerPositions = false;
    var state = engine.startMatch(settings, "test-set-serve", 0);
    state = engine.applySelectServer(state, LEFT, 1);
    state = winGames(engine, state, LEFT, 6, 2);
    Test.assertEqual(1, state.completedSets.size());
    Test.assertEqual(0, state.currentSet.leftGames);
    Test.assert(!state.needsServerSelection);
    Test.assertEqual(LEFT, state.currentServer);
    return true;
}

(:test)
function testTieBreakOpensOnRotatedServe(logger as Logger) as Boolean {
    var engine = new ScoringEngine();
    var settings = new MatchSettings();
    settings.fixedServerPositions = false;
    var state = engine.startMatch(settings, "test-tb-serve", 0);
    state = engine.applySelectServer(state, LEFT, 1);
    var t = 2;
    for (var i = 0; i < 6; i += 1) {
        for (var p = 0; p < 4; p += 1) {
            state = engine.applyPointWon(state, LEFT, t);
            t += 1;
        }
        for (var p = 0; p < 4; p += 1) {
            state = engine.applyPointWon(state, RIGHT, t);
            t += 1;
        }
    }
    Test.assert(state.currentGame.isTieBreak);
    Test.assertEqual(LEFT, state.currentServer);
    return true;
}

(:test)
function testNewServeNotOfferedBeforeFirstSet(logger as Logger) as Boolean {
    var engine = new ScoringEngine();
    var settings = new MatchSettings();
    var state = engine.startMatch(settings, "test-no-serve", 0);
    state = engine.applySelectServer(state, LEFT, 1);
    Test.assertEqual(0, state.completedSets.size());
    Test.assert(state.isAtSetStart());
    Test.assert(!state.canChooseNewServer());
    return true;
}

(:test)
function testNewServeAtChangeover(logger as Logger) as Boolean {
    var engine = new ScoringEngine();
    var settings = new MatchSettings();
    var state = engine.startMatch(settings, "test-new-serve", 0);
    state = engine.applySelectServer(state, LEFT, 1);
    state = winGames(engine, state, LEFT, 6, 2);
    Test.assert(state.canChooseNewServer());
    state = engine.applyRequestServerSelection(state);
    Test.assert(state.needsServerSelection);
    Test.assert(state.currentServer == null);
    return true;
}

(:test)
function testDeuceFormatChangeKeepsNewServePrompt(logger as Logger) as Boolean {
    var engine = new ScoringEngine();
    var settings = new MatchSettings();
    var state = engine.startMatch(settings, "test-deuce-serve", 0);
    state = engine.applySelectServer(state, LEFT, 1);
    state = winGames(engine, state, LEFT, 6, 2);
    state = engine.applyRequestServerSelection(state);
    state = engine.applySetDeuceFormat(state, DEUCE_ADVANTAGE, 100);
    Test.assert(state.needsServerSelection);
    Test.assert(state.currentServer == null);
    Test.assertEqual(DEUCE_ADVANTAGE, state.settings.deuceFormat);
    return true;
}

(:test)
function testFinishWithoutWinnerEndsEarly(logger as Logger) as Boolean {
    var engine = new ScoringEngine();
    var settings = new MatchSettings();
    var state = engine.startMatch(settings, "test-finish-early", 0);
    state = engine.applySelectServer(state, LEFT, 1);
    state = engine.applyPointWon(state, LEFT, 2);
    state = engine.applyFinish(state, 3);
    Test.assertEqual(ENDED_EARLY, state.status);
    Test.assert(state.winner == null);
    return true;
}

(:test)
function testMatchStartArmsWarmUpByDefault(logger as Logger) as Boolean {
    var engine = new ScoringEngine();
    var settings = new MatchSettings();
    var state = engine.startMatch(settings, "test-warmup-1", 0);
    Test.assert(state.needsWarmUp);
    Test.assert(state.needsServerSelection);
    Test.assert(state.isWaitingForFirstServe());
    return true;
}

(:test)
function testWarmUpCanBeDisabled(logger as Logger) as Boolean {
    var engine = new ScoringEngine();
    var settings = new MatchSettings();
    settings.warmUpEnabled = false;
    var state = engine.startMatch(settings, "test-warmup-off", 0);
    Test.assert(!state.needsWarmUp);
    Test.assert(state.needsServerSelection);
    return true;
}

(:test)
function testCompleteWarmUpClearsFlag(logger as Logger) as Boolean {
    var engine = new ScoringEngine();
    var settings = new MatchSettings();
    var state = engine.startMatch(settings, "test-warmup-skip", 0);
    state = engine.applyCompleteWarmUp(state);
    Test.assert(!state.needsWarmUp);
    Test.assert(state.needsServerSelection);
    Test.assert(state.currentServer == null);
    return true;
}

(:test)
function testWarmUpNotReArmedAtSetStart(logger as Logger) as Boolean {
    var engine = new ScoringEngine();
    var settings = new MatchSettings();
    var state = engine.startMatch(settings, "test-warmup-set", 0);
    state = engine.applyCompleteWarmUp(state);
    state = engine.applySelectServer(state, LEFT, 1);
    state = winGames(engine, state, LEFT, 6, 2);
    Test.assertEqual(1, state.completedSets.size());
    Test.assert(!state.needsWarmUp);
    state = engine.applyRequestServerSelection(state);
    Test.assert(state.needsServerSelection);
    Test.assert(!state.needsWarmUp);
    return true;
}

(:test)
function testRehydratePreservesWarmUp(logger as Logger) as Boolean {
    var engine = new ScoringEngine();
    var settings = new MatchSettings();
    var state = engine.startMatch(settings, "test-warmup-rehydrate", 0);
    var restored = engine.rehydrate(state);
    Test.assert(restored.needsWarmUp);
    Test.assert(restored.needsServerSelection);
    state = engine.applyCompleteWarmUp(state);
    restored = engine.rehydrate(state);
    Test.assert(!restored.needsWarmUp);
    Test.assert(restored.needsServerSelection);
    return true;
}
