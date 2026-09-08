package com.wristrally.domain

import java.nio.file.Files
import java.time.Instant
import java.util.UUID
import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Assertions.assertNull
import org.junit.jupiter.api.Assertions.assertTrue
import org.junit.jupiter.api.Test
import org.junit.jupiter.api.io.TempDir
import java.nio.file.Path

class MatchServiceTests {
    @Test
    fun testPersistAndRestoreActiveMatch() {
        val store = InMemoryMatchStore()
        val service = MatchService(store)
        service.startMatch()
        service.selectServer(Side.Left)
        service.awardPoint(Side.Left)
        assertEquals(1, store.active?.currentGame?.leftPoints)

        val restored = MatchService(store)
        assertEquals(1, restored.activeMatch?.currentGame?.leftPoints)
        assertEquals(service.activeMatch?.id, restored.activeMatch?.id)
    }

    @Test
    fun testFileStoreRoundTrip(@TempDir dir: Path) {
        val store = FileMatchStore(dir)
        val engine = ScoringEngine()
        var match = engine.startMatch()
        match = engine.apply(MatchAction.SelectServer(Side.Left), match)
        match = engine.apply(MatchAction.PointWon(Side.Right), match)
        store.saveActiveMatch(match)

        val loaded = store.loadActiveMatch()
        assertEquals(1, loaded?.currentGame?.rightPoints)

        match = engine.apply(MatchAction.EndEarly, match)
        store.saveActiveMatch(null)
        store.archiveMatch(match)
        val archive = store.loadArchivedMatches()
        assertEquals(1, archive.size)
        assertEquals(MatchStatus.EndedEarly, archive.first().status)
    }

    @Test
    fun testDiscardDoesNotArchive() {
        val store = InMemoryMatchStore()
        val service = MatchService(store)
        service.startMatch()
        service.selectServer(Side.Left)
        service.awardPoint(Side.Left)
        service.discardMatch()
        assertNull(service.activeMatch)
        assertTrue(service.archivedMatches.isEmpty())
        assertNull(store.active)
    }

    @Test
    fun testDiscardBeforeServerSelectionClearsActiveMatch() {
        val store = InMemoryMatchStore()
        val service = MatchService(store)
        service.startMatch()
        assertEquals(true, service.activeMatch?.isWaitingForFirstServe)
        service.discardMatch()
        assertNull(service.activeMatch)
        assertTrue(service.archivedMatches.isEmpty())
        assertNull(store.active)
    }

    @Test
    fun testEndEarlyArchivesAndKeepsActiveUntilAck() {
        val store = InMemoryMatchStore()
        val service = MatchService(store)
        service.startMatch()
        service.selectServer(Side.Left)
        service.awardPoint(Side.Left)
        service.endMatchEarly()
        assertEquals(MatchStatus.EndedEarly, service.activeMatch?.status)
        assertEquals(1, service.archivedMatches.size)
        service.acknowledgeCompletedMatch()
        assertNull(service.activeMatch)
        assertEquals(1, service.archivedMatches.size)
    }

    @Test
    fun testUndoViaService() {
        val store = InMemoryMatchStore()
        val service = MatchService(store)
        service.startMatch()
        service.selectServer(Side.Left)
        service.awardPoint(Side.Left)
        service.awardPoint(Side.Right)
        service.undoLastPoint()
        assertEquals(1, service.activeMatch?.currentGame?.leftPoints)
        assertEquals(0, service.activeMatch?.currentGame?.rightPoints)
    }

    @Test
    fun testSelectingServerUpdatesActiveMatch() {
        val store = InMemoryMatchStore()
        val service = MatchService(store)
        service.startMatch()
        assertEquals(true, service.activeMatch?.needsServerSelection)
        service.selectServer(Side.Right)
        assertEquals(false, service.activeMatch?.needsServerSelection)
        assertEquals(Side.Right, service.activeMatch?.currentServer)
    }

    @Test
    fun testCompleteWarmUpPersistsAndKeepsServePrompt() {
        val store = InMemoryMatchStore()
        val service = MatchService(store)
        service.startMatch()
        assertEquals(true, service.activeMatch?.needsWarmUp)
        assertEquals(true, service.activeMatch?.needsServerSelection)
        service.completeWarmUp()
        assertEquals(false, service.activeMatch?.needsWarmUp)
        assertEquals(true, service.activeMatch?.needsServerSelection)
        assertEquals(false, store.active?.needsWarmUp)
    }

    @Test
    fun testNewServeAtTheChangeoverPromptsAndPersists() {
        val store = InMemoryMatchStore()
        val service = MatchService(store)
        service.startMatch(MatchSettings().copy(setsToWin = 2))
        service.selectServer(Side.Left)
        repeat(24) { service.awardPoint(Side.Left) }
        assertEquals(1, service.activeMatch?.completedSets?.size)

        service.requestServerSelection()
        assertEquals(true, service.activeMatch?.needsServerSelection)
        assertEquals(true, store.active?.needsServerSelection)

        service.selectServer(Side.Right)
        assertEquals(Side.Right, service.activeMatch?.currentServer)
        service.awardPoint(Side.Left)
        assertEquals(Side.Right, service.activeMatch?.currentServer)
        assertEquals(1, store.active?.currentGame?.leftPoints)
    }

    @Test
    fun testStartMatchPersistsDeuceFormat() {
        val store = InMemoryMatchStore()
        val service = MatchService(store)
        service.startMatch(MatchSettings().copy(deuceFormat = DeuceFormat.SilverPoint))
        assertEquals(DeuceFormat.SilverPoint, service.activeMatch?.settings?.deuceFormat)
        assertEquals(DeuceFormat.SilverPoint, store.active?.settings?.deuceFormat)
    }

    @Test
    fun testDeuceFormatCanBeChangedMidMatchAndPersists() {
        val store = InMemoryMatchStore()
        val service = MatchService(store)
        service.startMatch(MatchSettings().copy(deuceFormat = DeuceFormat.Advantage))
        service.selectServer(Side.Left)
        repeat(3) {
            service.awardPoint(Side.Left)
            service.awardPoint(Side.Right)
        }
        assertEquals("Deuce", service.activeMatch?.gameStatusLine)

        service.setDeuceFormat(DeuceFormat.GoldenPoint)
        assertEquals(DeuceFormat.GoldenPoint, service.activeMatch?.settings?.deuceFormat)
        assertEquals(true, service.activeMatch?.currentGame?.isGoldenPointActive)
        assertEquals(DeuceFormat.GoldenPoint, store.active?.settings?.deuceFormat)

        service.awardPoint(Side.Left)
        assertEquals(1, service.activeMatch?.currentSet?.leftGames)
    }

    @Test
    fun testDeuceFormatChangeIgnoredWithoutAnActiveMatch() {
        val store = InMemoryMatchStore()
        val service = MatchService(store)
        service.setDeuceFormat(DeuceFormat.Advantage)
        assertNull(service.activeMatch)
    }

    @Test
    fun testExpireInactiveMatchWithPointsEndsEarly() {
        val engine = ScoringEngine()
        val oldDate = Instant.now().minusSeconds(31 * 60)
        var match = engine.startMatch(at = oldDate)
        match = engine.apply(MatchAction.SelectServer(Side.Left), match, oldDate)
        match = engine.apply(MatchAction.PointWon(Side.Left), match, oldDate)

        val service = serviceWithActiveMatch(match)
        service.expireInactiveMatchIfNeeded()

        assertEquals(MatchStatus.EndedEarly, service.activeMatch?.status)
        assertEquals(1, service.archivedMatches.size)
    }

    @Test
    fun testExpireInactiveMatchWithRecentPointStaysInProgress() {
        val engine = ScoringEngine()
        val startDate = Instant.now().minusSeconds(60 * 60)
        val recentDate = Instant.now().minusSeconds(5 * 60)
        var match = engine.startMatch(at = startDate)
        match = engine.apply(MatchAction.SelectServer(Side.Left), match, startDate)
        match = engine.apply(MatchAction.PointWon(Side.Left), match, recentDate)

        val service = serviceWithActiveMatch(match)
        service.expireInactiveMatchIfNeeded()

        assertEquals(MatchStatus.InProgress, service.activeMatch?.status)
        assertTrue(service.archivedMatches.isEmpty())
    }

    @Test
    fun testExpireInactiveZeroPointMatchDiscards() {
        val engine = ScoringEngine()
        val oldDate = Instant.now().minusSeconds(31 * 60)
        val match = engine.startMatch(at = oldDate)

        val service = serviceWithActiveMatch(match)
        service.expireInactiveMatchIfNeeded()

        assertNull(service.activeMatch)
        assertTrue(service.archivedMatches.isEmpty())
    }

    @Test
    fun testExpireInactiveRecentZeroPointMatchStaysInProgress() {
        val engine = ScoringEngine()
        val recentDate = Instant.now().minusSeconds(5 * 60)
        val match = engine.startMatch(at = recentDate)

        val service = serviceWithActiveMatch(match)
        service.expireInactiveMatchIfNeeded()

        assertEquals(MatchStatus.InProgress, service.activeMatch?.status)
    }

    @Test
    fun testRestoreExpiresInactiveMatch() {
        val store = InMemoryMatchStore()
        val engine = ScoringEngine()
        val oldDate = Instant.now().minusSeconds(31 * 60)
        var match = engine.startMatch(at = oldDate)
        match = engine.apply(MatchAction.SelectServer(Side.Left), match, oldDate)
        match = engine.apply(MatchAction.PointWon(Side.Left), match, oldDate)
        store.active = match

        val service = MatchService(store)

        assertEquals(MatchStatus.EndedEarly, service.activeMatch?.status)
        assertEquals(1, service.archivedMatches.size)
    }

    @Test
    fun testUndoAllPointsOnInactiveMatchDiscards() {
        val engine = ScoringEngine()
        val startDate = Instant.now().minusSeconds(31 * 60)
        val recentDate = Instant.now().minusSeconds(5 * 60)
        var match = engine.startMatch(at = startDate)
        match = engine.apply(MatchAction.SelectServer(Side.Left), match, startDate)
        match = engine.apply(MatchAction.PointWon(Side.Left), match, recentDate)

        val service = serviceWithActiveMatch(match)
        service.undoLastPoint()

        assertNull(service.activeMatch)
        assertTrue(service.archivedMatches.isEmpty())
    }

    @Test
    fun testDeleteArchivedMatchRemovesItAndRecordsTombstone() {
        val store = InMemoryMatchStore()
        val service = MatchService(store)
        service.startMatch()
        service.selectServer(Side.Left)
        service.awardPoint(Side.Left)
        service.endMatchEarly()
        service.acknowledgeCompletedMatch()
        val id = service.archivedMatches.first().id

        service.deleteArchivedMatch(id)

        assertTrue(service.archivedMatches.isEmpty())
        assertTrue(store.archive.isEmpty())
        assertEquals(setOf(id), store.deletedIDs)
    }

    @Test
    fun testDeletedMatchDoesNotReturnViaRemoteSnapshot() {
        val store = InMemoryMatchStore()
        val engine = ScoringEngine()
        var match = engine.startMatch()
        match = engine.apply(MatchAction.SelectServer(Side.Left), match)
        match = engine.apply(MatchAction.PointWon(Side.Left), match)
        match = engine.apply(MatchAction.EndEarly, match)
        store.archive = mutableListOf(match)

        val service = MatchService(store)
        service.deleteArchivedMatch(match.id)

        service.applyRemoteSnapshot(null, listOf(match))

        assertTrue(service.archivedMatches.isEmpty())
        assertTrue(store.archive.isEmpty())
    }

    @Test
    fun testDeletedMatchStaysDeletedAcrossRestore() {
        val store = InMemoryMatchStore()
        val engine = ScoringEngine()
        var match = engine.startMatch()
        match = engine.apply(MatchAction.EndEarly, match)
        store.archive = mutableListOf(match)

        val service = MatchService(store)
        service.deleteArchivedMatch(match.id)

        val restored = MatchService(store)
        assertTrue(restored.archivedMatches.isEmpty())
        assertEquals(setOf(match.id), restored.deletedMatchIDs)
    }

    @Test
    fun testDeleteIgnoresTheActiveMatch() {
        val store = InMemoryMatchStore()
        val service = MatchService(store)
        service.startMatch()
        service.selectServer(Side.Left)
        service.awardPoint(Side.Left)
        service.endMatchEarly()
        val id = service.activeMatch!!.id

        service.deleteArchivedMatch(id)

        assertEquals(1, service.archivedMatches.size)
        assertTrue(service.deletedMatchIDs.isEmpty())
    }

    @Test
    fun testRemoteDeletionsPruneArchiveButNotActiveMatch() {
        val store = InMemoryMatchStore()
        val engine = ScoringEngine()
        var archived = engine.startMatch()
        archived = engine.apply(MatchAction.EndEarly, archived)
        store.archive = mutableListOf(archived)

        val service = MatchService(store)
        service.startMatch()
        val activeID = service.activeMatch!!.id

        service.applyRemoteDeletions(setOf(archived.id, activeID))

        assertTrue(service.archivedMatches.isEmpty())
        assertTrue(store.archive.isEmpty())
        assertEquals(activeID, service.activeMatch?.id)
        assertEquals(setOf(archived.id), service.deletedMatchIDs)
        assertEquals(setOf(archived.id), store.deletedIDs)
    }

    @Test
    fun testDeletedIDsSurviveFileStoreRoundTrip(@TempDir dir: Path) {
        val store = FileMatchStore(dir)
        assertTrue(store.loadDeletedMatchIDs().isEmpty())

        val ids = setOf(UUID.randomUUID(), UUID.randomUUID())
        store.saveDeletedMatchIDs(ids)

        assertEquals(ids, FileMatchStore(dir).loadDeletedMatchIDs())
    }

    @Test
    fun testNoteIsStoredTrimmedAndClearedWhenBlank() {
        val store = InMemoryMatchStore()
        val engine = ScoringEngine()
        val match = engine.apply(MatchAction.EndEarly, engine.startMatch())
        store.archive = mutableListOf(match)
        val service = MatchService(store)

        service.setNote("  Played with Sam, windy court\n", match.id)
        assertEquals("Played with Sam, windy court", service.note(match.id))
        assertEquals("Played with Sam, windy court", store.notes[match.id])

        service.setNote("   ", match.id)
        assertEquals("", service.note(match.id))
        assertNull(store.notes[match.id])
    }

    @Test
    fun testNoteSurvivesRemoteSnapshotAndRestore() {
        val store = InMemoryMatchStore()
        val engine = ScoringEngine()
        val match = engine.apply(MatchAction.EndEarly, engine.startMatch())
        store.archive = mutableListOf(match)
        val service = MatchService(store)
        service.setNote("Left knee sore", match.id)

        service.applyRemoteSnapshot(null, listOf(match))
        assertEquals("Left knee sore", service.note(match.id))

        val restored = MatchService(store)
        assertEquals("Left knee sore", restored.note(match.id))
    }

    @Test
    fun testDeletingAMatchDropsItsNoteForGood() {
        val store = InMemoryMatchStore()
        val engine = ScoringEngine()
        val match = engine.apply(MatchAction.EndEarly, engine.startMatch())
        store.archive = mutableListOf(match)
        val service = MatchService(store)
        service.setNote("Best of the season", match.id)

        service.deleteArchivedMatch(match.id)
        assertTrue(store.notes.isEmpty())

        service.setNote("Best of the season", match.id)
        assertTrue(service.matchNotes.isEmpty())
    }

    @Test
    fun testNotesSurviveFileStoreRoundTrip(@TempDir dir: Path) {
        val store = FileMatchStore(dir)
        assertTrue(store.loadMatchNotes().isEmpty())

        val notes = mapOf(UUID.randomUUID() to "First note", UUID.randomUUID() to "Second note")
        store.saveMatchNotes(notes)

        assertEquals(notes, FileMatchStore(dir).loadMatchNotes())
    }

    private fun serviceWithActiveMatch(match: MatchState): MatchService {
        val store = InMemoryMatchStore()
        store.active = match
        return MatchService(store)
    }
}
