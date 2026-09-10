package com.wristrally.sync

import com.wristrally.domain.MatchState
import java.util.UUID
import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable
import kotlinx.serialization.json.Json

object SyncPaths {
    const val SNAPSHOT = "/wristrally/snapshot"
    const val DELETED = "/wristrally/deleted"
    const val CAPABILITY = "wristrally_sync"
    const val ENVELOPE_KEY = "envelopeJSON"
}

data class SyncPayload(
    val active: MatchState?,
    val archive: List<MatchState>,
    val deleted: Set<UUID>,
)

@Serializable
internal data class SyncEnvelope(
    @SerialName("activeMatchJSON")
    val active: MatchState? = null,
    @SerialName("archiveJSON")
    val archive: List<MatchState> = emptyList(),
    @SerialName("deletedMatchIDsJSON")
    val deleted: List<String> = emptyList(),
)

object SyncCodec {
    private val json = Json {
        ignoreUnknownKeys = true
        encodeDefaults = true
    }

    fun encode(payload: SyncPayload): ByteArray {
        val envelope = SyncEnvelope(
            active = payload.active,
            archive = payload.archive,
            deleted = payload.deleted.map { it.toString() }.sorted(),
        )
        return json.encodeToString(SyncEnvelope.serializer(), envelope).toByteArray()
    }

    fun decode(bytes: ByteArray): SyncPayload {
        if (bytes.isEmpty()) {
            return SyncPayload(active = null, archive = emptyList(), deleted = emptySet())
        }
        val envelope = json.decodeFromString(SyncEnvelope.serializer(), bytes.decodeToString())
        return SyncPayload(
            active = envelope.active,
            archive = envelope.archive,
            deleted = envelope.deleted.mapNotNull { raw ->
                runCatching { UUID.fromString(raw) }.getOrNull()
            }.toSet(),
        )
    }
}
