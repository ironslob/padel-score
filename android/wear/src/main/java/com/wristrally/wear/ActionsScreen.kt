package com.wristrally.wear

import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.wear.compose.foundation.lazy.ScalingLazyColumn
import androidx.wear.compose.material3.Button
import androidx.wear.compose.material3.ButtonDefaults
import androidx.wear.compose.material3.FilledTonalButton
import androidx.wear.compose.material3.Text
import com.wristrally.domain.DeuceFormat
import com.wristrally.domain.MatchService
import com.wristrally.domain.MatchState
import com.wristrally.domain.SettingsCopy

@Composable
fun ActionsScreen(
    service: MatchService,
    session: MatchSessionCoordinator,
    match: MatchState,
    onTips: () -> Unit,
) {
    var confirmEnd by remember { mutableStateOf(false) }
    var confirmDiscard by remember { mutableStateOf(false) }

    if (confirmEnd) {
        ConfirmScreen(
            title = "End this match? The current score is kept.",
            confirmLabel = "End Match",
            onConfirm = { service.finishMatch() },
            onCancel = { confirmEnd = false },
        )
        return
    }
    if (confirmDiscard) {
        ConfirmScreen(
            title = "Discard match? History will be deleted.",
            confirmLabel = "Discard",
            onConfirm = { service.discardMatch() },
            onCancel = { confirmDiscard = false },
        )
        return
    }

    ScalingLazyColumn(modifier = Modifier.fillMaxSize()) {
        item {
            Button(
                onClick = { service.undoLastPoint() },
                enabled = service.canUndo,
                colors = ButtonDefaults.buttonColors(containerColor = UndoOrange),
                modifier = Modifier.fillMaxWidth(),
            ) { Text("Undo Last Point") }
        }
        if (match.canChooseNewServer) {
            item {
                FilledTonalButton(onClick = { service.requestServerSelection() }, modifier = Modifier.fillMaxWidth()) {
                    Text("New Serve")
                }
            }
        }
        item {
            Button(
                onClick = { confirmEnd = true },
                colors = ButtonDefaults.buttonColors(containerColor = ThemRed),
                modifier = Modifier.fillMaxWidth(),
            ) { Text("End Match") }
        }
        item {
            PreferenceCycleButton("Scoring at deuce", match.settings.deuceFormat.label, SettingsCopy.deuceFormat) {
                val all = DeuceFormat.entries
                session.setDeuceFormat(all[(all.indexOf(match.settings.deuceFormat) + 1) % all.size])
            }
        }
        item {
            PreferenceToggleButton("Us / Them labels", match.settings.usThemLabels, SettingsCopy.usThemLabels) {
                session.setUsThemLabels(!match.settings.usThemLabels)
            }
        }
        item {
            PreferenceToggleButton("Swap sides each game", !match.settings.fixedServerPositions, SettingsCopy.fixedServerPositions) {
                session.setFixedServerPositions(!match.settings.fixedServerPositions)
            }
        }
        item {
            PreferenceToggleButton("Ask serve at set start", match.settings.askServeAtSetStart, SettingsCopy.askServeAtSetStart) {
                session.setAlwaysAskServeAtSetStart(!match.settings.askServeAtSetStart)
            }
        }
        item {
            FilledTonalButton(onClick = onTips, modifier = Modifier.fillMaxWidth()) { Text("During play tips") }
        }
        item {
            Button(
                onClick = { confirmDiscard = true },
                colors = ButtonDefaults.buttonColors(containerColor = ThemRed),
                modifier = Modifier.fillMaxWidth(),
            ) { Text("Discard Match") }
        }
    }
}
