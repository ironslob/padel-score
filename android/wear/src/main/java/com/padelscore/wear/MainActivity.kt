package com.padelscore.wear

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
import com.padelscore.domain.FileMatchStore
import com.padelscore.domain.MatchService

class MainActivity : ComponentActivity() {
    private val appModel: WearAppModel by lazy { WearAppModel(this) }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        setContent {
            MaterialTheme {
                WearApp(appModel)
            }
        }
    }
}

class WearAppModel(activity: MainActivity) {
    val service: MatchService
    val session: MatchSessionCoordinator

    init {
        val filesDir = activity.filesDir.toPath().resolve("PadelScore")
        service = MatchService(FileMatchStore(filesDir))
        session = MatchSessionCoordinator(
            service = service,
            workoutManager = HealthServicesWorkoutManager(activity.applicationContext),
            tipStore = SharedPreferencesTipStore.create(activity),
            serveStore = SharedPreferencesStore.create(activity),
        )
    }
}

@Composable
fun WearApp(model: WearAppModel) {
    var revision by remember { mutableIntStateOf(0) }
    DisposableEffect(model) {
        val listener: () -> Unit = { revision += 1 }
        model.service.addListener(listener)
        model.session.addListener(listener)
        onDispose {
            model.service.removeListener(listener)
        }
    }
    LifecycleResumeEffect(model) {
        model.session.handleBecameActive()
        onPauseOrDispose { }
    }
    // Read revision so Compose subscribes to service/session updates.
    @Suppress("UNUSED_VARIABLE")
    val tick = revision
    WearRoot(service = model.service, session = model.session)
}
