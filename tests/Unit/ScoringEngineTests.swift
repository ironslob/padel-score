import Foundation
import XCTest

final class ScoringEngineTests: XCTestCase {
    private let engine = ScoringEngine()

    /// Defaults with sides swapping after each game — most scoring tests assume server flips.
    private var rotatingSettings: MatchSettings {
        var settings = MatchSettings.default
        settings.fixedServerPositions = false
        return settings
    }

    private func start(settings: MatchSettings? = nil) -> MatchState {
        let initial = engine.startMatch(settings: settings ?? rotatingSettings)
        return (try? engine.apply(.selectServer(.left), to: initial)) ?? initial
    }

    private func startUnselected(settings: MatchSettings? = nil) -> MatchState {
        engine.startMatch(settings: settings ?? rotatingSettings)
    }

    private func point(_ side: Side, _ state: MatchState) throws -> MatchState {
        try engine.apply(.pointWon(side), to: state)
    }

    private func winGame(for side: Side, from state: MatchState) throws -> MatchState {
        var s = state
        if s.needsServerSelection {
            s = try engine.apply(.selectServer(.left), to: s)
        }
        // Win four straight points from love.
        for _ in 0..<4 {
            s = try point(side, s)
        }
        return s
    }

    private func reachSixSix(from state: MatchState) throws -> MatchState {
        var s = state
        for _ in 0..<6 {
            s = try winGame(for: .left, from: s)
            s = try winGame(for: .right, from: s)
        }
        return s
    }

    private func winTieBreak(for side: Side, points: Int, from state: MatchState) throws -> MatchState {
        var s = state
        for _ in 0..<points {
            s = try point(side, s)
        }
        return s
    }

    // MARK: - Point progression

    func testSetStartRequiresServerSelectionBeforeScoring() throws {
        let s = startUnselected()
        XCTAssertTrue(s.needsServerSelection)
        XCTAssertThrowsError(try point(.left, s)) { error in
            XCTAssertEqual(error as? ScoringError, .invalidAction)
        }
    }

    func testSelectingServerSetsCurrentServer() throws {
        let s = startUnselected()
        let selected = try engine.apply(.selectServer(.right), to: s)
        XCTAssertFalse(selected.needsServerSelection)
        XCTAssertEqual(selected.currentServer, .right)
    }

    func testLoveToFifteenToThirtyToFortyToGame() throws {
        var s = start()
        s = try point(.left, s)
        XCTAssertEqual(s.currentGame.displayPair.left, "15")
        s = try point(.left, s)
        XCTAssertEqual(s.currentGame.displayPair.left, "30")
        s = try point(.left, s)
        XCTAssertEqual(s.currentGame.displayPair.left, "40")
        s = try point(.left, s)
        XCTAssertEqual(s.currentSet.leftGames, 1)
        XCTAssertEqual(s.currentGame.displayPair.left, "0")
        XCTAssertEqual(s.currentGame.displayPair.right, "0")
    }

    func testOpponentBelowFortyThenFortyWinsGame() throws {
        var s = start()
        s = try point(.left, s)
        s = try point(.left, s)
        s = try point(.left, s) // 40-0
        s = try point(.right, s) // 40-15
        s = try point(.left, s)
        XCTAssertEqual(s.currentSet.leftGames, 1)
    }

    // MARK: - Deuce / Advantage / Golden Point

    func testDeuceAdvantageAndGameWithoutGoldenPath() throws {
        var s = start()
        // Reach deuce 40-40
        for _ in 0..<3 {
            s = try point(.left, s)
            s = try point(.right, s)
        }
        XCTAssertEqual(s.currentGame.statusLine, "Deuce")
        XCTAssertFalse(s.currentGame.isGoldenPointActive)

        s = try point(.left, s)
        XCTAssertEqual(s.currentGame.advantageSide, .left)
        XCTAssertFalse(s.currentGame.isGoldenPointActive)

        // Advantage holder wins game normally
        s = try point(.left, s)
        XCTAssertEqual(s.currentSet.leftGames, 1)
        XCTAssertFalse(s.currentGame.isGoldenPointActive)
    }

    func testGoldenPointActivatesAfterAdvantageBroken() throws {
        var s = start()
        for _ in 0..<3 {
            s = try point(.left, s)
            s = try point(.right, s)
        }
        s = try point(.left, s) // Ad left
        s = try point(.right, s) // back to deuce → golden
        XCTAssertTrue(s.currentGame.isGoldenPointActive)
        XCTAssertEqual(s.currentGame.statusLine, "Golden Point")
        XCTAssertEqual(s.currentGame.displayPair.left, "GP")
        XCTAssertEqual(s.currentGame.displayPair.right, "GP")

        s = try point(.right, s)
        XCTAssertEqual(s.currentSet.rightGames, 1)
        XCTAssertFalse(s.currentGame.isGoldenPointActive)
    }

    func testGoldenPointNextPointWinsForEitherSide() throws {
        var s = start()
        for _ in 0..<3 {
            s = try point(.left, s)
            s = try point(.right, s)
        }
        s = try point(.right, s)
        s = try point(.left, s) // golden
        XCTAssertTrue(s.currentGame.isGoldenPointActive)
        s = try point(.left, s)
        XCTAssertEqual(s.currentSet.leftGames, 1)
    }

    func testGoldenPointDisabledFallsBackToRepeatedAdvantage() throws {
        var settings = MatchSettings.default
        settings.goldenPointEnabled = false
        var s = start(settings: settings)
        for _ in 0..<3 {
            s = try point(.left, s)
            s = try point(.right, s)
        }
        s = try point(.left, s)
        s = try point(.right, s)
        XCTAssertFalse(s.currentGame.isGoldenPointActive)
        XCTAssertNil(s.currentGame.advantageSide)
        s = try point(.left, s)
        XCTAssertEqual(s.currentGame.advantageSide, .left)
    }

    // MARK: - Set / Match

    func testSetRequiresWinByTwo() throws {
        var s = start()
        // 5-5
        for _ in 0..<5 {
            s = try winGame(for: .left, from: s)
            s = try winGame(for: .right, from: s)
        }
        s = try winGame(for: .left, from: s) // 6-5
        XCTAssertEqual(s.currentSet.leftGames, 6)
        XCTAssertEqual(s.completedSets.count, 0)
        s = try winGame(for: .left, from: s) // 7-5 set
        XCTAssertEqual(s.completedSets.count, 1)
        XCTAssertEqual(s.leftSetsWon, 1)
        XCTAssertEqual(s.currentSet.leftGames, 0)
        XCTAssertFalse(s.needsServerSelection)
        XCTAssertEqual(s.currentServer, .right)
    }

    func testSetStartRequiresServerSelectionWhenEnabled() throws {
        var settings = MatchSettings.default
        settings.fixedServerPositions = false
        settings.askServeAtSetStart = true
        var s = start(settings: settings)
        for _ in 0..<5 {
            s = try winGame(for: .left, from: s)
            s = try winGame(for: .right, from: s)
        }
        s = try winGame(for: .left, from: s) // 6-5
        s = try winGame(for: .left, from: s) // 7-5 set
        XCTAssertTrue(s.needsServerSelection)
        XCTAssertNil(s.currentServer)
    }

    func testServerContinuesAcrossSetBoundaryByDefault() throws {
        var s = start()
        for _ in 0..<5 {
            s = try winGame(for: .left, from: s)
            s = try winGame(for: .right, from: s)
        }
        s = try winGame(for: .left, from: s) // 6-5
        s = try winGame(for: .left, from: s) // 7-5 set
        XCTAssertFalse(s.needsServerSelection)
        XCTAssertEqual(s.currentServer, .right)
        s = try point(.left, s)
        XCTAssertEqual(s.currentServer, .right)
    }

    func testServerAutoTogglesAfterEachCompletedGame() throws {
        var s = startUnselected()
        s = try engine.apply(.selectServer(.left), to: s)
        XCTAssertEqual(s.currentServer, .left)
        s = try winGame(for: .left, from: s)
        XCTAssertEqual(s.currentServer, .right)
        s = try winGame(for: .right, from: s)
        XCTAssertEqual(s.currentServer, .left)
    }

    func testMatchStartAlwaysRequiresServerSelection() {
        let s = startUnselected()
        XCTAssertTrue(s.needsServerSelection)
        XCTAssertNil(s.currentServer)
    }

    func testFixedServerPositionsStillRequiresServerSelectionAtMatchStart() {
        var settings = MatchSettings.default
        settings.fixedServerPositions = true
        let s = engine.startMatch(settings: settings)
        XCTAssertTrue(s.needsServerSelection)
        XCTAssertNil(s.currentServer)
    }

    func testUsThemLabelsFollowServeOrientation() throws {
        var s = start()
        XCTAssertEqual(s.servingRoleLabels.left, "Us")
        XCTAssertEqual(s.servingRoleLabels.right, "Them")
        XCTAssertEqual(s.scoreScreenSides.left, .left)
        XCTAssertEqual(s.scoreScreenSides.right, .right)

        s = try winGame(for: .right, from: s)
        XCTAssertEqual(s.currentServer, .right)
        XCTAssertEqual(s.servingRoleLabels.left, "Them")
        XCTAssertEqual(s.servingRoleLabels.right, "Us")
        XCTAssertEqual(s.scoreScreenSides.left, .right)
        XCTAssertEqual(s.scoreScreenSides.right, .left)
    }

    func testServingRoleLabelsStayServingLeftWhenUsThemLabelsDisabled() throws {
        var settings = MatchSettings.default
        settings.fixedServerPositions = false
        settings.usThemLabels = false
        var s = start(settings: settings)
        XCTAssertEqual(s.servingRoleLabels.left, "Serving")
        XCTAssertEqual(s.servingRoleLabels.right, "Receiving")

        s = try winGame(for: .right, from: s)
        XCTAssertEqual(s.currentServer, .right)
        XCTAssertEqual(s.servingRoleLabels.left, "Serving")
        XCTAssertEqual(s.servingRoleLabels.right, "Receiving")
    }

    func testScoreScreenDisplayRemapsWhenRightServes() throws {
        var s = start()
        s = try point(.left, s)
        s = try point(.left, s)
        s = try point(.right, s)
        XCTAssertEqual(s.scoreScreenGameDisplay.left, "30")
        XCTAssertEqual(s.scoreScreenGameDisplay.right, "15")

        s = try point(.left, s)
        s = try point(.left, s) // Us wins game; serve rotates to Them
        XCTAssertEqual(s.currentServer, .right)

        s = try point(.left, s)
        s = try point(.right, s)
        s = try point(.right, s)
        // Logical: Us 15, Them 30 — visual left is Them (serving)
        XCTAssertEqual(s.scoreScreenGameDisplay.left, "30")
        XCTAssertEqual(s.scoreScreenGameDisplay.right, "15")
        XCTAssertEqual(s.logicalSide(forVisual: .left), .right)
        XCTAssertEqual(s.logicalSide(forVisual: .right), .left)
        XCTAssertEqual(s.visualSide(forLogical: .right), .left)
    }

    func testFixedServerPositionsRotatesServeButKeepsButtonLayout() throws {
        var settings = MatchSettings.default
        settings.fixedServerPositions = true
        settings.usThemLabels = true
        var s = engine.startMatch(settings: settings)
        s = try engine.apply(.selectServer(.left), to: s)
        XCTAssertEqual(s.currentServer, .left)
        XCTAssertEqual(s.scoreScreenSides.left, .left)
        XCTAssertEqual(s.servingRoleLabels.left, "Us")
        XCTAssertEqual(s.servingRoleLabels.right, "Them")

        s = try winGame(for: .left, from: s)
        XCTAssertEqual(s.currentServer, .right)
        XCTAssertEqual(s.scoreScreenSides.left, .left)
        XCTAssertEqual(s.scoreScreenSides.right, .right)
        XCTAssertEqual(s.servingRoleLabels.left, "Us")
        XCTAssertEqual(s.servingRoleLabels.right, "Them")

        s = try winGame(for: .right, from: s)
        XCTAssertEqual(s.currentServer, .left)
        XCTAssertEqual(s.scoreScreenSides.left, .left)
    }

    func testFixedServerPositionsKeepsLayoutWhenRightServes() throws {
        var settings = MatchSettings.default
        settings.fixedServerPositions = true
        settings.usThemLabels = false
        var s = engine.startMatch(settings: settings)
        s = try engine.apply(.selectServer(.right), to: s)
        XCTAssertEqual(s.currentServer, .right)
        XCTAssertEqual(s.scoreScreenSides.left, .left)
        XCTAssertEqual(s.scoreScreenSides.right, .right)
        XCTAssertEqual(s.servingRoleLabels.left, "Receiving")
        XCTAssertEqual(s.servingRoleLabels.right, "Serving")

        s = try winGame(for: .left, from: s)
        XCTAssertEqual(s.currentServer, .left)
        XCTAssertEqual(s.scoreScreenSides.left, .left)
        XCTAssertEqual(s.servingRoleLabels.left, "Serving")
        XCTAssertEqual(s.servingRoleLabels.right, "Receiving")
    }

    func testFixedServerPositionsStillRotatesServeInTieBreak() throws {
        var settings = MatchSettings.default
        settings.fixedServerPositions = true
        var s = engine.startMatch(settings: settings)
        s = try engine.apply(.selectServer(.left), to: s)
        s = try reachSixSix(from: s)
        XCTAssertEqual(s.currentServer, .right)
        s = try point(.left, s)
        XCTAssertEqual(s.currentServer, .left)
        s = try point(.right, s)
        XCTAssertEqual(s.currentServer, .left)
        s = try point(.left, s)
        XCTAssertEqual(s.currentServer, .right)
    }

    func testAskServeAtSetStartWorksWithFixedServerPositions() throws {
        var settings = MatchSettings.default
        settings.fixedServerPositions = true
        settings.askServeAtSetStart = true
        var s = engine.startMatch(settings: settings)
        s = try engine.apply(.selectServer(.left), to: s)
        for _ in 0..<5 {
            s = try winGame(for: .left, from: s)
            s = try winGame(for: .right, from: s)
        }
        s = try winGame(for: .left, from: s) // 6-5
        s = try winGame(for: .left, from: s) // 7-5 set
        XCTAssertTrue(s.needsServerSelection)
        XCTAssertNil(s.currentServer)
    }

    func testMatchBestOfThree() throws {
        var s = start()
        for _ in 0..<2 {
            for _ in 0..<6 {
                s = try winGame(for: .left, from: s)
            }
        }
        XCTAssertEqual(s.status, .completed)
        XCTAssertEqual(s.winner, .left)
        XCTAssertEqual(s.leftSetsWon, 2)
        XCTAssertEqual(s.completedSets.count, 2)
    }

    func testMatchBestOfOne() throws {
        var settings = MatchSettings.default
        settings.setsToWin = 1
        var s = start(settings: settings)
        for _ in 0..<6 {
            s = try winGame(for: .left, from: s)
        }
        XCTAssertEqual(s.status, .completed)
        XCTAssertEqual(s.winner, .left)
        XCTAssertEqual(s.leftSetsWon, 1)
        XCTAssertEqual(s.completedSets.count, 1)
    }

    func testContinuousPlayDoesNotAutoComplete() throws {
        var settings = MatchSettings.default
        settings.continuousPlay = true
        var s = start(settings: settings)
        for _ in 0..<3 {
            for _ in 0..<6 {
                s = try winGame(for: .left, from: s)
            }
        }
        XCTAssertEqual(s.status, .inProgress)
        XCTAssertNil(s.winner)
        XCTAssertEqual(s.leftSetsWon, 3)
        XCTAssertEqual(s.completedSets.count, 3)
    }

    func testContinuousPlayFinishUsesSetLeader() throws {
        var settings = MatchSettings.default
        settings.continuousPlay = true
        var s = start(settings: settings)
        for _ in 0..<6 {
            s = try winGame(for: .left, from: s)
        }
        for _ in 0..<12 {
            s = try winGame(for: .right, from: s)
        }
        s = try engine.apply(.finish, to: s)
        XCTAssertEqual(s.status, .completed)
        XCTAssertEqual(s.winner, .right)
        XCTAssertEqual(s.leftSetsWon, 1)
        XCTAssertEqual(s.rightSetsWon, 2)
    }

    // MARK: - Tie-break

    func testSixSixStartsTieBreak() throws {
        let s = try reachSixSix(from: start())
        XCTAssertTrue(s.currentGame.isTieBreak)
        XCTAssertEqual(s.currentSet.leftGames, 6)
        XCTAssertEqual(s.currentSet.rightGames, 6)
        XCTAssertEqual(s.completedSets.count, 0)
        XCTAssertEqual(s.currentGame.displayPair.left, "0")
        XCTAssertEqual(s.currentGame.displayPair.right, "0")
    }

    func testTieBreakFirstToSevenWinsSet() throws {
        var s = try reachSixSix(from: start())
        s = try winTieBreak(for: .left, points: 7, from: s)
        XCTAssertEqual(s.completedSets.count, 1)
        XCTAssertEqual(s.completedSets[0].leftGames, 7)
        XCTAssertEqual(s.completedSets[0].rightGames, 6)
        XCTAssertEqual(s.leftSetsWon, 1)
    }

    func testTieBreakRequiresTwoPointLead() throws {
        var s = try reachSixSix(from: start())
        // 6-6 in tie-break — set not won
        s = try winTieBreak(for: .left, points: 6, from: s)
        s = try winTieBreak(for: .right, points: 6, from: s)
        XCTAssertEqual(s.completedSets.count, 0)
        XCTAssertTrue(s.currentGame.isTieBreak)
        XCTAssertEqual(s.currentGame.leftPoints, 6)
        XCTAssertEqual(s.currentGame.rightPoints, 6)

        // 8-6 in tie-break wins set 7-6
        s = try winTieBreak(for: .left, points: 2, from: s)
        XCTAssertEqual(s.completedSets.count, 1)
        XCTAssertEqual(s.completedSets[0].leftGames, 7)
        XCTAssertEqual(s.completedSets[0].rightGames, 6)
    }

    func testTieBreakServeRotation() throws {
        var s = try reachSixSix(from: start())
        XCTAssertEqual(s.currentServer, .right)

        s = try point(.left, s) // point 1
        XCTAssertEqual(s.currentServer, .left)

        s = try point(.right, s) // point 2
        XCTAssertEqual(s.currentServer, .left)

        s = try point(.left, s) // point 3
        XCTAssertEqual(s.currentServer, .right)
    }

    func testTieBreakNoticeChangeSides() throws {
        var s = try reachSixSix(from: start())
        XCTAssertNil(s.currentGame.tieBreakNotice)

        s = try winTieBreak(for: .left, points: 6, from: s)
        XCTAssertEqual(s.currentGame.tieBreakNotice, .changeSides)

        s = try winTieBreak(for: .right, points: 6, from: s)
        XCTAssertEqual(s.currentGame.tieBreakNotice, .changeSides)
    }

    func testTieBreakNoticeChangeServe() throws {
        var s = try reachSixSix(from: start())
        s = try point(.left, s)
        XCTAssertEqual(s.currentGame.tieBreakNotice, .changeServe)
    }

    func testTieBreakUndoAndReplay() throws {
        var s = try reachSixSix(from: start())
        s = try point(.left, s)
        s = try point(.right, s)
        s = try engine.apply(.undo, to: s)
        XCTAssertEqual(s.currentGame.leftPoints, 1)
        XCTAssertEqual(s.currentGame.rightPoints, 0)
        XCTAssertTrue(s.currentGame.isTieBreak)

        let replayed = engine.replay(events: s.events, onto: MatchState(id: s.id, settings: s.settings, startedAt: s.startedAt))
        XCTAssertEqual(replayed.currentGame.leftPoints, s.currentGame.leftPoints)
        XCTAssertEqual(replayed.currentGame.isTieBreak, s.currentGame.isTieBreak)
    }

    // MARK: - Undo

    func testUndoRemovesLastPointAndRecalculates() throws {
        var s = start()
        s = try point(.left, s)
        s = try point(.right, s)
        s = try engine.apply(.undo, to: s)
        XCTAssertEqual(s.currentGame.displayPair.left, "15")
        XCTAssertEqual(s.currentGame.displayPair.right, "0")
        XCTAssertEqual(s.events.filter { $0.kind == .pointWon }.count, 1)
    }

    func testUndoAfterGameWonRestoresPreviousGame() throws {
        var s = start()
        s = try winGame(for: .left, from: s)
        XCTAssertEqual(s.currentSet.leftGames, 1)
        s = try engine.apply(.undo, to: s)
        XCTAssertEqual(s.currentSet.leftGames, 0)
        XCTAssertEqual(s.currentGame.displayPair.left, "40")
    }

    func testUndoGoldenPoint() throws {
        var s = start()
        for _ in 0..<3 {
            s = try point(.left, s)
            s = try point(.right, s)
        }
        s = try point(.left, s)
        s = try point(.right, s)
        XCTAssertTrue(s.currentGame.isGoldenPointActive)
        s = try engine.apply(.undo, to: s)
        XCTAssertFalse(s.currentGame.isGoldenPointActive)
        XCTAssertEqual(s.currentGame.advantageSide, .left)
    }

    func testUndoWithNoPointsThrows() {
        let s = start()
        XCTAssertThrowsError(try engine.apply(.undo, to: s)) { error in
            XCTAssertEqual(error as? ScoringError, .nothingToUndo)
        }
    }

    // MARK: - End / Discard / Finish

    func testEndEarlyPreservesScore() throws {
        var s = start()
        s = try winGame(for: .left, from: s)
        s = try point(.right, s)
        s = try engine.apply(.endEarly, to: s)
        XCTAssertEqual(s.status, .endedEarly)
        XCTAssertEqual(s.currentSet.leftGames, 1)
        XCTAssertNotNil(s.finishedAt)
    }

    func testDiscardMarksDiscarded() throws {
        var s = start()
        s = try point(.left, s)
        s = try engine.apply(.discard, to: s)
        XCTAssertEqual(s.status, .discarded)
    }

    func testFinishWithoutWinnerCompletes() throws {
        var s = start()
        s = try point(.left, s)
        s = try engine.apply(.finish, to: s)
        XCTAssertEqual(s.status, .completed)
        XCTAssertNil(s.winner)
    }

    func testReplayIsDeterministic() throws {
        var s = start()
        s = try point(.left, s)
        s = try point(.right, s)
        s = try point(.left, s)
        let replayed = engine.replay(events: s.events, onto: MatchState(id: s.id, settings: s.settings, startedAt: s.startedAt))
        XCTAssertEqual(replayed.currentGame.leftPoints, s.currentGame.leftPoints)
        XCTAssertEqual(replayed.currentGame.rightPoints, s.currentGame.rightPoints)
        XCTAssertEqual(replayed.events.count, s.events.count)
    }

    // MARK: - Final score summary

    func testFinalScoreSummaryForCompletedMatch() throws {
        var s = start()
        for _ in 0..<2 {
            for _ in 0..<6 {
                s = try winGame(for: .left, from: s)
            }
        }
        XCTAssertEqual(s.finalScoreSummary, "6-0, 6-0")
    }

    func testFinalScoreSummaryEndedEarlyMidGame() throws {
        var s = start()
        for _ in 0..<3 {
            s = try winGame(for: .left, from: s)
        }
        for _ in 0..<2 {
            s = try winGame(for: .right, from: s)
        }
        s = try point(.left, s)
        s = try point(.left, s)
        s = try point(.left, s)
        s = try point(.right, s)
        s = try engine.apply(.endEarly, to: s)

        XCTAssertEqual(s.finalScoreSummary, "3-2 (40-15)")
    }

    func testFinalScoreSummaryEndedEarlyAfterCompletedSet() throws {
        var s = start()
        for _ in 0..<6 {
            s = try winGame(for: .left, from: s)
        }
        for _ in 0..<3 {
            s = try winGame(for: .left, from: s)
        }
        for _ in 0..<2 {
            s = try winGame(for: .right, from: s)
        }
        s = try point(.left, s)
        s = try point(.left, s)
        s = try point(.right, s)
        s = try engine.apply(.endEarly, to: s)

        XCTAssertEqual(s.finalScoreSummary, "6-0, 3-2 (30-15)")
    }

    func testFinalScoreSummaryEndedEarlyBetweenGames() throws {
        var s = start()
        s = try winGame(for: .left, from: s)
        s = try engine.apply(.endEarly, to: s)

        XCTAssertEqual(s.finalScoreSummary, "1-0")
    }

    func testFinalScoreSummaryEndedEarlyInTieBreak() throws {
        var s = try reachSixSix(from: start())
        s = try winTieBreak(for: .left, points: 4, from: s)
        s = try winTieBreak(for: .right, points: 3, from: s)
        s = try engine.apply(.endEarly, to: s)

        XCTAssertEqual(s.finalScoreSummary, "6-6 (4-3)")
    }

    func testFinalScoreSummaryEndedEarlyWithNoScore() throws {
        var s = start()
        s = try engine.apply(.endEarly, to: s)

        XCTAssertEqual(s.finalScoreSummary, "")
    }

    func testFinalScoreSummaryFinishMidSetIncludesPartial() throws {
        var s = start()
        for _ in 0..<3 {
            s = try winGame(for: .left, from: s)
        }
        for _ in 0..<2 {
            s = try winGame(for: .right, from: s)
        }
        s = try point(.left, s)
        s = try point(.left, s)
        s = try point(.left, s)
        s = try point(.right, s)
        s = try engine.apply(.finish, to: s)

        XCTAssertEqual(s.status, .completed)
        XCTAssertEqual(s.finalScoreSummary, "3-2 (40-15)")
        XCTAssertTrue(s.displaysIncompleteSet)
        XCTAssertEqual(s.setScoreLines, ["3-2"])
    }

    func testFinalScoreSummaryFinishMidSetAfterCompletedSet() throws {
        var s = start()
        for _ in 0..<6 {
            s = try winGame(for: .left, from: s)
        }
        for _ in 0..<3 {
            s = try winGame(for: .left, from: s)
        }
        for _ in 0..<2 {
            s = try winGame(for: .right, from: s)
        }
        s = try point(.left, s)
        s = try point(.left, s)
        s = try point(.right, s)
        s = try engine.apply(.finish, to: s)

        XCTAssertEqual(s.status, .completed)
        XCTAssertEqual(s.finalScoreSummary, "6-0, 3-2 (30-15)")
        XCTAssertTrue(s.displaysIncompleteSet)
        XCTAssertEqual(s.setScoreLines, ["6-0", "3-2"])
    }

    func testFinalScoreSummaryFinishWithNoScoreOmitsPartial() throws {
        var s = start()
        s = try engine.apply(.finish, to: s)

        XCTAssertEqual(s.status, .completed)
        XCTAssertEqual(s.finalScoreSummary, "")
        XCTAssertFalse(s.displaysIncompleteSet)
    }
}
