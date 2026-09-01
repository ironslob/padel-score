package com.padelscore.domain

import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable

@Serializable
enum class MatchStatus {
    @SerialName("inProgress")
    InProgress,

    @SerialName("completed")
    Completed,

    @SerialName("endedEarly")
    EndedEarly,

    @SerialName("discarded")
    Discarded,
    ;

    val isTerminal: Boolean
        get() = this != InProgress

    val displayName: String
        get() = when (this) {
            InProgress -> "In Progress"
            Completed -> "Completed"
            EndedEarly -> "Ended Early"
            Discarded -> "Discarded"
        }
}
