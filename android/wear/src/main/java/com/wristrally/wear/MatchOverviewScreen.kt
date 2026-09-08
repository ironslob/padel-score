package com.wristrally.wear

import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableLongStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.wear.compose.foundation.lazy.ScalingLazyColumn
import androidx.wear.compose.material3.MaterialTheme
import androidx.wear.compose.material3.Text
import com.wristrally.domain.DurationFormatter
import com.wristrally.domain.MatchState
import java.time.Instant
import kotlinx.coroutines.delay

@Composable
fun MatchOverviewScreen(match: MatchState) {
    var now by remember { mutableLongStateOf(System.currentTimeMillis()) }
    LaunchedEffect(Unit) {
        while (true) {
            now = System.currentTimeMillis()
            delay(30_000)
        }
    }
    val elapsed = DurationFormatter.elapsed(
        java.time.Duration.between(match.startedAt, Instant.ofEpochMilli(now)).seconds.toDouble(),
    )
    ScalingLazyColumn(modifier = Modifier.fillMaxSize()) {
        item { Labeled("Scoring", match.settings.deuceFormat.label) }
        if (match.isMatchTieBreak) {
            item {
                Labeled("Super TB", "${match.currentGame.leftPoints} – ${match.currentGame.rightPoints}")
            }
        } else {
            item { Labeled("Current Set", "${match.currentSet.leftGames} – ${match.currentSet.rightGames}") }
        }
        item { Labeled("Current Match", "${match.leftSetsWon} – ${match.rightSetsWon}") }
        item { Labeled("Elapsed", elapsed) }
        if (match.currentGame.isGoldenPointActive) {
            item {
                Text(match.settings.deuceFormat.decidingPointLabel, fontWeight = FontWeight.Bold, color = androidx.compose.ui.graphics.Color(0xFFFFD60A))
            }
            item { Text("Next point wins", style = MaterialTheme.typography.bodySmall) }
        }
        if (match.completedSets.isNotEmpty()) {
            item { Text("Sets", style = MaterialTheme.typography.labelSmall, color = MaterialTheme.colorScheme.onSurfaceVariant) }
            match.completedSets.forEachIndexed { index, set ->
                item { Text("Set ${index + 1}: ${set.leftGames}–${set.rightGames}", style = MaterialTheme.typography.bodySmall) }
            }
        }
    }
}

@Composable
private fun Labeled(title: String, value: String) {
    androidx.compose.foundation.layout.Column(Modifier.fillMaxWidth().padding(vertical = 2.dp)) {
        Text(title, style = MaterialTheme.typography.labelSmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
        Text(value, style = MaterialTheme.typography.titleSmall, fontWeight = FontWeight.SemiBold)
    }
}
