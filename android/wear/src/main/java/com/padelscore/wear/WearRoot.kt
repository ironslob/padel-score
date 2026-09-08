package com.padelscore.wear

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.pager.HorizontalPager
import androidx.compose.foundation.pager.rememberPagerState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.compose.LocalLifecycleOwner
import androidx.lifecycle.repeatOnLifecycle
import androidx.wear.compose.foundation.lazy.ScalingLazyColumn
import androidx.wear.compose.foundation.lazy.rememberScalingLazyListState
import androidx.wear.compose.material3.Button
import androidx.wear.compose.material3.ButtonDefaults
import androidx.wear.compose.material3.FilledTonalButton
import androidx.wear.compose.material3.MaterialTheme
import androidx.wear.compose.material3.Text
import com.padelscore.domain.DeuceFormat
import com.padelscore.domain.DuringPlayAccessCopy
import com.padelscore.domain.FirstLaunchTipCopy
import com.padelscore.domain.MatchService
import com.padelscore.domain.MatchSetFormat
import com.padelscore.domain.MatchSettings
import com.padelscore.domain.MatchState
import com.padelscore.domain.MatchStatus
import com.padelscore.domain.SettingsCopy
import com.padelscore.domain.Side
import com.padelscore.domain.WorkoutConflictCopy
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch

val WatchButtonShape = RoundedCornerShape(12.dp)
val UsBlue = Color(0xFF0A84FF)
val ThemRed = Color(0xFFFF453A)
val StartGreen = Color(0xFF30D158)
val UndoOrange = Color(0xFFFF9F0A)

@Composable
fun WearRoot(
    service: MatchService,
    session: MatchSessionCoordinator,
) {
    val match = service.activeMatch
    var showSettings by remember { mutableStateOf(false) }
    var showTips by remember { mutableStateOf(false) }
    var showGameInterstitial by remember { mutableStateOf(false) }
    var gameInterstitialCompletedSet by remember { mutableStateOf(false) }
    var gameInterstitialIsTieBreak by remember { mutableStateOf(false) }
    var previousMatch by remember { mutableStateOf<MatchState?>(null) }

    LaunchedEffect(match) {
        val oldMatch = previousMatch
        val newMatch = match
        previousMatch = newMatch
        if (oldMatch == null || newMatch == null) {
            showGameInterstitial = false
            return@LaunchedEffect
        }
        val completedSet = didCompleteSet(oldMatch, newMatch)
        if (completedSet != null) {
            gameInterstitialCompletedSet = completedSet
            gameInterstitialIsTieBreak = newMatch.currentGame.isTieBreak && !oldMatch.currentGame.isTieBreak
            showGameInterstitial = true
            if (!completedSet) {
                delay((MatchSettings.QUICK_UNDO_TIMEOUT_SECONDS * 1000).toLong())
                showGameInterstitial = false
            }
        } else if (showGameInterstitial && newMatch.events.size < oldMatch.events.size) {
            showGameInterstitial = false
        }
    }

    LaunchedEffect(Unit) {
        session.presentFirstLaunchTipIfNeeded()
    }

    when {
        session.showFirstLaunchTip -> FirstLaunchTipScreen(onDismiss = { session.dismissFirstLaunchTip() })
        session.showWorkoutConflictPrompt -> WorkoutConflictScreen(session)
        session.workoutErrorMessage != null -> WorkoutErrorScreen(
            message = session.workoutErrorMessage.orEmpty(),
            onDismiss = { session.dismissWorkoutError() },
        )
        showTips -> HelpScreen(
            title = DuringPlayAccessCopy.helpTitle,
            sections = DuringPlayAccessCopy.helpSections,
            onDismiss = { showTips = false },
        )
        showSettings -> SettingsScreen(session, onDone = { showSettings = false }, onTips = { showTips = true })
        match == null || match.status == MatchStatus.Discarded ->
            StartMatchScreen(session, onSettings = { showSettings = true })
        match.status == MatchStatus.Completed || match.status == MatchStatus.EndedEarly ->
            MatchCompleteScreen(service, match)
        match.needsWarmUp -> WarmUpScreen(service, match)
        match.needsServerSelection -> SelectServerScreen(service, match)
        showGameInterstitial -> GameInterstitialScreen(
            service = service,
            match = match,
            completedSet = gameInterstitialCompletedSet,
            isTieBreak = gameInterstitialIsTieBreak,
            onNext = { showGameInterstitial = false },
            onChooseServer = {
                service.requestServerSelection()
                showGameInterstitial = false
            },
        )
        else -> ActiveMatchPager(service, session, match, onTips = { showTips = true })
    }
}

private fun didCompleteSet(oldMatch: MatchState, newMatch: MatchState): Boolean? {
    if (oldMatch.status != MatchStatus.InProgress || newMatch.status != MatchStatus.InProgress) return null
    if (newMatch.events.size <= oldMatch.events.size) return null
    if (newMatch.events.lastOrNull()?.kind != com.padelscore.domain.MatchEventKind.PointWon) return null
    val oldGamesTotal = oldMatch.currentSet.leftGames + oldMatch.currentSet.rightGames
    val newGamesTotal = newMatch.currentSet.leftGames + newMatch.currentSet.rightGames
    val setAdvanced = newMatch.completedSets.size > oldMatch.completedSets.size
    val gameAdvanced = newGamesTotal > oldGamesTotal
    if (!setAdvanced && !gameAdvanced) return null
    return setAdvanced
}

@Composable
fun StartMatchScreen(session: MatchSessionCoordinator, onSettings: () -> Unit) {
    val scope = rememberCoroutineScope()
    var starting by remember { mutableStateOf(false) }
    ScalingLazyColumn(
        modifier = Modifier.fillMaxSize(),
        horizontalAlignment = Alignment.CenterHorizontally,
    ) {
        item {
            Text("Wrist Rally", style = MaterialTheme.typography.titleMedium, textAlign = TextAlign.Center)
        }
        item {
            Button(
                onClick = {
                    if (starting) return@Button
                    starting = true
                    scope.launch {
                        session.startMatch()
                        starting = false
                    }
                },
                enabled = !starting,
                colors = ButtonDefaults.buttonColors(containerColor = StartGreen),
                modifier = Modifier.fillMaxWidth(),
            ) {
                Text(if (starting) "Starting…" else "Start Match")
            }
        }
        item {
            FilledTonalButton(onClick = onSettings, modifier = Modifier.fillMaxWidth()) {
                Text("Settings")
            }
        }
    }
}

@Composable
fun SelectServerScreen(service: MatchService, match: MatchState) {
    val canReturn = match.isWaitingForFirstServe
    ScalingLazyColumn(
        modifier = Modifier.fillMaxSize(),
        horizontalAlignment = Alignment.CenterHorizontally,
    ) {
        item {
            Text("Who's serving?", style = MaterialTheme.typography.titleMedium, textAlign = TextAlign.Center)
        }
        item {
            Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                Button(
                    onClick = { service.selectServer(Side.Left) },
                    colors = ButtonDefaults.buttonColors(containerColor = UsBlue),
                    modifier = Modifier.weight(1f),
                ) { Text("Us") }
                Button(
                    onClick = { service.selectServer(Side.Right) },
                    colors = ButtonDefaults.buttonColors(containerColor = ThemRed),
                    modifier = Modifier.weight(1f),
                ) { Text("Them") }
            }
        }
        if (canReturn) {
            item {
                FilledTonalButton(onClick = { service.discardMatch() }, modifier = Modifier.fillMaxWidth()) {
                    Text("Back")
                }
            }
        }
    }
}

@Composable
fun GameInterstitialScreen(
    service: MatchService,
    match: MatchState,
    completedSet: Boolean,
    isTieBreak: Boolean,
    onNext: () -> Unit,
    onChooseServer: () -> Unit,
) {
    var confirmEnd by remember { mutableStateOf(false) }
    val headline = when {
        completedSet -> "Set!"
        isTieBreak -> "Tie-break"
        else -> "Game!"
    }
    val games = if (completedSet) {
        match.completedSets.lastOrNull()?.displayPair ?: match.currentSet.displayPair
    } else {
        match.currentSet.displayPair
    }
    val sets = match.matchSetsDisplay
    val offersServeChoice = completedSet && match.canChooseNewServer

    if (confirmEnd) {
        ConfirmScreen(
            title = "End this match? The current score is kept.",
            confirmLabel = "End Match",
            onConfirm = { service.finishMatch() },
            onCancel = { confirmEnd = false },
        )
        return
    }

    ScalingLazyColumn(
        modifier = Modifier.fillMaxSize(),
        horizontalAlignment = Alignment.CenterHorizontally,
    ) {
        item {
            Text(headline, style = MaterialTheme.typography.titleMedium, fontWeight = FontWeight.Bold)
        }
        item {
            Text(
                when {
                    match.isMatchTieBreak -> "First to 10, win by 2"
                    isTieBreak -> "First to 7, win by 2"
                    else -> "Sets ${sets.first} – ${sets.second}"
                },
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )
        }
        item {
            Text("Games ${games.first} – ${games.second}", style = MaterialTheme.typography.titleSmall)
        }
        if (completedSet) {
            item {
                FilledTonalButton(onClick = onNext, modifier = Modifier.fillMaxWidth()) { Text("Next set") }
            }
            if (offersServeChoice) {
                item {
                    FilledTonalButton(onClick = onChooseServer, modifier = Modifier.fillMaxWidth()) { Text("New serve") }
                }
            }
            item {
                Button(
                    onClick = { service.undoLastPoint() },
                    enabled = service.canUndo,
                    colors = ButtonDefaults.buttonColors(containerColor = UndoOrange),
                    modifier = Modifier.fillMaxWidth(),
                ) { Text("Undo") }
            }
            item {
                Button(
                    onClick = { confirmEnd = true },
                    colors = ButtonDefaults.buttonColors(containerColor = ThemRed),
                    modifier = Modifier.fillMaxWidth(),
                ) { Text("End match") }
            }
        } else {
            item {
                Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                    Button(
                        onClick = { service.undoLastPoint() },
                        enabled = service.canUndo,
                        colors = ButtonDefaults.buttonColors(containerColor = UndoOrange),
                        modifier = Modifier.weight(1f),
                    ) { Text("Undo") }
                    Button(
                        onClick = onNext,
                        colors = ButtonDefaults.buttonColors(containerColor = StartGreen),
                        modifier = Modifier.weight(1f),
                    ) { Text("Next") }
                }
            }
        }
    }
}

@Composable
fun MatchCompleteScreen(service: MatchService, match: MatchState) {
    val title = when (match.status) {
        MatchStatus.Completed -> "Match Complete"
        MatchStatus.EndedEarly -> "Match Ended Early"
        else -> "Match Over"
    }
    val summary = match.finalScoreSummary.ifEmpty { "${match.leftSetsWon}–${match.rightSetsWon}" }
    ScalingLazyColumn(
        modifier = Modifier.fillMaxSize(),
        horizontalAlignment = Alignment.CenterHorizontally,
    ) {
        item { Text(title, style = MaterialTheme.typography.titleMedium, textAlign = TextAlign.Center) }
        item {
            when {
                match.winner == Side.Left -> Text("Won", color = StartGreen, fontWeight = FontWeight.Bold)
                match.winner == Side.Right -> Text("Lost", color = UndoOrange, fontWeight = FontWeight.Bold)
                match.status == MatchStatus.EndedEarly -> Text("Ended Early", color = UndoOrange)
            }
        }
        item { Text(summary, textAlign = TextAlign.Center) }
        item {
            Button(onClick = { service.acknowledgeCompletedMatch() }, modifier = Modifier.fillMaxWidth()) {
                Text("Done")
            }
        }
    }
}

@Composable
fun ActiveMatchPager(
    service: MatchService,
    session: MatchSessionCoordinator,
    match: MatchState,
    onTips: () -> Unit,
) {
    val pagerState = rememberPagerState(initialPage = 1, pageCount = { 3 })
    val lifecycleOwner = LocalLifecycleOwner.current
    LaunchedEffect(lifecycleOwner) {
        lifecycleOwner.lifecycle.repeatOnLifecycle(Lifecycle.State.RESUMED) {
            pagerState.scrollToPage(1)
        }
    }
    HorizontalPager(state = pagerState, modifier = Modifier.fillMaxSize()) { page ->
        when (page) {
            0 -> MatchOverviewScreen(match)
            1 -> ScoreScreen(service, match)
            else -> ActionsScreen(service, session, match, onTips)
        }
    }
}

@Composable
fun SettingsScreen(
    session: MatchSessionCoordinator,
    onDone: () -> Unit,
    onTips: () -> Unit,
) {
    ScalingLazyColumn(modifier = Modifier.fillMaxSize()) {
        item { Text("Settings", style = MaterialTheme.typography.titleMedium) }
        item {
            FilledTonalButton(onClick = onTips, modifier = Modifier.fillMaxWidth()) { Text("Tips") }
        }
        item { PreferenceCycleButton("Match length", session.matchSetFormat.label, SettingsCopy.matchSetFormat) {
            val all = MatchSetFormat.entries
            session.setMatchSetFormat(all[(all.indexOf(session.matchSetFormat) + 1) % all.size])
        } }
        item { PreferenceCycleButton("Scoring at deuce", session.deuceFormat.label, SettingsCopy.deuceFormat) {
            val all = DeuceFormat.entries
            session.setDeuceFormat(all[(all.indexOf(session.deuceFormat) + 1) % all.size])
        } }
        item { PreferenceToggleButton("Us / Them labels", session.usThemLabels, SettingsCopy.usThemLabels) {
            session.setUsThemLabels(!session.usThemLabels)
        } }
        item { PreferenceToggleButton("Swap sides each game", !session.fixedServerPositions, SettingsCopy.fixedServerPositions) {
            session.setFixedServerPositions(!session.fixedServerPositions)
        } }
        item { PreferenceToggleButton("Ask serve at set start", session.alwaysAskServeAtSetStart, SettingsCopy.askServeAtSetStart) {
            session.setAlwaysAskServeAtSetStart(!session.alwaysAskServeAtSetStart)
        } }
        item { PreferenceToggleButton("Warm up before match", session.warmUpEnabled, SettingsCopy.warmUp) {
            session.setWarmUpEnabled(!session.warmUpEnabled)
        } }
        if (session.warmUpEnabled) {
            item { PreferenceCycleButton("Warm-up limit", MatchSettings.warmUpMinutesLabel(session.warmUpMinutes), SettingsCopy.warmUpLimit) {
                session.setWarmUpMinutes(MatchSettings.nextWarmUpMinutes(session.warmUpMinutes))
            } }
        }
        item {
            Button(onClick = onDone, modifier = Modifier.fillMaxWidth()) { Text("Done") }
        }
    }
}

@Composable
fun PreferenceCycleButton(title: String, value: String, helper: String, onClick: () -> Unit) {
    FilledTonalButton(onClick = onClick, modifier = Modifier.fillMaxWidth()) {
        Column(Modifier.fillMaxWidth()) {
            Text(title, style = MaterialTheme.typography.labelSmall)
            Text(value, style = MaterialTheme.typography.bodyMedium)
        }
    }
}

@Composable
fun PreferenceToggleButton(title: String, isOn: Boolean, helper: String, onClick: () -> Unit) {
    FilledTonalButton(onClick = onClick, modifier = Modifier.fillMaxWidth()) {
        Column(Modifier.fillMaxWidth()) {
            Text(title, style = MaterialTheme.typography.labelSmall)
            Text(if (isOn) "On" else "Off", style = MaterialTheme.typography.bodyMedium)
        }
    }
}

@Composable
fun FirstLaunchTipScreen(onDismiss: () -> Unit) {
    HelpScreen(FirstLaunchTipCopy.title, FirstLaunchTipCopy.tipSections, onDismiss, confirmLabel = "Got it")
}

@Composable
fun HelpScreen(
    title: String,
    sections: List<Pair<String, String>>,
    onDismiss: () -> Unit,
    confirmLabel: String = "Done",
) {
    ScalingLazyColumn(modifier = Modifier.fillMaxSize()) {
        item { Text(title, style = MaterialTheme.typography.titleMedium) }
        sections.forEach { (sectionTitle, body) ->
            item {
                Column(Modifier.fillMaxWidth().padding(vertical = 4.dp)) {
                    Text(sectionTitle, fontWeight = FontWeight.Bold)
                    Text(body, style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
                }
            }
        }
        item {
            Button(onClick = onDismiss, modifier = Modifier.fillMaxWidth()) { Text(confirmLabel) }
        }
    }
}

@Composable
fun WorkoutConflictScreen(session: MatchSessionCoordinator) {
    ScalingLazyColumn(modifier = Modifier.fillMaxSize(), horizontalAlignment = Alignment.CenterHorizontally) {
        item { Text(WorkoutConflictCopy.title, style = MaterialTheme.typography.titleMedium, textAlign = TextAlign.Center) }
        item { Text(WorkoutConflictCopy.message, style = MaterialTheme.typography.bodySmall, textAlign = TextAlign.Center) }
        item {
            FilledTonalButton(
                onClick = { session.resolveWorkoutConflict(MatchSessionCoordinator.WorkoutConflictResolution.ContinueWithoutWorkout) },
                modifier = Modifier.fillMaxWidth(),
            ) { Text(WorkoutConflictCopy.continueWithoutWorkout) }
        }
        item {
            Button(
                onClick = { session.resolveWorkoutConflict(MatchSessionCoordinator.WorkoutConflictResolution.CancelMatchStart) },
                colors = ButtonDefaults.buttonColors(containerColor = ThemRed),
                modifier = Modifier.fillMaxWidth(),
            ) { Text(WorkoutConflictCopy.cancelMatchStart) }
        }
    }
}

@Composable
fun WorkoutErrorScreen(message: String, onDismiss: () -> Unit) {
    ScalingLazyColumn(modifier = Modifier.fillMaxSize(), horizontalAlignment = Alignment.CenterHorizontally) {
        item { Text("Workout tracking unavailable", style = MaterialTheme.typography.titleMedium, textAlign = TextAlign.Center) }
        item { Text(message, style = MaterialTheme.typography.bodySmall, textAlign = TextAlign.Center) }
        item { Button(onClick = onDismiss, modifier = Modifier.fillMaxWidth()) { Text("OK") } }
    }
}

@Composable
fun ConfirmScreen(title: String, confirmLabel: String, onConfirm: () -> Unit, onCancel: () -> Unit) {
    ScalingLazyColumn(modifier = Modifier.fillMaxSize(), horizontalAlignment = Alignment.CenterHorizontally) {
        item { Text(title, style = MaterialTheme.typography.bodyMedium, textAlign = TextAlign.Center) }
        item {
            Button(
                onClick = onConfirm,
                colors = ButtonDefaults.buttonColors(containerColor = ThemRed),
                modifier = Modifier.fillMaxWidth(),
            ) { Text(confirmLabel) }
        }
        item {
            FilledTonalButton(onClick = onCancel, modifier = Modifier.fillMaxWidth()) { Text("Cancel") }
        }
    }
}
