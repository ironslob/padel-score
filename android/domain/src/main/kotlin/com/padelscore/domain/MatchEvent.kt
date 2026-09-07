package com.padelscore.domain

import java.time.Instant
import java.util.UUID
import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable

@Serializable
enum class MatchEventKind {
    @SerialName("matchStarted")
    MatchStarted,

    @SerialName("serverSelected")
    ServerSelected,

    @SerialName("pointWon")
    PointWon,

    @SerialName("matchFinished")
    MatchFinished,

    @SerialName("matchEndedEarly")
    MatchEndedEarly,

    @SerialName("matchDiscarded")
    MatchDiscarded,
}

/** Immutable fact in the match event stream. */
@Serializable
data class MatchEvent(
    @Serializable(with = UuidSerializer::class)
    val id: UUID = UUID.randomUUID(),
    val kind: MatchEventKind,
    val side: Side? = null,
    @Serializable(with = InstantIsoSerializer::class)
    val timestamp: Instant = Instant.now(),
) {
    companion object {
        fun matchStarted(at: Instant = Instant.now()): MatchEvent =
            MatchEvent(kind = MatchEventKind.MatchStarted, timestamp = at)

        fun pointWon(side: Side, at: Instant = Instant.now()): MatchEvent =
            MatchEvent(kind = MatchEventKind.PointWon, side = side, timestamp = at)

        fun serverSelected(side: Side, at: Instant = Instant.now()): MatchEvent =
            MatchEvent(kind = MatchEventKind.ServerSelected, side = side, timestamp = at)

        fun matchFinished(at: Instant = Instant.now()): MatchEvent =
            MatchEvent(kind = MatchEventKind.MatchFinished, timestamp = at)

        fun matchEndedEarly(at: Instant = Instant.now()): MatchEvent =
            MatchEvent(kind = MatchEventKind.MatchEndedEarly, timestamp = at)

        fun matchDiscarded(at: Instant = Instant.now()): MatchEvent =
            MatchEvent(kind = MatchEventKind.MatchDiscarded, timestamp = at)
    }
}
