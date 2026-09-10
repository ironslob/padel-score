package com.wristrally.sync

import com.wristrally.domain.MatchService
import com.wristrally.domain.MatchState
import java.util.UUID

/**
 * Bidirectional sync of active match + archive between Wear OS and the phone.
 * Watch is authoritative during live scoring; the phone applies remote snapshots.
 * History deletion runs the other way: the phone owns it, and the watch prunes
 * its own archive to match.
 */
class MatchSyncCoordinator(
    private val service: MatchService,
    private val isWatch: Boolean,
    private val transport: SyncTransport,
) {
    init {
        transport.setListener { path, payload, fromLocalNode ->
            apply(path, payload, fromLocalNode)
        }
        service.onSyncNeeded { active, archive, deleted ->
            push(active, archive, deleted)
        }
        push(service.activeMatch, service.archivedMatches, service.deletedMatchIDs)
    }

    fun apply(path: String, payload: ByteArray, fromLocalNode: Boolean) {
        if (fromLocalNode) return
        val decoded = runCatching { SyncCodec.decode(payload) }.getOrNull() ?: return
        if (isWatch) {
            if (path == SyncPaths.DELETED) {
                service.applyRemoteDeletions(decoded.deleted)
            }
        } else if (path == SyncPaths.SNAPSHOT) {
            service.applyRemoteSnapshot(decoded.active, decoded.archive)
        }
    }

    fun push(active: MatchState?, archive: List<MatchState>, deleted: Set<UUID>) {
        val payload = SyncCodec.encode(SyncPayload(active, archive, deleted))
        val path = if (isWatch) SyncPaths.SNAPSHOT else SyncPaths.DELETED
        transport.publish(path, payload)
        transport.sendMessage(path, payload)
    }
}
