package com.padelscore.domain

import kotlinx.serialization.KSerializer
import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable
import kotlinx.serialization.descriptors.SerialDescriptor
import kotlinx.serialization.encoding.Decoder
import kotlinx.serialization.encoding.Encoder
import kotlinx.serialization.json.JsonDecoder
import kotlinx.serialization.json.JsonEncoder
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.boolean
import kotlinx.serialization.json.booleanOrNull
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.int
import kotlinx.serialization.json.intOrNull
import kotlinx.serialization.json.jsonPrimitive
import kotlinx.serialization.json.put

enum class MatchSetFormat {
    BestOfOne,
    BestOfThree,
    BestOfFive,
    Continuous,
    ;

    val label: String
        get() = when (this) {
            BestOfOne -> "1 set"
            BestOfThree -> "Best of 3"
            BestOfFive -> "Best of 5"
            Continuous -> "Continuous"
        }

    fun apply(settings: MatchSettings): MatchSettings = when (this) {
        BestOfOne -> settings.copy(setsToWin = 1, continuousPlay = false)
        BestOfThree -> settings.copy(setsToWin = 2, continuousPlay = false)
        BestOfFive -> settings.copy(setsToWin = 3, continuousPlay = false)
        Continuous -> settings.copy(continuousPlay = true)
    }

    val rawValue: String
        get() = when (this) {
            BestOfOne -> "bestOfOne"
            BestOfThree -> "bestOfThree"
            BestOfFive -> "bestOfFive"
            Continuous -> "continuous"
        }

    companion object {
        fun fromRaw(raw: String?): MatchSetFormat = entries.firstOrNull { it.rawValue == raw } ?: BestOfThree
    }
}

/** How a game is resolved once both sides reach 40. */
@Serializable
enum class DeuceFormat {
    /** Traditional scoring: advantage repeats until one side wins by two points. */
    @SerialName("advantage")
    Advantage,

    /** One advantage is played. If it is broken, the next point decides the game. */
    @SerialName("silverPoint")
    SilverPoint,

    /** No advantage at all — the first point at 40-40 decides the game. */
    @SerialName("goldenPoint")
    GoldenPoint,
    ;

    val label: String
        get() = when (this) {
            Advantage -> "Regular"
            SilverPoint -> "Silver point"
            GoldenPoint -> "Golden point"
        }

    val decidingPointLabel: String
        get() = when (this) {
            Advantage -> "Deuce"
            SilverPoint -> "Silver Point"
            GoldenPoint -> "Golden Point"
        }

    val decidingPointShortLabel: String
        get() = when (this) {
            Advantage -> "40"
            SilverPoint -> "SP"
            GoldenPoint -> "GP"
        }
}

/** V1 defaults from product.md. `deuceFormat` is a persisted preference on Watch. */
@Serializable(with = MatchSettingsSerializer::class)
data class MatchSettings(
    val setsToWin: Int = 2,
    val continuousPlay: Boolean = false,
    val gamesToWinSet: Int = 6,
    val mustWinByTwoGames: Boolean = true,
    val deuceFormat: DeuceFormat = DeuceFormat.GoldenPoint,
    val askServeAtSetStart: Boolean = false,
    val fixedServerPositions: Boolean = true,
    val usThemLabels: Boolean = true,
    val warmUpEnabled: Boolean = true,
    val warmUpMinutes: Int = DEFAULT_WARM_UP_MINUTES,
) {
    val matchSetFormat: MatchSetFormat
        get() = when {
            continuousPlay -> MatchSetFormat.Continuous
            setsToWin == 1 -> MatchSetFormat.BestOfOne
            setsToWin == 3 -> MatchSetFormat.BestOfFive
            else -> MatchSetFormat.BestOfThree
        }

    val shouldWarmUp: Boolean get() = warmUpEnabled
    val hasWarmUpLimit: Boolean get() = warmUpMinutes > 0
    val warmUpDuration: Double get() = clampedWarmUpMinutes(warmUpMinutes) * 60.0

    companion object {
        const val QUICK_UNDO_TIMEOUT_SECONDS = 3.0
        const val INACTIVITY_TIMEOUT_SECONDS = 30 * 60.0
        const val MIN_WARM_UP_MINUTES = 0
        const val MAX_WARM_UP_MINUTES = 30
        const val DEFAULT_WARM_UP_MINUTES = 0
        val WARM_UP_MINUTE_PRESETS = listOf(0, 3, 5, 10)

        fun clampedWarmUpMinutes(value: Int): Int =
            value.coerceIn(MIN_WARM_UP_MINUTES, MAX_WARM_UP_MINUTES)

        fun warmUpMinutesLabel(minutes: Int): String {
            val clamped = clampedWarmUpMinutes(minutes)
            return if (clamped == 0) "No limit" else "$clamped min"
        }

        fun nextWarmUpMinutes(after: Int): Int {
            val index = WARM_UP_MINUTE_PRESETS.indexOf(after)
            if (index >= 0) {
                return WARM_UP_MINUTE_PRESETS[(index + 1) % WARM_UP_MINUTE_PRESETS.size]
            }
            return WARM_UP_MINUTE_PRESETS.firstOrNull { it > after } ?: WARM_UP_MINUTE_PRESETS[0]
        }
    }
}

object MatchSettingsSerializer : KSerializer<MatchSettings> {
    override val descriptor: SerialDescriptor = JsonObject.serializer().descriptor

    override fun serialize(encoder: Encoder, value: MatchSettings) {
        val json = encoder as JsonEncoder
        json.encodeJsonElement(
            buildJsonObject {
                put("setsToWin", value.setsToWin)
                put("continuousPlay", value.continuousPlay)
                put("gamesToWinSet", value.gamesToWinSet)
                put("mustWinByTwoGames", value.mustWinByTwoGames)
                put("deuceFormat", value.deuceFormat.name.replaceFirstChar { it.lowercase() }.let {
                    when (value.deuceFormat) {
                        DeuceFormat.Advantage -> "advantage"
                        DeuceFormat.SilverPoint -> "silverPoint"
                        DeuceFormat.GoldenPoint -> "goldenPoint"
                    }
                })
                put("goldenPointEnabled", value.deuceFormat != DeuceFormat.Advantage)
                put("askServeAtSetStart", value.askServeAtSetStart)
                put("fixedServerPositions", value.fixedServerPositions)
                put("usThemLabels", value.usThemLabels)
                put("warmUpEnabled", value.warmUpEnabled)
                put("warmUpMinutes", value.warmUpMinutes)
            },
        )
    }

    override fun deserialize(decoder: Decoder): MatchSettings {
        val json = decoder as JsonDecoder
        val obj = json.decodeJsonElement() as JsonObject
        fun bool(key: String, default: Boolean): Boolean =
            obj[key]?.jsonPrimitive?.booleanOrNull ?: default
        fun int(key: String, default: Int): Int =
            obj[key]?.jsonPrimitive?.intOrNull ?: default
        fun string(key: String): String? = obj[key]?.jsonPrimitive?.content

        val deuceFormat = when (string("deuceFormat")) {
            "advantage" -> DeuceFormat.Advantage
            "silverPoint" -> DeuceFormat.SilverPoint
            "goldenPoint" -> DeuceFormat.GoldenPoint
            else -> {
                val legacyGoldenPoint = bool("goldenPointEnabled", true)
                if (legacyGoldenPoint) DeuceFormat.SilverPoint else DeuceFormat.Advantage
            }
        }
        return MatchSettings(
            setsToWin = int("setsToWin", 2),
            continuousPlay = bool("continuousPlay", false),
            gamesToWinSet = int("gamesToWinSet", 6),
            mustWinByTwoGames = obj["mustWinByTwoGames"]?.jsonPrimitive?.boolean ?: true,
            deuceFormat = deuceFormat,
            askServeAtSetStart = bool("askServeAtSetStart", false),
            fixedServerPositions = bool("fixedServerPositions", true),
            usThemLabels = bool("usThemLabels", true),
            warmUpEnabled = bool("warmUpEnabled", false),
            warmUpMinutes = MatchSettings.clampedWarmUpMinutes(
                int("warmUpMinutes", MatchSettings.DEFAULT_WARM_UP_MINUTES),
            ),
        )
    }
}
