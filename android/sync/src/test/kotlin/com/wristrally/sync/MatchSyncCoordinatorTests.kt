package com.wristrally.sync

import com.wristrally.domain.InMemoryMatchStore
import com.wristrally.domain.MatchAction
import com.wristrally.domain.MatchService
import com.wristrally.domain.MatchStatus
import com.wristrally.domain.ScoringEngine
import com.wristrally.domain.Side
import java.util.UUID
import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Assertions.assertNull
import org.junit.jupiter.api.Assertions.assertTrue
import org.junit.jupiter.api.Test

class MatchSyncCoordinatorTests {
    @Test
    fun codecRoundTripPreservesSnapshot() {
        val engine = ScoringEngine()
        var match = engine.startMatch()
        match = engine.apply(MatchAction.SelectServer(Side.Left), match)
        match = engine.apply(MatchAction.PointWon(Side.Left), match)
        val deleted = setOf(UUID.randomUUID())
        val encoded = SyncCodec.encode(SyncPayload(match, listOf(match), deleted))
        val decoded = SyncCodec.decode(encoded)
        assertEquals(match.id, decoded.active?.id)
        assertEquals(1, decoded.active?.currentGame?.leftPoints)
        assertEquals(1, decoded.archive.size)
        assertEquals(deleted, decoded.deleted)
    }

    @Test
    fun watchPushesSnapshotPathAndIgnoresOwnSnapshot() {
        val watch = MatchService(InMemoryMatchStore())
        val transport = FakeSyncTransport()
        watch.startMatch()
        MatchSyncCoordinator(watch, isWatch = true, transport = transport)

        assertTrue(transport.published.any { it.first == SyncPaths.SNAPSHOT })
        assertTrue(transport.messages.any { it.first == SyncPaths.SNAPSHOT })

        val inbound = SyncCodec.encode(
            SyncPayload(active = watch.activeMatch, archive = emptyList(), deleted = emptySet()),
        )
        val previousId = watch.activeMatch?.id
        transport.deliver(SyncPaths.SNAPSHOT, inbound, fromLocalNode = true)
        assertEquals(previousId, watch.activeMatch?.id)
    }

    @Test
    fun watchAppliesOnlyRemoteDeletions() {
        val store = InMemoryMatchStore()
        val engine = ScoringEngine()
        var archived = engine.startMatch()
        archived = engine.apply(MatchAction.SelectServer(Side.Left), archived)
        archived = engine.apply(MatchAction.EndEarly, archived)
        store.archive = mutableListOf(archived)
        val watch = MatchService(store)
        val transport = FakeSyncTransport()
        MatchSyncCoordinator(watch, isWatch = true, transport = transport)
        transport.published.clear()
        transport.messages.clear()

        val snapshot = SyncCodec.encode(
            SyncPayload(active = null, archive = emptyList(), deleted = emptySet()),
        )
        transport.deliver(SyncPaths.SNAPSHOT, snapshot)
        assertEquals(1, watch.archivedMatches.size)

        val deleted = SyncCodec.encode(
            SyncPayload(active = null, archive = emptyList(), deleted = setOf(archived.id)),
        )
        transport.deliver(SyncPaths.DELETED, deleted)
        assertTrue(watch.archivedMatches.isEmpty())
        assertTrue(watch.deletedMatchIDs.contains(archived.id))
    }

    @Test
    fun phoneAppliesOnlyRemoteSnapshots() {
        val phone = MatchService(InMemoryMatchStore(), autoRestore = false)
        phone.restore()
        val transport = FakeSyncTransport()
        MatchSyncCoordinator(phone, isWatch = false, transport = transport)

        val engine = ScoringEngine()
        var match = engine.startMatch()
        match = engine.apply(MatchAction.SelectServer(Side.Right), match)
        match = engine.apply(MatchAction.PointWon(Side.Right), match)
        val payload = SyncCodec.encode(
            SyncPayload(active = match, archive = emptyList(), deleted = emptySet()),
        )
        transport.deliver(SyncPaths.DELETED, payload)
        assertNull(phone.activeMatch)

        transport.deliver(SyncPaths.SNAPSHOT, payload)
        assertEquals(match.id, phone.activeMatch?.id)
        assertEquals(1, phone.activeMatch?.currentGame?.rightPoints)
        assertEquals(MatchStatus.InProgress, phone.activeMatch?.status)
    }

    @Test
    fun phoneDeletePushesDeletedPath() {
        val store = InMemoryMatchStore()
        val engine = ScoringEngine()
        var archived = engine.startMatch()
        archived = engine.apply(MatchAction.SelectServer(Side.Left), archived)
        archived = engine.apply(MatchAction.EndEarly, archived)
        store.archive = mutableListOf(archived)
        val phone = MatchService(store)
        val transport = FakeSyncTransport()
        MatchSyncCoordinator(phone, isWatch = false, transport = transport)
        transport.published.clear()

        phone.deleteArchivedMatch(archived.id)
        assertTrue(transport.published.any { it.first == SyncPaths.DELETED })
        val latest = SyncCodec.decode(transport.published.last().second)
        assertTrue(latest.deleted.contains(archived.id))
    }
}
