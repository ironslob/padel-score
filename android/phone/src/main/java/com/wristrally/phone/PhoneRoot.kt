package com.wristrally.phone

import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.outlined.Notes
import androidx.compose.material.icons.outlined.Watch
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.ListItem
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.TopAppBar
import androidx.compose.material3.pulltorefresh.PullToRefreshBox
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.navigation.NavType
import androidx.navigation.compose.NavHost
import androidx.navigation.compose.composable
import androidx.navigation.compose.rememberNavController
import androidx.navigation.navArgument
import com.wristrally.domain.DurationFormatter
import com.wristrally.domain.MatchService
import com.wristrally.domain.MatchState
import com.wristrally.domain.MatchStatus
import java.time.ZoneId
import java.time.format.DateTimeFormatter
import java.time.format.FormatStyle
import java.util.UUID

@Composable
fun PhoneRoot(service: MatchService, initialMatchId: UUID? = null) {
    val navController = rememberNavController()
    LaunchedEffect(initialMatchId) {
        val id = initialMatchId ?: return@LaunchedEffect
        val deletable = service.activeMatch?.id != id
        navController.navigate("match/$id?deletable=$deletable")
    }
    NavHost(navController = navController, startDestination = "list") {
        composable("list") {
            MatchListScreen(
                service = service,
                onOpen = { match, deletable ->
                    navController.navigate("match/${match.id}?deletable=$deletable")
                },
            )
        }
        composable(
            route = "match/{id}?deletable={deletable}",
            arguments = listOf(
                navArgument("id") { type = NavType.StringType },
                navArgument("deletable") {
                    type = NavType.BoolType
                    defaultValue = false
                },
            ),
        ) { entry ->
            val id = UUID.fromString(entry.arguments?.getString("id"))
            val deletable = entry.arguments?.getBoolean("deletable") == true
            MatchDetailScreen(
                service = service,
                matchId = id,
                canDelete = deletable,
                onBack = { navController.popBackStack() },
            )
        }
    }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun MatchListScreen(
    service: MatchService,
    onOpen: (MatchState, Boolean) -> Unit,
) {
    var revision by remember { mutableIntStateOf(0) }
    DisposableEffect(service) {
        val listener: () -> Unit = { revision += 1 }
        service.addListener(listener)
        onDispose { service.removeListener(listener) }
    }
    @Suppress("UNUSED_VARIABLE")
    val tick = revision

    val active = service.activeMatch
    val history = service.archivedMatches.filter { it.id != active?.id }
    val showEmpty = service.isRestored && active == null && service.archivedMatches.isEmpty()
    var pendingDeletion by remember { mutableStateOf<List<MatchState>>(emptyList()) }
    var refreshing by remember { mutableStateOf(false) }

    Scaffold(
        topBar = { TopAppBar(title = { Text("Wrist Rally") }) },
    ) { padding ->
        Box(Modifier.fillMaxSize().padding(padding)) {
            if (!service.isRestored) {
                CircularProgressIndicator(Modifier.align(Alignment.Center))
            } else {
                PullToRefreshBox(
                    isRefreshing = refreshing,
                    onRefresh = {
                        refreshing = true
                        service.restore()
                        refreshing = false
                    },
                ) {
                    LazyColumn(Modifier.fillMaxSize()) {
                        if (active != null &&
                            (active.status == MatchStatus.InProgress || active.status.isTerminal)
                        ) {
                            item {
                                SectionHeader("Active Match")
                            }
                            item {
                                ActiveMatchRow(active) { onOpen(active, false) }
                            }
                        }
                        item { SectionHeader("History") }
                        if (history.isEmpty()) {
                            item {
                                Text(
                                    "No completed matches yet.",
                                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                                    modifier = Modifier.padding(horizontal = 16.dp, vertical = 12.dp),
                                )
                            }
                        } else {
                            items(history, key = { it.id }) { match ->
                                MatchHistoryRow(
                                    match = match,
                                    note = service.note(match.id),
                                    onClick = { onOpen(match, true) },
                                    onDelete = { pendingDeletion = listOf(match) },
                                )
                                HorizontalDivider()
                            }
                        }
                    }
                }
            }
            if (showEmpty) {
                EmptyHistory(Modifier.align(Alignment.Center).padding(32.dp))
            }
        }
    }

    if (pendingDeletion.isNotEmpty()) {
        val prompt = if (pendingDeletion.size > 1) {
            "Delete ${pendingDeletion.size} matches?"
        } else {
            "Delete this match?"
        }
        AlertDialog(
            onDismissRequest = { pendingDeletion = emptyList() },
            title = { Text(prompt) },
            text = { Text("This can't be undone. The match is removed from your Wear OS watch too.") },
            confirmButton = {
                TextButton(
                    onClick = {
                        pendingDeletion.forEach { service.deleteArchivedMatch(it.id) }
                        pendingDeletion = emptyList()
                    },
                ) { Text("Delete") }
            },
            dismissButton = {
                TextButton(onClick = { pendingDeletion = emptyList() }) { Text("Cancel") }
            },
        )
    }
}

@Composable
private fun SectionHeader(title: String) {
    Text(
        title,
        style = MaterialTheme.typography.titleSmall,
        color = MaterialTheme.colorScheme.primary,
        modifier = Modifier.padding(start = 16.dp, top = 16.dp, end = 16.dp, bottom = 4.dp),
    )
}

@Composable
private fun EmptyHistory(modifier: Modifier = Modifier) {
    Column(
        modifier = modifier,
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.spacedBy(8.dp),
    ) {
        Icon(Icons.Outlined.Watch, contentDescription = null)
        Text("No Matches Yet", style = MaterialTheme.typography.titleLarge)
        Text(
            "Start a match on your Wear OS watch. Completed matches will appear here.",
            style = MaterialTheme.typography.bodyMedium,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
        )
    }
}

@Composable
private fun ActiveMatchRow(match: MatchState, onClick: () -> Unit) {
    val game = match.gameDisplayPair
    Column(
        Modifier
            .fillMaxWidth()
            .clickable(onClick = onClick)
            .padding(horizontal = 16.dp, vertical = 12.dp),
    ) {
        Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween) {
            Text(
                if (match.status == MatchStatus.InProgress) "In Progress" else match.status.displayName,
                style = MaterialTheme.typography.titleMedium,
            )
            Text(
                "${match.leftSetsWon}–${match.rightSetsWon}",
                style = MaterialTheme.typography.titleMedium,
                fontFamily = FontFamily.Monospace,
                fontWeight = FontWeight.Bold,
            )
        }
        Text(
            "Set ${match.currentSet.leftGames}–${match.currentSet.rightGames} · Game ${game.first}–${game.second}",
            style = MaterialTheme.typography.bodyMedium,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
        )
        if (match.currentGame.isGoldenPointActive) {
            Text(
                match.settings.deuceFormat.decidingPointLabel,
                style = MaterialTheme.typography.labelMedium,
                color = Color(0xFFFF8C00),
                fontWeight = FontWeight.SemiBold,
            )
        }
    }
}

@Composable
private fun MatchHistoryRow(
    match: MatchState,
    note: String,
    onClick: () -> Unit,
    onDelete: () -> Unit,
) {
    val score = match.finalScoreSummary.ifEmpty { "${match.leftSetsWon}–${match.rightSetsWon}" }
    ListItem(
        headlineContent = {
            Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween) {
                Text(formatStarted(match), style = MaterialTheme.typography.titleMedium)
                Text(
                    match.status.displayName,
                    style = MaterialTheme.typography.labelMedium,
                    color = statusColor(match.status),
                )
            }
        },
        supportingContent = {
            Column {
                Text(score, fontFamily = FontFamily.Monospace)
                Text(
                    DurationFormatter.detailed(match.duration()),
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
                if (note.isNotEmpty()) {
                    Row(
                        horizontalArrangement = Arrangement.spacedBy(4.dp),
                        verticalAlignment = Alignment.CenterVertically,
                    ) {
                        Icon(Icons.AutoMirrored.Outlined.Notes, contentDescription = null)
                        Text(
                            note,
                            style = MaterialTheme.typography.bodySmall,
                            color = MaterialTheme.colorScheme.onSurfaceVariant,
                            maxLines = 1,
                        )
                    }
                }
            }
        },
        trailingContent = {
            TextButton(onClick = onDelete) { Text("Delete") }
        },
        modifier = Modifier.clickable(onClick = onClick),
    )
}

private fun statusColor(status: MatchStatus): Color = when (status) {
    MatchStatus.Completed -> Color(0xFF2E7D32)
    MatchStatus.EndedEarly -> Color(0xFFEF6C00)
    MatchStatus.InProgress -> Color(0xFF1565C0)
    MatchStatus.Discarded -> Color.Gray
}

private val startedFormatter: DateTimeFormatter =
    DateTimeFormatter.ofLocalizedDateTime(FormatStyle.MEDIUM, FormatStyle.SHORT)

fun formatStarted(match: MatchState): String =
    startedFormatter.format(match.startedAt.atZone(ZoneId.systemDefault()))
