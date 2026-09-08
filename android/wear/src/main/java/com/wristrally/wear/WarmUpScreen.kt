package com.wristrally.wear

import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableLongStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.wear.compose.foundation.lazy.ScalingLazyColumn
import androidx.wear.compose.material3.Button
import androidx.wear.compose.material3.ButtonDefaults
import androidx.wear.compose.material3.FilledTonalButton
import androidx.wear.compose.material3.MaterialTheme
import androidx.wear.compose.material3.Text
import com.wristrally.domain.DurationFormatter
import com.wristrally.domain.MatchService
import com.wristrally.domain.MatchState
import java.time.Instant
import kotlinx.coroutines.delay

@Composable
fun WarmUpScreen(service: MatchService, match: MatchState) {
    var now by remember { mutableLongStateOf(System.currentTimeMillis()) }
    LaunchedEffect(match.id) {
        if (match.isWarmUpExpired()) {
            service.completeWarmUp()
            return@LaunchedEffect
        }
        val remaining = match.warmUpRemaining()
        if (remaining != null && remaining > 0) {
            delay((remaining * 1000).toLong())
            service.completeWarmUp()
        }
    }
    LaunchedEffect(Unit) {
        while (true) {
            now = System.currentTimeMillis()
            delay(200)
        }
    }
    val elapsed = match.warmUpElapsed(Instant.ofEpochMilli(now))
    ScalingLazyColumn(
        modifier = Modifier.fillMaxSize(),
        horizontalAlignment = Alignment.CenterHorizontally,
    ) {
        item { Text("Warm up", style = MaterialTheme.typography.titleMedium, textAlign = TextAlign.Center) }
        item {
            Text(
                DurationFormatter.countdown(elapsed),
                style = MaterialTheme.typography.displaySmall,
                fontWeight = FontWeight.SemiBold,
            )
        }
        item {
            Button(
                onClick = { service.completeWarmUp() },
                colors = ButtonDefaults.buttonColors(containerColor = StartGreen),
                modifier = Modifier.fillMaxWidth(),
            ) { Text("Play") }
        }
        item {
            FilledTonalButton(onClick = { service.discardMatch() }, modifier = Modifier.fillMaxWidth()) {
                Text("Back")
            }
        }
    }
}
