import Foundation
import XCTest

final class ScoringEngineTests: XCTestCase {
    private let engine = ScoringEngine()

    private func start(settings: MatchSettings = .default) -> MatchState {
        let initial = engine.startMatch(settings: settings)
        return (try? engine.apply(.selectServer(.left), to: initial)) ?? initial
    }

    private func startUnselected() -> MatchState {
        engine.startMatch()
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
        XCTAssertTrue(s.needsServerSelection)
        XCTAssertNil(s.currentServer)
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

    func testFinishWithoutWinnerEndsEarly() throws {
        var s = start()
        s = try point(.left, s)
        s = try engine.apply(.finish, to: s)
        XCTAssertEqual(s.status, .endedEarly)
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
}
