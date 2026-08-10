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
        XCTAssertEqual(s.gameDisplayPair.left, "15")
        s = try point(.left, s)
        XCTAssertEqual(s.gameDisplayPair.left, "30")
        s = try point(.left, s)
        XCTAssertEqual(s.gameDisplayPair.left, "40")
        s = try point(.left, s)
        XCTAssertEqual(s.currentSet.leftGames, 1)
        XCTAssertEqual(s.gameDisplayPair.left, "0")
        XCTAssertEqual(s.gameDisplayPair.right, "0")
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

    // MARK: - Deuce / Advantage / Silver Point / Golden Point

    /// Rotating-serve settings pinned to a specific deuce format.
    private func settings(_ format: DeuceFormat) -> MatchSettings {
        var settings = rotatingSettings
        settings.deuceFormat = format
        return settings
    }

    /// Plays to 40-40 without ever putting a side above 40.
    private func reachDeuce(_ state: MatchState) throws -> MatchState {
        var s = state
        for _ in 0..<3 {
            s = try point(.left, s)
            s = try point(.right, s)
        }
        return s
    }

    // MARK: Regular (advantage)

    func testAdvantageWinsGameWhenHeld() throws {
        var s = try reachDeuce(start(settings: settings(.advantage)))
        XCTAssertEqual(s.gameStatusLine, "Deuce")
        XCTAssertFalse(s.currentGame.isGoldenPointActive)

        s = try point(.left, s)
        XCTAssertEqual(s.currentGame.advantageSide, .left)
        XCTAssertEqual(s.gameStatusLine, "Advantage")

        s = try point(.left, s)
        XCTAssertEqual(s.currentSet.leftGames, 1)
    }

    func testAdvantageCyclesIndefinitely() throws {
        var s = try reachDeuce(start(settings: settings(.advantage)))
        // Three full advantage-then-broken cycles must never become decisive.
        for _ in 0..<3 {
            s = try point(.left, s)
            XCTAssertEqual(s.currentGame.advantageSide, .left)
            s = try point(.right, s)
            XCTAssertNil(s.currentGame.advantageSide)
            XCTAssertFalse(s.currentGame.isGoldenPointActive)
            XCTAssertEqual(s.gameStatusLine, "Deuce")
        }
        XCTAssertEqual(s.currentSet.leftGames, 0)
        XCTAssertEqual(s.currentSet.rightGames, 0)
    }

    // MARK: Golden point

    func testGoldenPointIsDecisiveImmediatelyAtDeuce() throws {
        var s = try reachDeuce(start(settings: settings(.goldenPoint)))
        // No advantage phase at all: 40-40 is already the deciding rally.
        XCTAssertTrue(s.currentGame.isGoldenPointActive)
        XCTAssertNil(s.currentGame.advantageSide)
        XCTAssertEqual(s.gameStatusLine, "Golden Point")
        XCTAssertEqual(s.gameDisplayPair.left, "GP")
        XCTAssertEqual(s.gameDisplayPair.right, "GP")

        s = try point(.right, s)
        XCTAssertEqual(s.currentSet.rightGames, 1)
        XCTAssertEqual(s.currentSet.leftGames, 0)
        XCTAssertFalse(s.currentGame.isGoldenPointActive)
    }

    func testGoldenPointNeverAwardsAdvantage() throws {
        var s = try reachDeuce(start(settings: settings(.goldenPoint)))
        s = try point(.left, s)
        // The game is over — the point did not become an advantage.
        XCTAssertEqual(s.currentSet.leftGames, 1)
        XCTAssertNil(s.currentGame.advantageSide)
    }

    func testGoldenPointReachedFromUnevenScoreline() throws {
        // 40-30 → 40-40 must arm the deciding point just the same.
        var s = start(settings: settings(.goldenPoint))
        s = try point(.left, s)
        s = try point(.left, s)
        s = try point(.left, s) // 40-0
        s = try point(.right, s)
        s = try point(.right, s) // 40-30
        XCTAssertFalse(s.currentGame.isGoldenPointActive)
        s = try point(.right, s) // 40-40
        XCTAssertTrue(s.currentGame.isGoldenPointActive)
    }

    // MARK: Silver point

    func testSilverPointPlaysOneAdvantageThenDecides() throws {
        var s = try reachDeuce(start(settings: settings(.silverPoint)))
        XCTAssertFalse(s.currentGame.isGoldenPointActive)
        XCTAssertEqual(s.gameStatusLine, "Deuce")

        s = try point(.left, s) // Ad left
        XCTAssertEqual(s.currentGame.advantageSide, .left)
        XCTAssertFalse(s.currentGame.isGoldenPointActive)

        s = try point(.right, s) // advantage broken → deciding point
        XCTAssertTrue(s.currentGame.isGoldenPointActive)
        XCTAssertNil(s.currentGame.advantageSide)
        XCTAssertEqual(s.gameStatusLine, "Silver Point")
        XCTAssertEqual(s.gameDisplayPair.left, "SP")
        XCTAssertEqual(s.gameDisplayPair.right, "SP")

        s = try point(.right, s)
        XCTAssertEqual(s.currentSet.rightGames, 1)
        XCTAssertFalse(s.currentGame.isGoldenPointActive)
    }

    func testSilverPointAdvantageHolderStillWinsOnSecondPoint() throws {
        var s = try reachDeuce(start(settings: settings(.silverPoint)))
        s = try point(.left, s) // Ad left
        s = try point(.left, s) // converts, no deciding point needed
        XCTAssertEqual(s.currentSet.leftGames, 1)
    }

    func testSilverPointDecidingPointWinnableByEitherSide() throws {
        var s = try reachDeuce(start(settings: settings(.silverPoint)))
        s = try point(.right, s) // Ad right
        s = try point(.left, s) // broken → deciding point
        XCTAssertTrue(s.currentGame.isGoldenPointActive)
        s = try point(.left, s)
        XCTAssertEqual(s.currentSet.leftGames, 1)
    }

    // MARK: Changing the deuce format mid-match

    private func changeFormat(_ format: DeuceFormat, _ state: MatchState) throws -> MatchState {
        try engine.apply(.setDeuceFormat(format), to: state)
    }

    func testChangingToGoldenPointArmsTheGameInProgress() throws {
        var s = try reachDeuce(start(settings: settings(.advantage)))
        XCTAssertEqual(s.gameStatusLine, "Deuce")

        s = try changeFormat(.goldenPoint, s)
        XCTAssertEqual(s.settings.deuceFormat, .goldenPoint)
        XCTAssertTrue(s.currentGame.isGoldenPointActive)
        XCTAssertEqual(s.gameStatusLine, "Golden Point")

        s = try point(.left, s)
        XCTAssertEqual(s.currentSet.leftGames, 1)
    }

    func testChangingToGoldenPointSurrendersAnAdvantageAlreadyHeld() throws {
        var s = try reachDeuce(start(settings: settings(.advantage)))
        s = try point(.left, s)
        XCTAssertEqual(s.currentGame.advantageSide, .left)

        s = try changeFormat(.goldenPoint, s)
        XCTAssertNil(s.currentGame.advantageSide)
        XCTAssertTrue(s.currentGame.isGoldenPointActive)

        // The next rally decides it, and it can go to the side that lost the advantage.
        s = try point(.right, s)
        XCTAssertEqual(s.currentSet.rightGames, 1)
    }

    func testChangingAwayFromGoldenPointDisarmsTheDecidingPoint() throws {
        var s = try reachDeuce(start(settings: settings(.goldenPoint)))
        XCTAssertTrue(s.currentGame.isGoldenPointActive)

        s = try changeFormat(.advantage, s)
        XCTAssertFalse(s.currentGame.isGoldenPointActive)
        XCTAssertEqual(s.gameStatusLine, "Deuce")

        // Back to a normal advantage phase rather than a game.
        s = try point(.left, s)
        XCTAssertEqual(s.currentGame.advantageSide, .left)
        XCTAssertEqual(s.currentSet.leftGames, 0)
    }

    func testChangingToSilverPointLeavesItsOneAdvantageStillToPlay() throws {
        var s = try reachDeuce(start(settings: settings(.goldenPoint)))
        s = try changeFormat(.silverPoint, s)
        XCTAssertFalse(s.currentGame.isGoldenPointActive)

        s = try point(.left, s)
        XCTAssertEqual(s.currentGame.advantageSide, .left)
        s = try point(.right, s)
        XCTAssertTrue(s.currentGame.isGoldenPointActive)
        XCTAssertEqual(s.gameStatusLine, "Silver Point")
    }

    func testGamesAlreadyPlayedKeepTheirResultAfterAFormatChange() throws {
        // Two games decided on a golden point, then the format is corrected.
        var s = start(settings: settings(.goldenPoint))
        for _ in 0..<2 {
            s = try reachDeuce(s)
            s = try point(.left, s)
        }
        XCTAssertEqual(s.currentSet.leftGames, 2)

        s = try changeFormat(.advantage, s)
        XCTAssertEqual(s.currentSet.leftGames, 2)
        XCTAssertEqual(s.completedSets.count, 0)
    }

    func testUndoAfterAFormatChangeDoesNotRescoreEarlierGames() throws {
        var s = start(settings: settings(.goldenPoint))
        s = try reachDeuce(s)
        s = try point(.left, s) // golden point decides game 1
        s = try changeFormat(.advantage, s)
        s = try point(.right, s) // first point of game 2

        s = try engine.apply(.undo, to: s)
        // The undone point belongs to game 2; game 1 stays won on the golden point.
        XCTAssertEqual(s.currentSet.leftGames, 1)
        XCTAssertEqual(s.currentGame.leftPoints, 0)
        XCTAssertEqual(s.currentGame.rightPoints, 0)
    }

    func testUndoRestoresTheDecidingPointArmedByAFormatChange() throws {
        var s = try reachDeuce(start(settings: settings(.advantage)))
        s = try changeFormat(.goldenPoint, s)
        s = try point(.left, s)
        XCTAssertEqual(s.currentSet.leftGames, 1)

        s = try engine.apply(.undo, to: s)
        XCTAssertEqual(s.currentSet.leftGames, 0)
        XCTAssertTrue(s.currentGame.isGoldenPointActive)
    }

    func testFormatCanBeChangedRepeatedly() throws {
        var s = try reachDeuce(start(settings: settings(.advantage)))
        s = try changeFormat(.goldenPoint, s)
        s = try changeFormat(.silverPoint, s)
        s = try changeFormat(.advantage, s)
        XCTAssertEqual(s.settings.deuceFormat, .advantage)
        XCTAssertFalse(s.currentGame.isGoldenPointActive)
        XCTAssertEqual(s.deuceFormatChanges.count, 4)
    }

    func testChangingToTheSameFormatIsANoOp() throws {
        let s = try reachDeuce(start(settings: settings(.goldenPoint)))
        let unchanged = try changeFormat(.goldenPoint, s)
        XCTAssertEqual(unchanged, s)
        XCTAssertTrue(unchanged.deuceFormatChanges.isEmpty)
    }

    func testFormatChangeMidTieBreakLeavesItAlone() throws {
        var s = try reachSixSix(from: start(settings: settings(.advantage)))
        s = try point(.left, s)
        s = try point(.right, s)
        XCTAssertTrue(s.currentGame.isTieBreak)

        s = try changeFormat(.goldenPoint, s)
        XCTAssertTrue(s.currentGame.isTieBreak)
        XCTAssertFalse(s.currentGame.isGoldenPointActive)
        XCTAssertEqual(s.currentGame.leftPoints, 1)
        XCTAssertEqual(s.currentGame.rightPoints, 1)
    }

    func testFormatCannotBeChangedOnATerminalMatch() throws {
        let s = try engine.apply(.endEarly, to: start(settings: settings(.advantage)))
        XCTAssertThrowsError(try changeFormat(.goldenPoint, s)) { error in
            XCTAssertEqual(error as? ScoringError, .matchNotInProgress)
        }
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
        XCTAssertEqual(s.currentServer, .left)
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
        s = try winGame(for: .left, from: s) // 6-5, game 11 served by Us
        s = try winGame(for: .left, from: s) // 7-5 set, game 12 served by Them
        XCTAssertFalse(s.needsServerSelection)
        // Serve rotates after the set-winning game like any other game.
        XCTAssertEqual(s.currentServer, .left)
        s = try point(.left, s)
        XCTAssertEqual(s.currentServer, .left)
    }

    /// product.md §12: serve rotates after every game, so the set boundary is not
    /// a reset — the side that did not serve the last game of a set opens the next.
    func testServeRotatesIntoFirstGameOfNextSet() throws {
        var s = start()
        XCTAssertEqual(s.currentServer, .left)
        for game in 1...6 {
            s = try winGame(for: .left, from: s)
            let expected: Side = game.isMultiple(of: 2) ? .left : .right
            XCTAssertEqual(s.currentServer, expected, "after game \(game)")
        }
        // Set 1 is over 6-0; Them served game 6, so Us opens set 2.
        XCTAssertEqual(s.completedSets.count, 1)
        XCTAssertEqual(s.currentSet.leftGames, 0)
        XCTAssertFalse(s.needsServerSelection)
        XCTAssertEqual(s.currentServer, .left)
    }

    func testServeRotatesAcrossSetBoundaryInContinuousPlay() throws {
        var settings = MatchSettings.default
        settings.continuousPlay = true
        var s = start(settings: settings)
        for _ in 0..<6 {
            s = try winGame(for: .left, from: s)
        }
        XCTAssertEqual(s.completedSets.count, 1)
        XCTAssertEqual(s.status, .inProgress)
        XCTAssertFalse(s.needsServerSelection)
        XCTAssertEqual(s.currentServer, .left)
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
        XCTAssertEqual(s.currentServer, .left)
        s = try point(.left, s)
        XCTAssertEqual(s.currentServer, .right)
        s = try point(.right, s)
        XCTAssertEqual(s.currentServer, .right)
        s = try point(.left, s)
        XCTAssertEqual(s.currentServer, .left)
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
        XCTAssertEqual(s.gameDisplayPair.left, "0")
        XCTAssertEqual(s.gameDisplayPair.right, "0")
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
        XCTAssertEqual(s.currentServer, .left)

        s = try point(.left, s) // point 1
        XCTAssertEqual(s.currentServer, .right)

        s = try point(.right, s) // point 2
        XCTAssertEqual(s.currentServer, .right)

        s = try point(.left, s) // point 3
        XCTAssertEqual(s.currentServer, .left)
    }

    /// product.md §12: the tie-break is entered on the normal rotation, so the
    /// side that did not serve game 12 serves the opening tie-break point.
    func testServeRotatesIntoTieBreakOpeningPoint() throws {
        var s = start()
        for _ in 0..<5 {
            s = try winGame(for: .left, from: s)
            s = try winGame(for: .right, from: s)
        }
        s = try winGame(for: .left, from: s)  // 6-5, game 11 served by Us
        XCTAssertEqual(s.currentServer, .right)
        s = try winGame(for: .right, from: s) // 6-6, game 12 served by Them
        XCTAssertTrue(s.currentGame.isTieBreak)
        XCTAssertEqual(s.currentServer, .left)
    }

    /// The side that opens a tie-break receives first in the next set, whatever
    /// the tie-break's length.
    func testServeAfterTieBreakPassesToTieBreakReceiver() throws {
        var s = try reachSixSix(from: start())
        XCTAssertEqual(s.currentServer, .left) // Us opens the tie-break

        s = try winTieBreak(for: .left, points: 7, from: s) // 7-0, even flip count
        XCTAssertEqual(s.completedSets.count, 1)
        XCTAssertFalse(s.needsServerSelection)
        XCTAssertEqual(s.currentServer, .right)
    }

    func testServeAfterOddLengthTieBreakPassesToTieBreakReceiver() throws {
        var s = try reachSixSix(from: start())
        XCTAssertEqual(s.currentServer, .left) // Us opens the tie-break

        s = try winTieBreak(for: .right, points: 2, from: s)
        s = try winTieBreak(for: .left, points: 7, from: s) // 7-2, odd flip count
        XCTAssertEqual(s.completedSets.count, 1)
        XCTAssertEqual(s.completedSets[0].leftGames, 7)
        XCTAssertFalse(s.needsServerSelection)
        XCTAssertEqual(s.currentServer, .right)
    }

    func testAskServeAtSetStartStillPromptsAfterTieBreak() throws {
        var settings = MatchSettings.default
        settings.askServeAtSetStart = true
        var s = engine.startMatch(settings: settings)
        s = try engine.apply(.selectServer(.left), to: s)
        s = try reachSixSix(from: s)
        s = try winTieBreak(for: .left, points: 7, from: s)
        XCTAssertEqual(s.completedSets.count, 1)
        XCTAssertTrue(s.needsServerSelection)
        XCTAssertNil(s.currentServer)
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
        XCTAssertEqual(s.gameDisplayPair.left, "15")
        XCTAssertEqual(s.gameDisplayPair.right, "0")
        XCTAssertEqual(s.events.filter { $0.kind == .pointWon }.count, 1)
    }

    func testUndoAfterGameWonRestoresPreviousGame() throws {
        var s = start()
        s = try winGame(for: .left, from: s)
        XCTAssertEqual(s.currentSet.leftGames, 1)
        s = try engine.apply(.undo, to: s)
        XCTAssertEqual(s.currentSet.leftGames, 0)
        XCTAssertEqual(s.gameDisplayPair.left, "40")
    }

    func testUndoSilverPointReturnsToAdvantage() throws {
        var s = try reachDeuce(start(settings: settings(.silverPoint)))
        s = try point(.left, s)
        s = try point(.right, s)
        XCTAssertTrue(s.currentGame.isGoldenPointActive)
        s = try engine.apply(.undo, to: s)
        XCTAssertFalse(s.currentGame.isGoldenPointActive)
        XCTAssertEqual(s.currentGame.advantageSide, .left)
    }

    func testUndoGoldenPointReturnsToFortyThirty() throws {
        var s = try reachDeuce(start(settings: settings(.goldenPoint)))
        XCTAssertTrue(s.currentGame.isGoldenPointActive)
        s = try engine.apply(.undo, to: s)
        XCTAssertFalse(s.currentGame.isGoldenPointActive)
        XCTAssertEqual(s.gameDisplayPair.left, "40")
        XCTAssertEqual(s.gameDisplayPair.right, "30")
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
