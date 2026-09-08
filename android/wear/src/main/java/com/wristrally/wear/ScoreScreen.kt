package com.wristrally.wear

import androidx.compose.foundation.border
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.hapticfeedback.HapticFeedbackType
import androidx.compose.ui.platform.LocalHapticFeedback
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.wear.compose.material3.MaterialTheme
import androidx.wear.compose.material3.Text
import com.wristrally.domain.MatchService
import com.wristrally.domain.MatchSettings
import com.wristrally.domain.MatchState
import com.wristrally.domain.MatchStatus
import com.wristrally.domain.Side
import com.wristrally.domain.TieBreakNotice
import kotlinx.coroutines.delay

@Composable
fun ScoreScreen(service: MatchService, match: MatchState) {
    val haptic = LocalHapticFeedback.current
    var undoSide by remember { mutableStateOf<Side?>(null) }
    val games = match.scoreScreenSetDisplay
    val game = match.scoreScreenGameDisplay
    val roles = match.servingRoleLabels
    val sides = match.scoreScreenSides

    LaunchedEffect(match.events.size) {
        haptic.performHapticFeedback(HapticFeedbackType.LongPress)
    }
    LaunchedEffect(match.activeTieBreakNotice) {
        if (match.activeTieBreakNotice != null) {
            haptic.performHapticFeedback(HapticFeedbackType.TextHandleMove)
        }
    }
    LaunchedEffect(undoSide) {
        if (undoSide != null) {
            delay((MatchSettings.QUICK_UNDO_TIMEOUT_SECONDS * 1000).toLong())
            undoSide = null
        }
    }

    Column(
        modifier = Modifier.fillMaxSize().padding(horizontal = 6.dp, vertical = 8.dp),
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.spacedBy(6.dp),
    ) {
        when {
            match.currentGame.isTieBreak -> TieBreakHeader(match, games)
            match.currentGame.isGoldenPointActive -> DecidingPointHeader(match)
            else -> GamesHeader(match, games)
        }
        Row(
            modifier = Modifier.fillMaxWidth().weight(1f),
            horizontalArrangement = Arrangement.spacedBy(8.dp),
        ) {
            ScoreButton(
                logicalSide = sides.first,
                score = game.first,
                role = roles.first,
                tint = if (sides.first == Side.Left) UsBlue else ThemRed,
                serving = match.currentServer == sides.first,
                undoing = undoSide == sides.first,
                modifier = Modifier.weight(1f).fillMaxHeight(),
                onTap = { handleTap(service, sides.first, undoSide) { undoSide = it } },
            )
            ScoreButton(
                logicalSide = sides.second,
                score = game.second,
                role = roles.second,
                tint = if (sides.second == Side.Left) UsBlue else ThemRed,
                serving = match.currentServer == sides.second,
                undoing = undoSide == sides.second,
                modifier = Modifier.weight(1f).fillMaxHeight(),
                onTap = { handleTap(service, sides.second, undoSide) { undoSide = it } },
            )
        }
    }
}

private fun handleTap(
    service: MatchService,
    logicalSide: Side,
    undoSide: Side?,
    setUndo: (Side?) -> Unit,
) {
    if (undoSide == logicalSide) {
        service.undoLastPoint()
        setUndo(null)
        return
    }
    val previous = service.activeMatch
    service.awardPoint(logicalSide)
    val updated = service.activeMatch
    if (!didPointEndGame(previous, updated)) {
        setUndo(logicalSide)
    } else {
        setUndo(null)
    }
}

private fun didPointEndGame(previous: MatchState?, updated: MatchState?): Boolean {
    if (previous == null || updated == null) return false
    if (previous.status != MatchStatus.InProgress || updated.status != MatchStatus.InProgress) return false
    val previousGames = previous.currentSet.leftGames + previous.currentSet.rightGames
    val updatedGames = updated.currentSet.leftGames + updated.currentSet.rightGames
    if (updatedGames > previousGames) return true
    return updated.completedSets.size > previous.completedSets.size
}

@Composable
private fun TieBreakHeader(match: MatchState, games: Pair<String, String>) {
    val isMatchTB = match.isMatchTieBreak
    Column(horizontalAlignment = Alignment.CenterHorizontally) {
        Text(
            if (isMatchTB) "Super TB" else "Tie-break",
            color = UndoOrange,
            fontWeight = FontWeight.Bold,
            style = MaterialTheme.typography.labelSmall,
        )
        if (!isMatchTB) {
            Text(
                "${games.first} – ${games.second}",
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )
        }
        val notice = match.activeTieBreakNotice
        Text(
            when (notice) {
                TieBreakNotice.ChangeServe -> "Change serve"
                TieBreakNotice.ChangeSides -> "Change sides"
                null -> if (isMatchTB) "First to 10" else "First to 7"
            },
            style = MaterialTheme.typography.labelSmall,
            color = if (notice != null) UndoOrange else MaterialTheme.colorScheme.onSurfaceVariant,
        )
    }
}

@Composable
private fun GamesHeader(match: MatchState, games: Pair<String, String>) {
    val status = if (match.settings.deuceFormat.numbersDeuceCycles) match.gameStatusLine else null
    Column(horizontalAlignment = Alignment.CenterHorizontally) {
        Text(
            "${games.first} – ${games.second}",
            style = MaterialTheme.typography.titleMedium,
            fontWeight = FontWeight.SemiBold,
        )
        if (status != null) {
            Text(
                status,
                style = MaterialTheme.typography.labelSmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )
        }
    }
}

@Composable
private fun DecidingPointHeader(match: MatchState) {
    Column(horizontalAlignment = Alignment.CenterHorizontally) {
        Text(match.settings.deuceFormat.decidingPointLabel, color = Color(0xFFFFD60A), fontWeight = FontWeight.Bold)
        Text("Next point wins", style = MaterialTheme.typography.labelSmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
    }
}

@Composable
private fun ScoreButton(
    logicalSide: Side,
    score: String,
    role: String,
    tint: Color,
    serving: Boolean,
    undoing: Boolean,
    modifier: Modifier,
    onTap: () -> Unit,
) {
    androidx.wear.compose.material3.Button(
        onClick = onTap,
        modifier = modifier.semantics {
            contentDescription = if (serving) "$role $score, serving" else "$role $score"
        },
        colors = androidx.wear.compose.material3.ButtonDefaults.buttonColors(
            containerColor = tint.copy(alpha = if (undoing) 0.45f else 0.28f),
        ),
        shape = WatchButtonShape,
    ) {
        Box(Modifier.fillMaxSize(), contentAlignment = Alignment.Center) {
            Column(horizontalAlignment = Alignment.CenterHorizontally) {
                Text(score, style = MaterialTheme.typography.displaySmall, fontWeight = FontWeight.Bold, textAlign = TextAlign.Center)
                Text(role, style = MaterialTheme.typography.labelSmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
            }
            if (serving) {
                Box(
                    Modifier
                        .align(Alignment.TopCenter)
                        .padding(top = 4.dp)
                        .size(8.dp)
                        .clip(CircleShape)
                        .border(0.dp, Color.Transparent, CircleShape)
                        .then(Modifier),
                ) {
                    Box(Modifier.fillMaxSize().clip(CircleShape).then(Modifier), contentAlignment = Alignment.Center) {
                        androidx.compose.foundation.Canvas(Modifier.size(8.dp)) {
                            drawCircle(Color(0xFFFFD60A))
                        }
                    }
                }
            }
        }
    }
}
