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

(:test)
function testGoldenPointActivates(logger as Logger) as Boolean {
    var engine = new ScoringEngine();
    var settings = new MatchSettings();
    var state = engine.startMatch(settings, "test-2", 0);
    state = engine.applySelectServer(state, Side.LEFT, 1);
    for (var i = 0; i < 3; i += 1) {
        state = engine.applyPointWon(state, Side.LEFT, 10 + i);
        state = engine.applyPointWon(state, Side.RIGHT, 20 + i);
    }
    state = engine.applyPointWon(state, Side.LEFT, 30);
    state = engine.applyPointWon(state, Side.RIGHT, 31);
    Test.assert(state.currentGame.isGoldenPointActive);
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
    var pair = state.currentGame.displayPair();
    Test.assertEqual("15", pair[0]);
    Test.assertEqual("0", pair[1]);
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
