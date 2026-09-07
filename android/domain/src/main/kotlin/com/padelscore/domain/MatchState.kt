package com.padelscore.domain

import java.time.Duration
import java.time.Instant
import java.util.UUID
import kotlinx.serialization.EncodeDefault
import kotlinx.serialization.ExperimentalSerializationApi
import kotlinx.serialization.Serializable

/** Transient notice shown during a tie-break after certain points. */
enum class TieBreakNotice {
    ChangeServe,
    ChangeSides,
}

/** Mutable projection of the current game (derived from events). */
@Serializable
data class GameScore(
    var leftPoints: Int = 0,
    var rightPoints: Int = 0,
    var advantageSide: Side? = null,
    /** True while a single decisive rally is in progress under any capped deuce
     * format. Historical name kept for archive compatibility. */
    var isGoldenPointActive: Boolean = false,
    /** How many times advantage has been broken in this game. Reconstructed by
     * replay; used by capped formats to know when the next rally decides. */
    var brokenAdvantageCount: Int = 0,
    var isTieBreak: Boolean = false,
    var isComplete: Boolean = false,
    var winner: Side? = null,
) {
    fun points(side: Side): Int = if (side == Side.Left) leftPoints else rightPoints

    fun setPoints(value: Int, side: Side) {
        if (side == Side.Left) leftPoints = value else rightPoints = value
    }

    val tieBreakTotalPoints: Int get() = leftPoints + rightPoints

    val tieBreakNotice: TieBreakNotice?
        get() {
            if (!isTieBreak) return null
            val total = tieBreakTotalPoints
            if (total <= 0) return null
            if (total % 6 == 0) return TieBreakNotice.ChangeSides
            if (total % 2 == 1) return TieBreakNotice.ChangeServe
            return null
        }

    fun displayPair(deuceFormat: DeuceFormat): Pair<String, String> {
        if (isComplete) return "0" to "0"
        if (isTieBreak) return leftPoints.toString() to rightPoints.toString()
        if (isGoldenPointActive) {
            val label = deuceFormat.decidingPointShortLabel
            return label to label
        }
        advantageSide?.let { adv ->
            return if (adv == Side.Left) "Ad" to "40" else "40" to "Ad"
        }
        if (leftPoints >= 3 && rightPoints >= 3) return "40" to "40"
        return labelFor(leftPoints) to labelFor(rightPoints)
    }

    fun statusLine(deuceFormat: DeuceFormat): String? = when {
        isTieBreak -> "Tie-break"
        isGoldenPointActive -> deuceFormat.decidingPointLabel
        advantageSide != null -> if (deuceFormat.numbersDeuceCycles) {
            "Advantage ${brokenAdvantageCount + 1}"
        } else {
            "Advantage"
        }
        leftPoints >= 3 && rightPoints >= 3 -> if (deuceFormat.numbersDeuceCycles) {
            "Deuce ${brokenAdvantageCount + 1}"
        } else {
            "Deuce"
        }
        else -> null
    }

    companion object {
        val ZERO = GameScore()

        private fun labelFor(points: Int): String = when (points) {
            0 -> "0"
            1 -> "15"
            2 -> "30"
            else -> "40"
        }
    }
}

@Serializable
data class SetScore(
    var leftGames: Int = 0,
    var rightGames: Int = 0,
    var isComplete: Boolean = false,
    var winner: Side? = null,
) {
    fun games(side: Side): Int = if (side == Side.Left) leftGames else rightGames

    fun setGames(value: Int, side: Side) {
        if (side == Side.Left) leftGames = value else rightGames = value
    }

    val displayPair: Pair<String, String>
        get() = leftGames.toString() to rightGames.toString()

    companion object {
        val ZERO = SetScore()
    }
}

@Serializable
data class DeuceFormatChange(
    val format: DeuceFormat,
    @Serializable(with = InstantIsoSerializer::class)
    val at: Instant,
)

/** Full match record + derived score projection. */
@OptIn(ExperimentalSerializationApi::class)
@Serializable
data class MatchState(
    @Serializable(with = UuidSerializer::class)
    var id: UUID = UUID.randomUUID(),
    var settings: MatchSettings = MatchSettings(),
    var status: MatchStatus = MatchStatus.InProgress,
    var events: List<MatchEvent> = emptyList(),
    @EncodeDefault(EncodeDefault.Mode.NEVER)
    var deuceFormatChanges: List<DeuceFormatChange> = emptyList(),
    @Serializable(with = InstantIsoSerializer::class)
    var startedAt: Instant = Instant.now(),
    @Serializable(with = InstantIsoSerializer::class)
    var finishedAt: Instant? = null,
    var currentGame: GameScore = GameScore(),
    var currentSet: SetScore = SetScore(),
    var completedSets: List<SetScore> = emptyList(),
    var leftSetsWon: Int = 0,
    var rightSetsWon: Int = 0,
    var winner: Side? = null,
    var currentServer: Side? = null,
    var needsServerSelection: Boolean = true,
    var needsWarmUp: Boolean = false,
) {
    fun deepCopy(): MatchState = copy(
        settings = settings.copy(),
        events = events.toList(),
        deuceFormatChanges = deuceFormatChanges.toList(),
        currentGame = currentGame.copy(),
        currentSet = currentSet.copy(),
        completedSets = completedSets.map { it.copy() },
    )

    val hasScoredPoints: Boolean
        get() = events.any { it.kind == MatchEventKind.PointWon }

    val isAtSetStart: Boolean
        get() = currentSet.leftGames == 0 && currentSet.rightGames == 0 && currentGame == GameScore()

    val canChooseNewServer: Boolean
        get() = status == MatchStatus.InProgress &&
            !needsServerSelection &&
            isAtSetStart &&
            completedSets.isNotEmpty()

    val isWaitingForFirstServe: Boolean
        get() = status == MatchStatus.InProgress &&
            needsServerSelection &&
            isAtSetStart &&
            completedSets.isEmpty() &&
            !hasScoredPoints

    fun warmUpElapsed(at: Instant = Instant.now()): Double =
        maxOf(0.0, secondsBetween(startedAt, at))

    fun warmUpRemaining(at: Instant = Instant.now()): Double? {
        if (!needsWarmUp || !settings.hasWarmUpLimit) return null
        val end = startedAt.plusMillis((settings.warmUpDuration * 1000).toLong())
        return maxOf(0.0, secondsBetween(at, end))
    }

    fun isWarmUpExpired(at: Instant = Instant.now()): Boolean {
        val remaining = warmUpRemaining(at) ?: return false
        return remaining <= 0.0
    }

    val lastScoringActivityAt: Instant
        get() = events.lastOrNull { it.kind == MatchEventKind.PointWon }?.timestamp ?: startedAt

    fun isInactive(at: Instant = Instant.now()): Boolean {
        if (status != MatchStatus.InProgress) return false
        return secondsBetween(lastScoringActivityAt, at) >= MatchSettings.INACTIVITY_TIMEOUT_SECONDS
    }

    val matchSetsDisplay: Pair<String, String>
        get() = leftSetsWon.toString() to rightSetsWon.toString()

    val scoreScreenSides: Pair<Side, Side>
        get() {
            if (settings.fixedServerPositions) return Side.Left to Side.Right
            return when (currentServer) {
                Side.Right -> Side.Right to Side.Left
                Side.Left, null -> Side.Left to Side.Right
            }
        }

    val gameDisplayPair: Pair<String, String>
        get() = currentGame.displayPair(settings.deuceFormat)

    val gameStatusLine: String?
        get() = currentGame.statusLine(settings.deuceFormat)

    val scoreScreenGameDisplay: Pair<String, String>
        get() = remapForScoreScreen(gameDisplayPair)

    val scoreScreenSetDisplay: Pair<String, String>
        get() = remapForScoreScreen(currentSet.displayPair)

    val servingRoleLabels: Pair<String, String>
        get() {
            if (settings.usThemLabels) {
                val sides = scoreScreenSides
                return sides.first.displayName to sides.second.displayName
            }
            val server = currentServer ?: return "" to ""
            val sides = scoreScreenSides
            return (if (sides.first == server) "Serving" else "Receiving") to
                (if (sides.second == server) "Serving" else "Receiving")
        }

    fun logicalSide(visual: Side): Side {
        val sides = scoreScreenSides
        return if (visual == Side.Left) sides.first else sides.second
    }

    fun visualSide(logical: Side): Side {
        val sides = scoreScreenSides
        return if (sides.first == logical) Side.Left else Side.Right
    }

    private fun remapForScoreScreen(pair: Pair<String, String>): Pair<String, String> {
        if (settings.fixedServerPositions) return pair
        return when (currentServer) {
            Side.Right -> pair.second to pair.first
            Side.Left, null -> pair
        }
    }

    val activeTieBreakNotice: TieBreakNotice?
        get() = currentGame.tieBreakNotice

    val setScoreLines: List<String>
        get() {
            val lines = completedSets.map { "${it.leftGames}-${it.rightGames}" }.toMutableList()
            if (status == MatchStatus.InProgress ||
                status == MatchStatus.EndedEarly ||
                status == MatchStatus.Completed
            ) {
                if (!currentSet.isComplete) {
                    lines.add("${currentSet.leftGames}-${currentSet.rightGames}")
                }
            }
            return lines
        }

    val finalScoreSummary: String
        get() {
            val lines = completedSets.map { "${it.leftGames}-${it.rightGames}" }.toMutableList()
            partialSetLineForIncompleteTerminal?.let { lines.add(it) }
            return lines.joinToString(", ")
        }

    val displaysIncompleteSet: Boolean
        get() {
            if (currentSet.isComplete) return false
            return when (status) {
                MatchStatus.InProgress -> true
                MatchStatus.Completed, MatchStatus.EndedEarly ->
                    currentSet.leftGames > 0 || currentSet.rightGames > 0 || hasInProgressGameScore
                else -> false
            }
        }

    private val partialSetLineForIncompleteTerminal: String?
        get() {
            if (status != MatchStatus.EndedEarly && status != MatchStatus.Completed) return null
            if (currentSet.isComplete) return null
            if (currentSet.leftGames == 0 && currentSet.rightGames == 0 && !hasInProgressGameScore) {
                return null
            }
            var line = "${currentSet.leftGames}-${currentSet.rightGames}"
            inProgressGameScoreLabel?.let { line += " ($it)" }
            return line
        }

    private val hasInProgressGameScore: Boolean
        get() = currentGame.leftPoints > 0 ||
            currentGame.rightPoints > 0 ||
            currentGame.advantageSide != null ||
            currentGame.isGoldenPointActive ||
            currentGame.isTieBreak

    private val inProgressGameScoreLabel: String?
        get() {
            if (!hasInProgressGameScore) return null
            val pair = gameDisplayPair
            return "${pair.first}-${pair.second}"
        }

    companion object {
        private fun secondsBetween(from: Instant, to: Instant): Double =
            Duration.between(from, to).toNanos() / 1_000_000_000.0
    }
}
