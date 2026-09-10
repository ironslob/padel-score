package com.wristrally.wear

import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.lifecycle.compose.LifecycleResumeEffect
import androidx.wear.compose.material3.MaterialTheme

class MainActivity : ComponentActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        val app = application as WristRallyWearApp
        setContent {
            MaterialTheme {
                WearApp(app)
            }
        }
    }
}

@Composable
fun WearApp(app: WristRallyWearApp) {
    var revision by remember { mutableIntStateOf(0) }
    DisposableEffect(app) {
        val listener: () -> Unit = { revision += 1 }
        app.service.addListener(listener)
        app.session.addListener(listener)
        onDispose {
            app.service.removeListener(listener)
        }
    }
    LifecycleResumeEffect(app) {
        app.session.handleBecameActive()
        onPauseOrDispose { }
    }
    // Read revision so Compose subscribes to service/session updates.
    @Suppress("UNUSED_VARIABLE")
    val tick = revision
    WearRoot(service = app.service, session = app.session)
}
