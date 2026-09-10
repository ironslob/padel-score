package com.wristrally.phone

import androidx.activity.compose.BackHandler
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.itemsIndexed
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.outlined.Delete
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.TopAppBar
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.unit.dp
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.LifecycleEventObserver
import androidx.lifecycle.compose.LocalLifecycleOwner
import com.wristrally.domain.DurationFormatter
import com.wristrally.domain.MatchEvent
import com.wristrally.domain.MatchEventKind
import com.wristrally.domain.MatchService
import com.wristrally.domain.MatchState
import com.wristrally.domain.MatchStatus
import com.wristrally.domain.Side
import java.time.ZoneId
import java.time.format.DateTimeFormatter
import java.time.format.FormatStyle
import java.util.UUID

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun MatchDetailScreen(
    service: MatchService,
    matchId: UUID,
    canDelete: Boolean,
    onBack: () -> Unit,
) {
    var revision by remember { mutableIntStateOf(0) }
    DisposableEffect(service) {
        val listener: () -> Unit = { revision += 1 }
        service.addListener(listener)
        onDispose { service.removeListener(listener) }
    }
    @Suppress("UNUSED_VARIABLE")
    val tick = revision

    val match = remember(revision, matchId) {
        if (service.activeMatch?.id == matchId) service.activeMatch
        else service.archivedMatches.firstOrNull { it.id == matchId }
    }
    if (match == null) {
        LaunchedBack(onBack)
        return
    }

    var noteDraft by remember(matchId) { mutableStateOf(service.note(matchId)) }
    var historyExpanded by remember { mutableStateOf(false) }
    var confirmingDelete by remember { mutableStateOf(false) }

    fun saveNote() {
        service.setNote(noteDraft, matchId)
    }

    val lifecycleOwner = LocalLifecycleOwner.current
    DisposableEffect(lifecycleOwner, matchId) {
        val observer = LifecycleEventObserver { _, event ->
            if (event == Lifecycle.Event.ON_PAUSE) saveNote()
        }
        lifecycleOwner.lifecycle.addObserver(observer)
        onDispose {
            saveNote()
            lifecycleOwner.lifecycle.removeObserver(observer)
        }
    }

    BackHandler {
        saveNote()
        onBack()
    }

    Scaffold(
        topBar = {
            TopAppBar(
                title = { Text("Match") },
                navigationIcon = {
                    IconButton(onClick = {
                        saveNote()
                        onBack()
                    }) {
                        Icon(Icons.AutoMirrored.Filled.ArrowBack, contentDescription = "Back")
                    }
                },
                actions = {
                    if (canDelete) {
                        IconButton(onClick = { confirmingDelete = true }) {
                            Icon(Icons.Outlined.Delete, contentDescription = "Delete")
                        }
                    }
                },
            )
        },
    ) { padding ->
        LazyColumn(Modifier.padding(padding)) {
            item { SectionTitle("Summary") }
            item { Labeled("Status", match.status.displayName) }
            item { Labeled("Started", formatStarted(match)) }
            match.finishedAt?.let { finished ->
                item {
                    Labeled(
                        "Finished",
                        finished.atZone(ZoneId.systemDefault())
                            .format(DateTimeFormatter.ofLocalizedDateTime(FormatStyle.MEDIUM, FormatStyle.SHORT)),
                    )
                }
            }
            item { Labeled("Duration", DurationFormatter.detailed(match.duration())) }
            item { Labeled("Score", scoreText(match)) }
            match.winner?.let { winner ->
                item {
                    Labeled(
                        "Winner",
                        if (winner == Side.Left) "Us (left)" else "Them (right)",
                    )
                }
            }

            item { SectionTitle("Notes") }
            item {
                OutlinedTextField(
                    value = noteDraft,
                    onValueChange = { noteDraft = it },
                    modifier = Modifier
                        .fillMaxWidth()
                        .padding(horizontal = 16.dp, vertical = 8.dp),
                    label = { Text("Add a note") },
                    minLines = 3,
                    maxLines = 12,
                )
            }

            item { SectionTitle("Sets") }
            if (match.completedSets.isEmpty() && match.status == MatchStatus.InProgress) {
                item {
                    Text(
                        "No completed sets yet.",
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                        modifier = Modifier.padding(horizontal = 16.dp, vertical = 8.dp),
                    )
                }
            }
            itemsIndexed(match.completedSets) { index, set ->
                Text(
                    "Set ${index + 1}: ${set.leftGames}–${set.rightGames}",
                    fontFamily = FontFamily.Monospace,
                    modifier = Modifier.padding(horizontal = 16.dp, vertical = 4.dp),
                )
            }
            if (match.displaysIncompleteSet) {
                val game = match.gameDisplayPair
                val label = if (match.status == MatchStatus.InProgress) {
                    "Current"
                } else {
                    "Set ${match.completedSets.size + 1}"
                }
                item {
                    Text(
                        "$label: ${match.currentSet.leftGames}–${match.currentSet.rightGames} (Game ${game.first}–${game.second})",
                        fontFamily = FontFamily.Monospace,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                        modifier = Modifier.padding(horizontal = 16.dp, vertical = 4.dp),
                    )
                }
            }

            item {
                TextButton(
                    onClick = { historyExpanded = !historyExpanded },
                    modifier = Modifier.padding(horizontal = 8.dp),
                ) {
                    Text("Scoring History  ${historyRows(match).size}")
                }
            }
            if (historyExpanded) {
                itemsIndexed(historyRows(match), key = { _, row -> row.id }) { index, row ->
                    Row(
                        Modifier
                            .fillMaxWidth()
                            .padding(horizontal = 16.dp, vertical = 6.dp),
                        horizontalArrangement = Arrangement.SpaceBetween,
                    ) {
                        Text(row.label)
                        Text(
                            row.time,
                            style = MaterialTheme.typography.bodySmall,
                            color = MaterialTheme.colorScheme.onSurfaceVariant,
                        )
                    }
                    HorizontalDivider()
                }
            }
        }
    }

    if (confirmingDelete) {
        AlertDialog(
            onDismissRequest = { confirmingDelete = false },
            title = { Text("Delete this match?") },
            text = { Text("This can't be undone. The match is removed from your Wear OS watch too.") },
            confirmButton = {
                TextButton(
                    onClick = {
                        service.deleteArchivedMatch(matchId)
                        confirmingDelete = false
                        onBack()
                    },
                ) { Text("Delete") }
            },
            dismissButton = {
                TextButton(onClick = { confirmingDelete = false }) { Text("Cancel") }
            },
        )
    }
}

@Composable
private fun LaunchedBack(onBack: () -> Unit) {
    androidx.compose.runtime.LaunchedEffect(Unit) { onBack() }
}

@Composable
private fun SectionTitle(title: String) {
    Text(
        title,
        style = MaterialTheme.typography.titleSmall,
        color = MaterialTheme.colorScheme.primary,
        modifier = Modifier.padding(start = 16.dp, top = 16.dp, end = 16.dp, bottom = 4.dp),
    )
}

@Composable
private fun Labeled(label: String, value: String) {
    Column(Modifier.padding(horizontal = 16.dp, vertical = 6.dp)) {
        Text(label, style = MaterialTheme.typography.labelMedium, color = MaterialTheme.colorScheme.onSurfaceVariant)
        Text(value, style = MaterialTheme.typography.bodyLarge)
    }
}

private fun scoreText(match: MatchState): String {
    val summary = match.finalScoreSummary
    return if (summary.isEmpty()) "${match.leftSetsWon}–${match.rightSetsWon}" else summary
}

private data class HistoryRow(
    val id: String,
    val timestamp: java.time.Instant,
    val time: String,
    val label: String,
)

private val timeFormatter: DateTimeFormatter =
    DateTimeFormatter.ofLocalizedTime(FormatStyle.MEDIUM)

private fun historyRows(match: MatchState): List<HistoryRow> {
    val rows = match.events.map { event ->
        HistoryRow(
            id = event.id.toString(),
            timestamp = event.timestamp,
            time = timeFormatter.format(event.timestamp.atZone(ZoneId.systemDefault())),
            label = eventLabel(event),
        )
    }.toMutableList()
    match.deuceFormatChanges.forEachIndexed { index, change ->
        if (index == 0) return@forEachIndexed
        rows += HistoryRow(
            id = "deuce-$index-${change.at}",
            timestamp = change.at,
            time = timeFormatter.format(change.at.atZone(ZoneId.systemDefault())),
            label = "Scoring at deuce: ${change.format.label}",
        )
    }
    return rows.sortedBy { it.timestamp }
}

private fun eventLabel(event: MatchEvent): String = when (event.kind) {
    MatchEventKind.MatchStarted -> "Match started"
    MatchEventKind.ServerSelected -> "Server: ${event.side?.displayName ?: "?"}"
    MatchEventKind.PointWon -> "Point: ${event.side?.displayName ?: "?"}"
    MatchEventKind.MatchFinished -> "Match finished"
    MatchEventKind.MatchEndedEarly -> "Ended early"
    MatchEventKind.MatchDiscarded -> "Discarded"
}
