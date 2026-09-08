package com.wristrally.domain

import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable

/** Logical team side: left = Us, right = Them. Visual layout may remap when swap-sides is on. */
@Serializable
enum class Side {
    @SerialName("left")
    Left,

    @SerialName("right")
    Right,
    ;

    val opposite: Side
        get() = if (this == Left) Right else Left

    val displayName: String
        get() = if (this == Left) "Us" else "Them"
}
