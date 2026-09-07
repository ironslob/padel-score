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
    /** Best of 3 where the deciding set is a 10-point match tie-break. */
    BestOfThreeMatchTieBreak,
    BestOfFive,
    Continuous,
    ;

    val label: String
        get() = when (this) {
            BestOfOne -> "1 set"
            BestOfThree -> "Best of 3"
            BestOfThreeMatchTieBreak -> "2 sets + TB"
            BestOfFive -> "Best of 5"
            Continuous -> "Continuous"
        }

    fun apply(settings: MatchSettings): MatchSettings = when (this) {
        BestOfOne -> settings.copy(
            setsToWin = 1,
            continuousPlay = false,
            decidingSetIsMatchTieBreak = false,
        )
        BestOfThree -> settings.copy(
            setsToWin = 2,
            continuousPlay = false,
            decidingSetIsMatchTieBreak = false,
        )
        BestOfThreeMatchTieBreak -> settings.copy(
            setsToWin = 2,
            continuousPlay = false,
            decidingSetIsMatchTieBreak = true,
        )
        BestOfFive -> settings.copy(
            setsToWin = 3,
            continuousPlay = false,
            decidingSetIsMatchTieBreak = false,
        )
        Continuous -> settings.copy(
            continuousPlay = true,
            decidingSetIsMatchTieBreak = false,
        )
    }

    val rawValue: String
        get() = when (this) {
            BestOfOne -> "bestOfOne"
            BestOfThree -> "bestOfThree"
            BestOfThreeMatchTieBreak -> "bestOfThreeMatchTieBreak"
            BestOfFive -> "bestOfFive"
            Continuous -> "continuous"
        }

    companion object {
        fun fromRaw(raw: String?): MatchSetFormat = entries.firstOrNull { it.rawValue == raw } ?: BestOfThree
    }
}

/** How a game is resolved once both sides reach 40.
 *
 * Declaration order is the picker/cycler order: most advantages to fewest
 * (Regular → Star → Silver → Golden).
 */
@Serializable
enum class DeuceFormat {
    /** Traditional scoring: advantage repeats until one side wins by two points. */
    @SerialName("advantage")
    Advantage,

    /** Two advantage cycles are played. If the second is broken, the next point decides. */
    @SerialName("starPoint")
    StarPoint,

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
            StarPoint -> "Star point"
            SilverPoint -> "Silver point"
            GoldenPoint -> "Golden point"
        }

    val decidingPointLabel: String
        get() = when (this) {
            Advantage -> "Deuce"
            StarPoint -> "Star Point"
            SilverPoint -> "Silver Point"
            GoldenPoint -> "Golden Point"
        }

    val decidingPointShortLabel: String
        get() = when (this) {
            Advantage -> "40"
            StarPoint -> "ST"
            SilverPoint -> "SP"
            GoldenPoint -> "GP"
        }

    /** How many converted-or-broken advantage cycles are allowed before the
     * next point becomes decisive. `null` means unlimited (regular scoring). */
    val advantagesBeforeDecidingPoint: Int?
        get() = when (this) {
            Advantage -> null
            StarPoint -> 2
            SilverPoint -> 1
            GoldenPoint -> 0
        }

    fun decidesGame(afterBrokenAdvantages: Int): Boolean {
        val cap = advantagesBeforeDecidingPoint ?: return false
        return afterBrokenAdvantages >= cap
    }

    val numbersDeuceCycles: Boolean
        get() = (advantagesBeforeDecidingPoint ?: 0) > 1
}

/** V1 defaults from product.md. `deuceFormat` is a persisted preference on Watch. */
@Serializable(with = MatchSettingsSerializer::class)
data class MatchSettings(
    val setsToWin: Int = 2,
    val continuousPlay: Boolean = false,
    val gamesToWinSet: Int = 6,
    val mustWinByTwoGames: Boolean = true,
    val decidingSetIsMatchTieBreak: Boolean = false,
    val deuceFormat: DeuceFormat = DeuceFormat.StarPoint,
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
            decidingSetIsMatchTieBreak -> MatchSetFormat.BestOfThreeMatchTieBreak
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
                put("decidingSetIsMatchTieBreak", value.decidingSetIsMatchTieBreak)
                put("deuceFormat", when (value.deuceFormat) {
                        DeuceFormat.Advantage -> "advantage"
                        DeuceFormat.StarPoint -> "starPoint"
                        DeuceFormat.SilverPoint -> "silverPoint"
                        DeuceFormat.GoldenPoint -> "goldenPoint"
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
            "starPoint" -> DeuceFormat.StarPoint
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
            decidingSetIsMatchTieBreak = bool("decidingSetIsMatchTieBreak", false),
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
