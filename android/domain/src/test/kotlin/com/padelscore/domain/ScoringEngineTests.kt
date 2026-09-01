package com.padelscore.domain

import java.time.Instant
import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Assertions.assertFalse
import org.junit.jupiter.api.Assertions.assertNotNull
import org.junit.jupiter.api.Assertions.assertNull
import org.junit.jupiter.api.Assertions.assertThrows
import org.junit.jupiter.api.Assertions.assertTrue
import org.junit.jupiter.api.Test

class ScoringEngineTests {
    private val engine = ScoringEngine()

    /** Defaults with sides swapping after each game — most scoring tests assume server flips. */
    private val rotatingSettings: MatchSettings
        get() = MatchSettings().copy(fixedServerPositions = false)

    private fun start(settings: MatchSettings? = null): MatchState {
        val initial = engine.startMatch(settings ?: rotatingSettings)
        return try {
            engine.apply(MatchAction.SelectServer(Side.Left), initial)
        } catch (_: ScoringError) {
            initial
        }
    }

    private fun startUnselected(settings: MatchSettings? = null): MatchState {
        return engine.startMatch(settings ?: rotatingSettings)
    }

    private fun point(side: Side, state: MatchState): MatchState {
        return engine.apply(MatchAction.PointWon(side), state)
    }

    private fun winGame(forSide: Side, from: MatchState): MatchState {
        var s = from
        if (s.needsServerSelection) {
            s = engine.apply(MatchAction.SelectServer(Side.Left), s)
        }
        // Win four straight points from love.
        repeat(4) {
            s = point(forSide, s)
        }
        return s
    }

    private fun reachSixSix(from: MatchState): MatchState {
        var s = from
        repeat(6) {
            s = winGame(Side.Left, s)
            s = winGame(Side.Right, s)
        }
        return s
    }

    private fun winTieBreak(forSide: Side, points: Int, from: MatchState): MatchState {
        var s = from
        repeat(points) {
            s = point(forSide, s)
        }
        return s
    }

    // MARK: - Point progression

    @Test
    fun testSetStartRequiresServerSelectionBeforeScoring() {
        val s = startUnselected()
        assertTrue(s.needsServerSelection)
        val error = assertThrows(ScoringError::class.java) {
            point(Side.Left, s)
        }
        assertEquals(ScoringError.InvalidAction, error)
    }

    @Test
    fun testSelectingServerSetsCurrentServer() {
        val s = startUnselected()
        val selected = engine.apply(MatchAction.SelectServer(Side.Right), s)
        assertFalse(selected.needsServerSelection)
        assertEquals(Side.Right, selected.currentServer)
    }

    @Test
    fun testLoveToFifteenToThirtyToFortyToGame() {
        var s = start()
        s = point(Side.Left, s)
        assertEquals("15", s.gameDisplayPair.first)
        s = point(Side.Left, s)
        assertEquals("30", s.gameDisplayPair.first)
        s = point(Side.Left, s)
        assertEquals("40", s.gameDisplayPair.first)
        s = point(Side.Left, s)
        assertEquals(1, s.currentSet.leftGames)
        assertEquals("0", s.gameDisplayPair.first)
        assertEquals("0", s.gameDisplayPair.second)
    }

    @Test
    fun testOpponentBelowFortyThenFortyWinsGame() {
        var s = start()
        s = point(Side.Left, s)
        s = point(Side.Left, s)
        s = point(Side.Left, s) // 40-0
        s = point(Side.Right, s) // 40-15
        s = point(Side.Left, s)
        assertEquals(1, s.currentSet.leftGames)
    }

    // MARK: - Deuce / Advantage / Silver Point / Golden Point

    /** Rotating-serve settings pinned to a specific deuce format. */
    private fun settings(format: DeuceFormat): MatchSettings {
        return rotatingSettings.copy(deuceFormat = format)
    }

    /** Plays to 40-40 without ever putting a side above 40. */
    private fun reachDeuce(state: MatchState): MatchState {
        var s = state
        repeat(3) {
            s = point(Side.Left, s)
            s = point(Side.Right, s)
        }
        return s
    }

    // MARK: Regular (advantage)

    @Test
    fun testAdvantageWinsGameWhenHeld() {
        var s = reachDeuce(start(settings(DeuceFormat.Advantage)))
        assertEquals("Deuce", s.gameStatusLine)
        assertFalse(s.currentGame.isGoldenPointActive)

        s = point(Side.Left, s)
        assertEquals(Side.Left, s.currentGame.advantageSide)
        assertEquals("Advantage", s.gameStatusLine)

        s = point(Side.Left, s)
        assertEquals(1, s.currentSet.leftGames)
    }

    @Test
    fun testAdvantageCyclesIndefinitely() {
        var s = reachDeuce(start(settings(DeuceFormat.Advantage)))
        // Three full advantage-then-broken cycles must never become decisive.
        repeat(3) {
            s = point(Side.Left, s)
            assertEquals(Side.Left, s.currentGame.advantageSide)
            s = point(Side.Right, s)
            assertNull(s.currentGame.advantageSide)
            assertFalse(s.currentGame.isGoldenPointActive)
            assertEquals("Deuce", s.gameStatusLine)
        }
        assertEquals(0, s.currentSet.leftGames)
        assertEquals(0, s.currentSet.rightGames)
    }

    // MARK: Golden point

    @Test
    fun testGoldenPointIsDecisiveImmediatelyAtDeuce() {
        var s = reachDeuce(start(settings(DeuceFormat.GoldenPoint)))
        // No advantage phase at all: 40-40 is already the deciding rally.
        assertTrue(s.currentGame.isGoldenPointActive)
        assertNull(s.currentGame.advantageSide)
        assertEquals("Golden Point", s.gameStatusLine)
        assertEquals("GP", s.gameDisplayPair.first)
        assertEquals("GP", s.gameDisplayPair.second)

        s = point(Side.Right, s)
        assertEquals(1, s.currentSet.rightGames)
        assertEquals(0, s.currentSet.leftGames)
        assertFalse(s.currentGame.isGoldenPointActive)
    }

    @Test
    fun testGoldenPointNeverAwardsAdvantage() {
        var s = reachDeuce(start(settings(DeuceFormat.GoldenPoint)))
        s = point(Side.Left, s)
        // The game is over — the point did not become an advantage.
        assertEquals(1, s.currentSet.leftGames)
        assertNull(s.currentGame.advantageSide)
    }

    @Test
    fun testGoldenPointReachedFromUnevenScoreline() {
        // 40-30 → 40-40 must arm the deciding point just the same.
        var s = start(settings(DeuceFormat.GoldenPoint))
        s = point(Side.Left, s)
        s = point(Side.Left, s)
        s = point(Side.Left, s) // 40-0
        s = point(Side.Right, s)
        s = point(Side.Right, s) // 40-30
        assertFalse(s.currentGame.isGoldenPointActive)
        s = point(Side.Right, s) // 40-40
        assertTrue(s.currentGame.isGoldenPointActive)
    }

    // MARK: Silver point

    @Test
    fun testSilverPointPlaysOneAdvantageThenDecides() {
        var s = reachDeuce(start(settings(DeuceFormat.SilverPoint)))
        assertFalse(s.currentGame.isGoldenPointActive)
        assertEquals("Deuce", s.gameStatusLine)

        s = point(Side.Left, s) // Ad left
        assertEquals(Side.Left, s.currentGame.advantageSide)
        assertFalse(s.currentGame.isGoldenPointActive)

        s = point(Side.Right, s) // advantage broken → deciding point
        assertTrue(s.currentGame.isGoldenPointActive)
        assertNull(s.currentGame.advantageSide)
        assertEquals("Silver Point", s.gameStatusLine)
        assertEquals("SP", s.gameDisplayPair.first)
        assertEquals("SP", s.gameDisplayPair.second)

        s = point(Side.Right, s)
        assertEquals(1, s.currentSet.rightGames)
        assertFalse(s.currentGame.isGoldenPointActive)
    }

    @Test
    fun testSilverPointAdvantageHolderStillWinsOnSecondPoint() {
        var s = reachDeuce(start(settings(DeuceFormat.SilverPoint)))
        s = point(Side.Left, s) // Ad left
        s = point(Side.Left, s) // converts, no deciding point needed
        assertEquals(1, s.currentSet.leftGames)
    }

    @Test
    fun testSilverPointDecidingPointWinnableByEitherSide() {
        var s = reachDeuce(start(settings(DeuceFormat.SilverPoint)))
        s = point(Side.Right, s) // Ad right
        s = point(Side.Left, s) // broken → deciding point
        assertTrue(s.currentGame.isGoldenPointActive)
        s = point(Side.Left, s)
        assertEquals(1, s.currentSet.leftGames)
    }

    // MARK: Changing the deuce format mid-match

    private fun changeFormat(format: DeuceFormat, state: MatchState): MatchState {
        return engine.apply(MatchAction.SetDeuceFormat(format), state)
    }

    @Test
    fun testChangingToGoldenPointArmsTheGameInProgress() {
        var s = reachDeuce(start(settings(DeuceFormat.Advantage)))
        assertEquals("Deuce", s.gameStatusLine)

        s = changeFormat(DeuceFormat.GoldenPoint, s)
        assertEquals(DeuceFormat.GoldenPoint, s.settings.deuceFormat)
        assertTrue(s.currentGame.isGoldenPointActive)
        assertEquals("Golden Point", s.gameStatusLine)

        s = point(Side.Left, s)
        assertEquals(1, s.currentSet.leftGames)
    }

    @Test
    fun testChangingToGoldenPointSurrendersAnAdvantageAlreadyHeld() {
        var s = reachDeuce(start(settings(DeuceFormat.Advantage)))
        s = point(Side.Left, s)
        assertEquals(Side.Left, s.currentGame.advantageSide)

        s = changeFormat(DeuceFormat.GoldenPoint, s)
        assertNull(s.currentGame.advantageSide)
        assertTrue(s.currentGame.isGoldenPointActive)

        // The next rally decides it, and it can go to the side that lost the advantage.
        s = point(Side.Right, s)
        assertEquals(1, s.currentSet.rightGames)
    }

    @Test
    fun testChangingAwayFromGoldenPointDisarmsTheDecidingPoint() {
        var s = reachDeuce(start(settings(DeuceFormat.GoldenPoint)))
        assertTrue(s.currentGame.isGoldenPointActive)

        s = changeFormat(DeuceFormat.Advantage, s)
        assertFalse(s.currentGame.isGoldenPointActive)
        assertEquals("Deuce", s.gameStatusLine)

        // Back to a normal advantage phase rather than a game.
        s = point(Side.Left, s)
        assertEquals(Side.Left, s.currentGame.advantageSide)
        assertEquals(0, s.currentSet.leftGames)
    }

    @Test
    fun testChangingToSilverPointLeavesItsOneAdvantageStillToPlay() {
        var s = reachDeuce(start(settings(DeuceFormat.GoldenPoint)))
        s = changeFormat(DeuceFormat.SilverPoint, s)
        assertFalse(s.currentGame.isGoldenPointActive)

        s = point(Side.Left, s)
        assertEquals(Side.Left, s.currentGame.advantageSide)
        s = point(Side.Right, s)
        assertTrue(s.currentGame.isGoldenPointActive)
        assertEquals("Silver Point", s.gameStatusLine)
    }

    @Test
    fun testGamesAlreadyPlayedKeepTheirResultAfterAFormatChange() {
        // Two games decided on a golden point, then the format is corrected.
        var s = start(settings(DeuceFormat.GoldenPoint))
        repeat(2) {
            s = reachDeuce(s)
            s = point(Side.Left, s)
        }
        assertEquals(2, s.currentSet.leftGames)

        s = changeFormat(DeuceFormat.Advantage, s)
        assertEquals(2, s.currentSet.leftGames)
        assertEquals(0, s.completedSets.size)
    }

    @Test
    fun testUndoAfterAFormatChangeDoesNotRescoreEarlierGames() {
        var s = start(settings(DeuceFormat.GoldenPoint))
        s = reachDeuce(s)
        s = point(Side.Left, s) // golden point decides game 1
        s = changeFormat(DeuceFormat.Advantage, s)
        s = point(Side.Right, s) // first point of game 2

        s = engine.apply(MatchAction.Undo, s)
        // The undone point belongs to game 2; game 1 stays won on the golden point.
        assertEquals(1, s.currentSet.leftGames)
        assertEquals(0, s.currentGame.leftPoints)
        assertEquals(0, s.currentGame.rightPoints)
    }

    @Test
    fun testUndoRestoresTheDecidingPointArmedByAFormatChange() {
        var s = reachDeuce(start(settings(DeuceFormat.Advantage)))
        s = changeFormat(DeuceFormat.GoldenPoint, s)
        s = point(Side.Left, s)
        assertEquals(1, s.currentSet.leftGames)

        s = engine.apply(MatchAction.Undo, s)
        assertEquals(0, s.currentSet.leftGames)
        assertTrue(s.currentGame.isGoldenPointActive)
    }

    @Test
    fun testFormatCanBeChangedRepeatedly() {
        var s = reachDeuce(start(settings(DeuceFormat.Advantage)))
        s = changeFormat(DeuceFormat.GoldenPoint, s)
        s = changeFormat(DeuceFormat.SilverPoint, s)
        s = changeFormat(DeuceFormat.Advantage, s)
        assertEquals(DeuceFormat.Advantage, s.settings.deuceFormat)
        assertFalse(s.currentGame.isGoldenPointActive)
        assertEquals(4, s.deuceFormatChanges.size)
    }

    @Test
    fun testChangingToTheSameFormatIsANoOp() {
        val s = reachDeuce(start(settings(DeuceFormat.GoldenPoint)))
        val unchanged = changeFormat(DeuceFormat.GoldenPoint, s)
        assertEquals(s, unchanged)
        assertTrue(unchanged.deuceFormatChanges.isEmpty())
    }

    @Test
    fun testFormatChangeMidTieBreakLeavesItAlone() {
        var s = reachSixSix(start(settings(DeuceFormat.Advantage)))
        s = point(Side.Left, s)
        s = point(Side.Right, s)
        assertTrue(s.currentGame.isTieBreak)

        s = changeFormat(DeuceFormat.GoldenPoint, s)
        assertTrue(s.currentGame.isTieBreak)
        assertFalse(s.currentGame.isGoldenPointActive)
        assertEquals(1, s.currentGame.leftPoints)
        assertEquals(1, s.currentGame.rightPoints)
    }

    @Test
    fun testFormatCannotBeChangedOnATerminalMatch() {
        val s = engine.apply(MatchAction.EndEarly, start(settings(DeuceFormat.Advantage)))
        val error = assertThrows(ScoringError::class.java) {
            changeFormat(DeuceFormat.GoldenPoint, s)
        }
        assertEquals(ScoringError.MatchNotInProgress, error)
    }

    // MARK: - Set / Match

    @Test
    fun testSetRequiresWinByTwo() {
        var s = start()
        // 5-5
        repeat(5) {
            s = winGame(Side.Left, s)
            s = winGame(Side.Right, s)
        }
        s = winGame(Side.Left, s) // 6-5
        assertEquals(6, s.currentSet.leftGames)
        assertEquals(0, s.completedSets.size)
        s = winGame(Side.Left, s) // 7-5 set
        assertEquals(1, s.completedSets.size)
        assertEquals(1, s.leftSetsWon)
        assertEquals(0, s.currentSet.leftGames)
        assertFalse(s.needsServerSelection)
        assertEquals(Side.Left, s.currentServer)
    }

    @Test
    fun testSetStartRequiresServerSelectionWhenEnabled() {
        val settings = MatchSettings().copy(
            fixedServerPositions = false,
            askServeAtSetStart = true,
        )
        var s = start(settings)
        repeat(5) {
            s = winGame(Side.Left, s)
            s = winGame(Side.Right, s)
        }
        s = winGame(Side.Left, s) // 6-5
        s = winGame(Side.Left, s) // 7-5 set
        assertTrue(s.needsServerSelection)
        assertNull(s.currentServer)
    }

    @Test
    fun testServerContinuesAcrossSetBoundaryByDefault() {
        var s = start()
        repeat(5) {
            s = winGame(Side.Left, s)
            s = winGame(Side.Right, s)
        }
        s = winGame(Side.Left, s) // 6-5, game 11 served by Us
        s = winGame(Side.Left, s) // 7-5 set, game 12 served by Them
        assertFalse(s.needsServerSelection)
        // Serve rotates after the set-winning game like any other game.
        assertEquals(Side.Left, s.currentServer)
        s = point(Side.Left, s)
        assertEquals(Side.Left, s.currentServer)
    }

    /**
     * product.md §12: serve rotates after every game, so the set boundary is not
     * a reset — the side that did not serve the last game of a set opens the next.
     */
    @Test
    fun testServeRotatesIntoFirstGameOfNextSet() {
        var s = start()
        assertEquals(Side.Left, s.currentServer)
        for (game in 1..6) {
            s = winGame(Side.Left, s)
            val expected = if (game % 2 == 0) Side.Left else Side.Right
            assertEquals(expected, s.currentServer, "after game $game")
        }
        // Set 1 is over 6-0; Them served game 6, so Us opens set 2.
        assertEquals(1, s.completedSets.size)
        assertEquals(0, s.currentSet.leftGames)
        assertFalse(s.needsServerSelection)
        assertEquals(Side.Left, s.currentServer)
    }

    @Test
    fun testServeRotatesAcrossSetBoundaryInContinuousPlay() {
        val settings = MatchSettings().copy(continuousPlay = true)
        var s = start(settings)
        repeat(6) {
            s = winGame(Side.Left, s)
        }
        assertEquals(1, s.completedSets.size)
        assertEquals(MatchStatus.InProgress, s.status)
        assertFalse(s.needsServerSelection)
        assertEquals(Side.Left, s.currentServer)
    }

    // MARK: - Choosing a new server at the changeover

    /**
     * Runs a 6-0 set out. Serve has flipped six times, so it comes back to whoever
     * opened the match for the first game of the next set.
     */
    private fun winFirstSet(from: MatchState): MatchState {
        var s = from
        repeat(6) {
            s = winGame(Side.Left, s)
        }
        return s
    }

    @Test
    fun testNewServeIsNotOfferedBeforeTheFirstSetEnds() {
        val s = start()
        assertTrue(s.completedSets.isEmpty())
        assertTrue(s.isAtSetStart)
        assertFalse(s.canChooseNewServer)
    }

    @Test
    fun testNewServeAtTheChangeoverAsksWhoIsServing() {
        var s = winFirstSet(start())
        assertEquals(1, s.completedSets.size)
        assertTrue(s.canChooseNewServer)

        s = engine.apply(MatchAction.RequestServerSelection, s)
        assertTrue(s.needsServerSelection)
        assertNull(s.currentServer)
        val error = assertThrows(ScoringError::class.java) {
            point(Side.Left, s)
        }
        assertEquals(ScoringError.InvalidAction, error)
    }

    @Test
    fun testServerChosenAtTheChangeoverSurvivesReplay() {
        var s = winFirstSet(start())
        assertEquals(Side.Left, s.currentServer) // rotation would carry Us on

        s = engine.apply(MatchAction.RequestServerSelection, s)
        s = engine.apply(MatchAction.SelectServer(Side.Right), s)
        assertFalse(s.needsServerSelection)
        assertEquals(Side.Right, s.currentServer)

        // Every later action replays the whole stream, so the choice has to survive it.
        s = point(Side.Left, s)
        assertEquals(Side.Right, s.currentServer)
        s = engine.apply(MatchAction.Undo, s)
        assertEquals(Side.Right, s.currentServer)
        assertEquals(1, s.completedSets.size)
    }

    @Test
    fun testNewServeIsRefusedOnceTheSetIsUnderWay() {
        var s = winFirstSet(start())
        s = point(Side.Left, s)
        assertFalse(s.canChooseNewServer)
        val error = assertThrows(ScoringError::class.java) {
            engine.apply(MatchAction.RequestServerSelection, s)
        }
        assertEquals(ScoringError.InvalidAction, error)
    }

    @Test
    fun testNewServeChangesNothingWhileAlreadyAsking() {
        val settings = MatchSettings().copy(askServeAtSetStart = true)
        val s = winFirstSet(start(settings))
        assertTrue(s.needsServerSelection)
        assertFalse(s.canChooseNewServer)
        assertEquals(s, engine.apply(MatchAction.RequestServerSelection, s))
    }

    @Test
    fun testChangingDeuceFormatKeepsNewServePrompt() {
        var s = winFirstSet(start())
        s = engine.apply(MatchAction.RequestServerSelection, s)
        assertTrue(s.needsServerSelection)
        assertNull(s.currentServer)

        s = engine.apply(MatchAction.SetDeuceFormat(DeuceFormat.Advantage), s)
        assertTrue(s.needsServerSelection)
        assertNull(s.currentServer)
        assertEquals(DeuceFormat.Advantage, s.settings.deuceFormat)
        assertTrue(s.isAtSetStart)
    }

    @Test
    fun testRehydratePreservesNewServePrompt() {
        var s = winFirstSet(start())
        s = engine.apply(MatchAction.RequestServerSelection, s)
        val rehydrated = engine.rehydrate(s)
        assertTrue(rehydrated.needsServerSelection)
        assertNull(rehydrated.currentServer)
        assertEquals(1, rehydrated.completedSets.size)
    }

    /**
     * Undo moves the set boundary back, which strands a server chosen for a set that
     * is no longer over. The mid-set rotation has to win.
     */
    @Test
    fun testUndoingTheSetWinningPointDropsTheServerChosenForTheNextSet() {
        var s = start()
        repeat(5) {
            s = winGame(Side.Left, s)
        }
        s = point(Side.Left, s)
        s = point(Side.Left, s)
        s = point(Side.Left, s) // 5-0, 40-0 on serve
        val serverBeforeSetPoint = s.currentServer
        s = point(Side.Left, s) // 6-0 set

        s = engine.apply(MatchAction.RequestServerSelection, s)
        s = engine.apply(MatchAction.SelectServer(Side.Right), s)
        s = engine.apply(MatchAction.Undo, s)

        assertEquals(0, s.completedSets.size)
        assertEquals(5, s.currentSet.leftGames)
        assertFalse(s.needsServerSelection)
        assertEquals(serverBeforeSetPoint, s.currentServer)
    }

    @Test
    fun testServerAutoTogglesAfterEachCompletedGame() {
        var s = startUnselected()
        s = engine.apply(MatchAction.SelectServer(Side.Left), s)
        assertEquals(Side.Left, s.currentServer)
        s = winGame(Side.Left, s)
        assertEquals(Side.Right, s.currentServer)
        s = winGame(Side.Right, s)
        assertEquals(Side.Left, s.currentServer)
    }

    @Test
    fun testMatchStartAlwaysRequiresServerSelection() {
        val s = startUnselected()
        assertTrue(s.needsServerSelection)
        assertNull(s.currentServer)
    }

    // MARK: - Pre-match warm-up

    @Test
    fun testMatchStartArmsWarmUpByDefault() {
        val s = startUnselected()
        assertTrue(s.needsWarmUp)
        assertTrue(s.settings.warmUpEnabled)
        assertEquals(0, s.settings.warmUpMinutes)
        assertTrue(s.isWaitingForFirstServe)
        assertNull(s.warmUpRemaining())
    }

    @Test
    fun testWarmUpCanBeDisabledAtMatchStart() {
        val settings = MatchSettings().copy(warmUpEnabled = false)
        val s = engine.startMatch(settings)
        assertFalse(s.needsWarmUp)
        assertTrue(s.needsServerSelection)
    }

    @Test
    fun testCompleteWarmUpClearsFlagAndStillAsksWhoServes() {
        val initial = startUnselected()
        val s = engine.apply(MatchAction.CompleteWarmUp, initial)
        assertFalse(s.needsWarmUp)
        assertTrue(s.needsServerSelection)
        assertNull(s.currentServer)
    }

    @Test
    fun testCompleteWarmUpIsIdempotent() {
        var s = startUnselected()
        s = engine.apply(MatchAction.CompleteWarmUp, s)
        assertEquals(s, engine.apply(MatchAction.CompleteWarmUp, s))
    }

    @Test
    fun testWarmUpRemainingUsesStartedAt() {
        val start = Instant.ofEpochSecond(1_000)
        val settings = MatchSettings().copy(warmUpMinutes = 5)
        val s = engine.startMatch(settings = settings, at = start)
        assertEquals(300.0, s.warmUpRemaining(start))
        assertEquals(240.0, s.warmUpRemaining(start.plusSeconds(60)))
        assertEquals(0.0, s.warmUpRemaining(start.plusSeconds(400)))
        val done = try {
            engine.apply(MatchAction.CompleteWarmUp, s)
        } catch (_: ScoringError) {
            null
        }
        assertNull(done?.warmUpRemaining(start))
    }

    @Test
    fun testUnlimitedWarmUpCountsElapsedAndNeverExpires() {
        val start = Instant.ofEpochSecond(1_000)
        val s = engine.startMatch(at = start)
        assertEquals(0, s.settings.warmUpMinutes)
        assertNull(s.warmUpRemaining(start.plusSeconds(400)))
        assertFalse(s.isWarmUpExpired(start.plusSeconds(400)))
        assertEquals(90.0, s.warmUpElapsed(start.plusSeconds(90)))
    }

    @Test
    fun testWarmUpIsNotReArmedAtSetStart() {
        var s = startUnselected()
        s = engine.apply(MatchAction.CompleteWarmUp, s)
        s = engine.apply(MatchAction.SelectServer(Side.Left), s)
        repeat(5) {
            s = winGame(Side.Left, s)
            s = winGame(Side.Right, s)
        }
        s = winGame(Side.Left, s)
        s = winGame(Side.Left, s)
        assertEquals(1, s.completedSets.size)
        assertTrue(s.isAtSetStart)
        assertFalse(s.needsWarmUp)
        s = engine.apply(MatchAction.RequestServerSelection, s)
        assertTrue(s.needsServerSelection)
        assertFalse(s.needsWarmUp)
        assertEquals(s, engine.apply(MatchAction.CompleteWarmUp, s))
    }

    @Test
    fun testRehydratePreservesWarmUp() {
        val s = startUnselected()
        assertTrue(s.needsWarmUp)
        val rehydrated = engine.rehydrate(s)
        assertTrue(rehydrated.needsWarmUp)
        assertTrue(rehydrated.needsServerSelection)
    }

    @Test
    fun testRehydrateDoesNotRestoreCompletedWarmUp() {
        val s = engine.apply(MatchAction.CompleteWarmUp, startUnselected())
        val rehydrated = engine.rehydrate(s)
        assertFalse(rehydrated.needsWarmUp)
        assertTrue(rehydrated.needsServerSelection)
    }

    @Test
    fun testDeuceFormatChangeKeepsWarmUp() {
        var s = startUnselected()
        s = engine.apply(MatchAction.SetDeuceFormat(DeuceFormat.Advantage), s)
        assertTrue(s.needsWarmUp)
        assertTrue(s.needsServerSelection)
        assertEquals(DeuceFormat.Advantage, s.settings.deuceFormat)
    }

    @Test
    fun testFixedServerPositionsStillRequiresServerSelectionAtMatchStart() {
        val settings = MatchSettings().copy(fixedServerPositions = true)
        val s = engine.startMatch(settings)
        assertTrue(s.needsServerSelection)
        assertNull(s.currentServer)
    }

    @Test
    fun testUsThemLabelsFollowServeOrientation() {
        var s = start()
        assertEquals("Us", s.servingRoleLabels.first)
        assertEquals("Them", s.servingRoleLabels.second)
        assertEquals(Side.Left, s.scoreScreenSides.first)
        assertEquals(Side.Right, s.scoreScreenSides.second)

        s = winGame(Side.Right, s)
        assertEquals(Side.Right, s.currentServer)
        assertEquals("Them", s.servingRoleLabels.first)
        assertEquals("Us", s.servingRoleLabels.second)
        assertEquals(Side.Right, s.scoreScreenSides.first)
        assertEquals(Side.Left, s.scoreScreenSides.second)
    }

    @Test
    fun testServingRoleLabelsStayServingLeftWhenUsThemLabelsDisabled() {
        val settings = MatchSettings().copy(
            fixedServerPositions = false,
            usThemLabels = false,
        )
        var s = start(settings)
        assertEquals("Serving", s.servingRoleLabels.first)
        assertEquals("Receiving", s.servingRoleLabels.second)

        s = winGame(Side.Right, s)
        assertEquals(Side.Right, s.currentServer)
        assertEquals("Serving", s.servingRoleLabels.first)
        assertEquals("Receiving", s.servingRoleLabels.second)
    }

    @Test
    fun testScoreScreenDisplayRemapsWhenRightServes() {
        var s = start()
        s = point(Side.Left, s)
        s = point(Side.Left, s)
        s = point(Side.Right, s)
        assertEquals("30", s.scoreScreenGameDisplay.first)
        assertEquals("15", s.scoreScreenGameDisplay.second)

        s = point(Side.Left, s)
        s = point(Side.Left, s) // Us wins game; serve rotates to Them
        assertEquals(Side.Right, s.currentServer)

        s = point(Side.Left, s)
        s = point(Side.Right, s)
        s = point(Side.Right, s)
        // Logical: Us 15, Them 30 — visual left is Them (serving)
        assertEquals("30", s.scoreScreenGameDisplay.first)
        assertEquals("15", s.scoreScreenGameDisplay.second)
        assertEquals(Side.Right, s.logicalSide(Side.Left))
        assertEquals(Side.Left, s.logicalSide(Side.Right))
        assertEquals(Side.Left, s.visualSide(Side.Right))
    }

    @Test
    fun testFixedServerPositionsRotatesServeButKeepsButtonLayout() {
        val settings = MatchSettings().copy(
            fixedServerPositions = true,
            usThemLabels = true,
        )
        var s = engine.startMatch(settings)
        s = engine.apply(MatchAction.SelectServer(Side.Left), s)
        assertEquals(Side.Left, s.currentServer)
        assertEquals(Side.Left, s.scoreScreenSides.first)
        assertEquals("Us", s.servingRoleLabels.first)
        assertEquals("Them", s.servingRoleLabels.second)

        s = winGame(Side.Left, s)
        assertEquals(Side.Right, s.currentServer)
        assertEquals(Side.Left, s.scoreScreenSides.first)
        assertEquals(Side.Right, s.scoreScreenSides.second)
        assertEquals("Us", s.servingRoleLabels.first)
        assertEquals("Them", s.servingRoleLabels.second)

        s = winGame(Side.Right, s)
        assertEquals(Side.Left, s.currentServer)
        assertEquals(Side.Left, s.scoreScreenSides.first)
    }

    @Test
    fun testFixedServerPositionsKeepsLayoutWhenRightServes() {
        val settings = MatchSettings().copy(
            fixedServerPositions = true,
            usThemLabels = false,
        )
        var s = engine.startMatch(settings)
        s = engine.apply(MatchAction.SelectServer(Side.Right), s)
        assertEquals(Side.Right, s.currentServer)
        assertEquals(Side.Left, s.scoreScreenSides.first)
        assertEquals(Side.Right, s.scoreScreenSides.second)
        assertEquals("Receiving", s.servingRoleLabels.first)
        assertEquals("Serving", s.servingRoleLabels.second)

        s = winGame(Side.Left, s)
        assertEquals(Side.Left, s.currentServer)
        assertEquals(Side.Left, s.scoreScreenSides.first)
        assertEquals("Serving", s.servingRoleLabels.first)
        assertEquals("Receiving", s.servingRoleLabels.second)
    }

    @Test
    fun testFixedServerPositionsStillRotatesServeInTieBreak() {
        val settings = MatchSettings().copy(fixedServerPositions = true)
        var s = engine.startMatch(settings)
        s = engine.apply(MatchAction.SelectServer(Side.Left), s)
        s = reachSixSix(s)
        assertEquals(Side.Left, s.currentServer)
        s = point(Side.Left, s)
        assertEquals(Side.Right, s.currentServer)
        s = point(Side.Right, s)
        assertEquals(Side.Right, s.currentServer)
        s = point(Side.Left, s)
        assertEquals(Side.Left, s.currentServer)
    }

    @Test
    fun testAskServeAtSetStartWorksWithFixedServerPositions() {
        val settings = MatchSettings().copy(
            fixedServerPositions = true,
            askServeAtSetStart = true,
        )
        var s = engine.startMatch(settings)
        s = engine.apply(MatchAction.SelectServer(Side.Left), s)
        repeat(5) {
            s = winGame(Side.Left, s)
            s = winGame(Side.Right, s)
        }
        s = winGame(Side.Left, s) // 6-5
        s = winGame(Side.Left, s) // 7-5 set
        assertTrue(s.needsServerSelection)
        assertNull(s.currentServer)
    }

    @Test
    fun testMatchBestOfThree() {
        var s = start()
        repeat(2) {
            repeat(6) {
                s = winGame(Side.Left, s)
            }
        }
        assertEquals(MatchStatus.Completed, s.status)
        assertEquals(Side.Left, s.winner)
        assertEquals(2, s.leftSetsWon)
        assertEquals(2, s.completedSets.size)
    }

    @Test
    fun testMatchBestOfOne() {
        val settings = MatchSettings().copy(setsToWin = 1)
        var s = start(settings)
        repeat(6) {
            s = winGame(Side.Left, s)
        }
        assertEquals(MatchStatus.Completed, s.status)
        assertEquals(Side.Left, s.winner)
        assertEquals(1, s.leftSetsWon)
        assertEquals(1, s.completedSets.size)
    }

    @Test
    fun testContinuousPlayDoesNotAutoComplete() {
        val settings = MatchSettings().copy(continuousPlay = true)
        var s = start(settings)
        repeat(3) {
            repeat(6) {
                s = winGame(Side.Left, s)
            }
        }
        assertEquals(MatchStatus.InProgress, s.status)
        assertNull(s.winner)
        assertEquals(3, s.leftSetsWon)
        assertEquals(3, s.completedSets.size)
    }

    @Test
    fun testContinuousPlayFinishUsesSetLeader() {
        val settings = MatchSettings().copy(continuousPlay = true)
        var s = start(settings)
        repeat(6) {
            s = winGame(Side.Left, s)
        }
        repeat(12) {
            s = winGame(Side.Right, s)
        }
        s = engine.apply(MatchAction.Finish, s)
        assertEquals(MatchStatus.Completed, s.status)
        assertEquals(Side.Right, s.winner)
        assertEquals(1, s.leftSetsWon)
        assertEquals(2, s.rightSetsWon)
    }

    // MARK: - Tie-break

    @Test
    fun testSixSixStartsTieBreak() {
        val s = reachSixSix(start())
        assertTrue(s.currentGame.isTieBreak)
        assertEquals(6, s.currentSet.leftGames)
        assertEquals(6, s.currentSet.rightGames)
        assertEquals(0, s.completedSets.size)
        assertEquals("0", s.gameDisplayPair.first)
        assertEquals("0", s.gameDisplayPair.second)
    }

    @Test
    fun testTieBreakFirstToSevenWinsSet() {
        var s = reachSixSix(start())
        s = winTieBreak(Side.Left, 7, s)
        assertEquals(1, s.completedSets.size)
        assertEquals(7, s.completedSets[0].leftGames)
        assertEquals(6, s.completedSets[0].rightGames)
        assertEquals(1, s.leftSetsWon)
    }

    @Test
    fun testTieBreakRequiresTwoPointLead() {
        var s = reachSixSix(start())
        // 6-6 in tie-break — set not won
        s = winTieBreak(Side.Left, 6, s)
        s = winTieBreak(Side.Right, 6, s)
        assertEquals(0, s.completedSets.size)
        assertTrue(s.currentGame.isTieBreak)
        assertEquals(6, s.currentGame.leftPoints)
        assertEquals(6, s.currentGame.rightPoints)

        // 8-6 in tie-break wins set 7-6
        s = winTieBreak(Side.Left, 2, s)
        assertEquals(1, s.completedSets.size)
        assertEquals(7, s.completedSets[0].leftGames)
        assertEquals(6, s.completedSets[0].rightGames)
    }

    @Test
    fun testTieBreakServeRotation() {
        var s = reachSixSix(start())
        assertEquals(Side.Left, s.currentServer)

        s = point(Side.Left, s) // point 1
        assertEquals(Side.Right, s.currentServer)

        s = point(Side.Right, s) // point 2
        assertEquals(Side.Right, s.currentServer)

        s = point(Side.Left, s) // point 3
        assertEquals(Side.Left, s.currentServer)
    }

    /**
     * product.md §12: the tie-break is entered on the normal rotation, so the
     * side that did not serve game 12 serves the opening tie-break point.
     */
    @Test
    fun testServeRotatesIntoTieBreakOpeningPoint() {
        var s = start()
        repeat(5) {
            s = winGame(Side.Left, s)
            s = winGame(Side.Right, s)
        }
        s = winGame(Side.Left, s) // 6-5, game 11 served by Us
        assertEquals(Side.Right, s.currentServer)
        s = winGame(Side.Right, s) // 6-6, game 12 served by Them
        assertTrue(s.currentGame.isTieBreak)
        assertEquals(Side.Left, s.currentServer)
    }

    /**
     * The side that opens a tie-break receives first in the next set, whatever
     * the tie-break's length.
     */
    @Test
    fun testServeAfterTieBreakPassesToTieBreakReceiver() {
        var s = reachSixSix(start())
        assertEquals(Side.Left, s.currentServer) // Us opens the tie-break

        s = winTieBreak(Side.Left, 7, s) // 7-0, even flip count
        assertEquals(1, s.completedSets.size)
        assertFalse(s.needsServerSelection)
        assertEquals(Side.Right, s.currentServer)
    }

    @Test
    fun testServeAfterOddLengthTieBreakPassesToTieBreakReceiver() {
        var s = reachSixSix(start())
        assertEquals(Side.Left, s.currentServer) // Us opens the tie-break

        s = winTieBreak(Side.Right, 2, s)
        s = winTieBreak(Side.Left, 7, s) // 7-2, odd flip count
        assertEquals(1, s.completedSets.size)
        assertEquals(7, s.completedSets[0].leftGames)
        assertFalse(s.needsServerSelection)
        assertEquals(Side.Right, s.currentServer)
    }

    @Test
    fun testAskServeAtSetStartStillPromptsAfterTieBreak() {
        val settings = MatchSettings().copy(askServeAtSetStart = true)
        var s = engine.startMatch(settings)
        s = engine.apply(MatchAction.SelectServer(Side.Left), s)
        s = reachSixSix(s)
        s = winTieBreak(Side.Left, 7, s)
        assertEquals(1, s.completedSets.size)
        assertTrue(s.needsServerSelection)
        assertNull(s.currentServer)
    }

    @Test
    fun testTieBreakNoticeChangeSides() {
        var s = reachSixSix(start())
        assertNull(s.currentGame.tieBreakNotice)

        s = winTieBreak(Side.Left, 6, s)
        assertEquals(TieBreakNotice.ChangeSides, s.currentGame.tieBreakNotice)

        s = winTieBreak(Side.Right, 6, s)
        assertEquals(TieBreakNotice.ChangeSides, s.currentGame.tieBreakNotice)
    }

    @Test
    fun testTieBreakNoticeChangeServe() {
        var s = reachSixSix(start())
        s = point(Side.Left, s)
        assertEquals(TieBreakNotice.ChangeServe, s.currentGame.tieBreakNotice)
    }

    @Test
    fun testTieBreakUndoAndReplay() {
        var s = reachSixSix(start())
        s = point(Side.Left, s)
        s = point(Side.Right, s)
        s = engine.apply(MatchAction.Undo, s)
        assertEquals(1, s.currentGame.leftPoints)
        assertEquals(0, s.currentGame.rightPoints)
        assertTrue(s.currentGame.isTieBreak)

        val replayed = engine.replay(
            s.events,
            MatchState(id = s.id, settings = s.settings, startedAt = s.startedAt),
        )
        assertEquals(s.currentGame.leftPoints, replayed.currentGame.leftPoints)
        assertEquals(s.currentGame.isTieBreak, replayed.currentGame.isTieBreak)
    }

    // MARK: - Undo

    @Test
    fun testUndoRemovesLastPointAndRecalculates() {
        var s = start()
        s = point(Side.Left, s)
        s = point(Side.Right, s)
        s = engine.apply(MatchAction.Undo, s)
        assertEquals("15", s.gameDisplayPair.first)
        assertEquals("0", s.gameDisplayPair.second)
        assertEquals(1, s.events.count { it.kind == MatchEventKind.PointWon })
    }

    @Test
    fun testUndoAfterGameWonRestoresPreviousGame() {
        var s = start()
        s = winGame(Side.Left, s)
        assertEquals(1, s.currentSet.leftGames)
        s = engine.apply(MatchAction.Undo, s)
        assertEquals(0, s.currentSet.leftGames)
        assertEquals("40", s.gameDisplayPair.first)
    }

    @Test
    fun testUndoSilverPointReturnsToAdvantage() {
        var s = reachDeuce(start(settings(DeuceFormat.SilverPoint)))
        s = point(Side.Left, s)
        s = point(Side.Right, s)
        assertTrue(s.currentGame.isGoldenPointActive)
        s = engine.apply(MatchAction.Undo, s)
        assertFalse(s.currentGame.isGoldenPointActive)
        assertEquals(Side.Left, s.currentGame.advantageSide)
    }

    @Test
    fun testUndoGoldenPointReturnsToFortyThirty() {
        var s = reachDeuce(start(settings(DeuceFormat.GoldenPoint)))
        assertTrue(s.currentGame.isGoldenPointActive)
        s = engine.apply(MatchAction.Undo, s)
        assertFalse(s.currentGame.isGoldenPointActive)
        assertEquals("40", s.gameDisplayPair.first)
        assertEquals("30", s.gameDisplayPair.second)
    }

    @Test
    fun testUndoWithNoPointsThrows() {
        val s = start()
        val error = assertThrows(ScoringError::class.java) {
            engine.apply(MatchAction.Undo, s)
        }
        assertEquals(ScoringError.NothingToUndo, error)
    }

    // MARK: - End / Discard / Finish

    @Test
    fun testEndEarlyPreservesScore() {
        var s = start()
        s = winGame(Side.Left, s)
        s = point(Side.Right, s)
        s = engine.apply(MatchAction.EndEarly, s)
        assertEquals(MatchStatus.EndedEarly, s.status)
        assertEquals(1, s.currentSet.leftGames)
        assertNotNull(s.finishedAt)
    }

    @Test
    fun testDiscardMarksDiscarded() {
        var s = start()
        s = point(Side.Left, s)
        s = engine.apply(MatchAction.Discard, s)
        assertEquals(MatchStatus.Discarded, s.status)
    }

    @Test
    fun testFinishWithoutWinnerEndsEarlyAndMatchesReplay() {
        var s = start()
        s = point(Side.Left, s)
        s = engine.apply(MatchAction.Finish, s)
        assertEquals(MatchStatus.EndedEarly, s.status)
        assertNull(s.winner)
        val replayed = engine.replay(
            s.events,
            MatchState(id = s.id, settings = s.settings, startedAt = s.startedAt),
        )
        assertEquals(MatchStatus.EndedEarly, replayed.status)
        assertNull(replayed.winner)
    }

    @Test
    fun testReplayIsDeterministic() {
        var s = start()
        s = point(Side.Left, s)
        s = point(Side.Right, s)
        s = point(Side.Left, s)
        val replayed = engine.replay(
            s.events,
            MatchState(id = s.id, settings = s.settings, startedAt = s.startedAt),
        )
        assertEquals(s.currentGame.leftPoints, replayed.currentGame.leftPoints)
        assertEquals(s.currentGame.rightPoints, replayed.currentGame.rightPoints)
        assertEquals(s.events.size, replayed.events.size)
    }

    // MARK: - Final score summary

    @Test
    fun testFinalScoreSummaryForCompletedMatch() {
        var s = start()
        repeat(2) {
            repeat(6) {
                s = winGame(Side.Left, s)
            }
        }
        assertEquals("6-0, 6-0", s.finalScoreSummary)
    }

    @Test
    fun testFinalScoreSummaryEndedEarlyMidGame() {
        var s = start()
        repeat(3) {
            s = winGame(Side.Left, s)
        }
        repeat(2) {
            s = winGame(Side.Right, s)
        }
        s = point(Side.Left, s)
        s = point(Side.Left, s)
        s = point(Side.Left, s)
        s = point(Side.Right, s)
        s = engine.apply(MatchAction.EndEarly, s)

        assertEquals("3-2 (40-15)", s.finalScoreSummary)
    }

    @Test
    fun testFinalScoreSummaryEndedEarlyAfterCompletedSet() {
        var s = start()
        repeat(6) {
            s = winGame(Side.Left, s)
        }
        repeat(3) {
            s = winGame(Side.Left, s)
        }
        repeat(2) {
            s = winGame(Side.Right, s)
        }
        s = point(Side.Left, s)
        s = point(Side.Left, s)
        s = point(Side.Right, s)
        s = engine.apply(MatchAction.EndEarly, s)

        assertEquals("6-0, 3-2 (30-15)", s.finalScoreSummary)
    }

    @Test
    fun testFinalScoreSummaryEndedEarlyBetweenGames() {
        var s = start()
        s = winGame(Side.Left, s)
        s = engine.apply(MatchAction.EndEarly, s)

        assertEquals("1-0", s.finalScoreSummary)
    }

    @Test
    fun testFinalScoreSummaryEndedEarlyInTieBreak() {
        var s = reachSixSix(start())
        s = winTieBreak(Side.Left, 4, s)
        s = winTieBreak(Side.Right, 3, s)
        s = engine.apply(MatchAction.EndEarly, s)

        assertEquals("6-6 (4-3)", s.finalScoreSummary)
    }

    @Test
    fun testFinalScoreSummaryEndedEarlyWithNoScore() {
        var s = start()
        s = engine.apply(MatchAction.EndEarly, s)

        assertEquals("", s.finalScoreSummary)
    }

    @Test
    fun testFinalScoreSummaryFinishMidSetIncludesPartial() {
        var s = start()
        repeat(3) {
            s = winGame(Side.Left, s)
        }
        repeat(2) {
            s = winGame(Side.Right, s)
        }
        s = point(Side.Left, s)
        s = point(Side.Left, s)
        s = point(Side.Left, s)
        s = point(Side.Right, s)
        s = engine.apply(MatchAction.Finish, s)

        assertEquals(MatchStatus.EndedEarly, s.status)
        assertEquals("3-2 (40-15)", s.finalScoreSummary)
        assertTrue(s.displaysIncompleteSet)
        assertEquals(listOf("3-2"), s.setScoreLines)
    }

    @Test
    fun testFinalScoreSummaryFinishMidSetAfterCompletedSet() {
        var s = start()
        repeat(6) {
            s = winGame(Side.Left, s)
        }
        repeat(3) {
            s = winGame(Side.Left, s)
        }
        repeat(2) {
            s = winGame(Side.Right, s)
        }
        s = point(Side.Left, s)
        s = point(Side.Left, s)
        s = point(Side.Right, s)
        s = engine.apply(MatchAction.Finish, s)

        assertEquals(MatchStatus.EndedEarly, s.status)
        assertEquals("6-0, 3-2 (30-15)", s.finalScoreSummary)
        assertTrue(s.displaysIncompleteSet)
        assertEquals(listOf("6-0", "3-2"), s.setScoreLines)
    }

    @Test
    fun testFinalScoreSummaryFinishWithNoScoreOmitsPartial() {
        var s = start()
        s = engine.apply(MatchAction.Finish, s)

        assertEquals(MatchStatus.EndedEarly, s.status)
        assertEquals("", s.finalScoreSummary)
        assertFalse(s.displaysIncompleteSet)
    }
}
