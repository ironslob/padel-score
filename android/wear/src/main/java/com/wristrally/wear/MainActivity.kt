package com.wristrally.wear

import android.os.Bundle
import android.os.Handler
import android.os.Looper
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
import com.wristrally.domain.FileMatchStore
import com.wristrally.domain.MatchService

class MainActivity : ComponentActivity() {
    private val appModel: WearAppModel by lazy { WearAppModel.fromActivity(this) }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        setContent {
            MaterialTheme {
                WearApp(appModel)
            }
        }
    }
}

class WearAppModel(
    val service: MatchService,
    val session: MatchSessionCoordinator,
) {
    companion object {
        fun fromActivity(activity: MainActivity): WearAppModel {
            val service = MatchService(FileMatchStore(activity.filesDir.toPath().resolve("WristRally")))
            return WearAppModel(
                service = service,
                session = MatchSessionCoordinator(
                    service = service,
                    workoutManager = ForegroundWorkoutManager(activity.applicationContext),
                    tipStore = SharedPreferencesTipStore.create(activity),
                    serveStore = SharedPreferencesStore.create(activity),
                ),
            )
        }
    }
}

@Composable
fun WearApp(model: WearAppModel) {
    var revision by remember { mutableIntStateOf(0) }
    DisposableEffect(model) {
        val mainHandler = Handler(Looper.getMainLooper())
        fun bumpRevision() {
            if (Looper.myLooper() == Looper.getMainLooper()) {
                revision += 1
            } else {
                mainHandler.post { revision += 1 }
            }
        }
        val listener: () -> Unit = { bumpRevision() }
        model.service.addListener(listener)
        model.session.addListener(listener)
        onDispose {
            model.service.removeListener(listener)
            model.session.removeListener(listener)
        }
    }
    LifecycleResumeEffect(model) {
        model.session.handleBecameActive()
        onPauseOrDispose { }
    }
    val tick = revision
    WearRoot(
        service = model.service,
        session = model.session,
        showFirstLaunchTip = model.session.showFirstLaunchTip,
        showWorkoutConflictPrompt = model.session.showWorkoutConflictPrompt,
        workoutErrorMessage = model.session.workoutErrorMessage,
        uiTick = tick,
    )
}
