package com.wristrally.wear

import com.wristrally.domain.FileMatchStore
import com.wristrally.domain.InMemoryMatchStore
import com.wristrally.domain.InMemoryPreferenceStore
import com.wristrally.domain.InMemoryTipStore
import com.wristrally.domain.MatchService
import com.wristrally.domain.WorkoutSessionError
import java.nio.file.Files
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.runBlocking
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config

internal object IdleWorkoutManager : WorkoutSessionManaging {
    override var isRunning: Boolean = false
    override suspend fun startWorkout() {}
    override suspend fun endWorkout(save: Boolean) {}
}

internal class ExplodingWorkoutManager : WorkoutSessionManaging {
    override var isRunning: Boolean = false
    override suspend fun startWorkout() {
        throw RuntimeException("Health Services native crash")
    }
    override suspend fun endWorkout(save: Boolean) {}
}

internal class DeniedWorkoutManager : WorkoutSessionManaging {
    override var isRunning: Boolean = false
    override suspend fun startWorkout() {
        throw WorkoutSessionError.HealthDataUnavailable
    }
    override suspend fun endWorkout(save: Boolean) {}
}

internal fun testWearModel(
    tipSeen: Boolean = false,
    warmUpEnabled: Boolean = true,
    workout: WorkoutSessionManaging = IdleWorkoutManager,
): WearAppModel {
    val service = MatchService(InMemoryMatchStore(), autoRestore = false)
    val tips = InMemoryTipStore()
    if (tipSeen) tips.markTipSeen()
    val prefs = InMemoryPreferenceStore().apply { this.warmUpEnabled = warmUpEnabled }
    val session = MatchSessionCoordinator(
        service = service,
        workoutManager = workout,
        tipStore = tips,
        serveStore = prefs,
        scope = CoroutineScope(SupervisorJob() + Dispatchers.Unconfined),
    )
    return WearAppModel(service, session)
}

@RunWith(RobolectricTestRunner::class)
@Config(sdk = [33])
class WearSessionTests {
    @Test
    fun dismissFirstLaunchTipClearsTheFlagSoHomeCanShow() {
        val model = testWearModel(tipSeen = false)
        model.session.presentFirstLaunchTipIfNeeded()
        assertTrue(model.session.showFirstLaunchTip)
        model.session.dismissFirstLaunchTip()
        assertFalse(model.session.showFirstLaunchTip)
        assertNull(model.service.activeMatch)
    }

    @Test
    fun startMatchSurvivesWorkoutManagerCrashAndKeepsScoring() = runBlocking {
        val model = testWearModel(tipSeen = true, workout = ExplodingWorkoutManager())
        model.session.startMatch()
        assertNotNull(model.service.activeMatch)
        assertFalse(model.session.isWorkoutSessionActive)
        assertEquals(
            com.wristrally.domain.WorkoutConflictCopy.genericFailureMessage,
            model.session.workoutErrorMessage,
        )
    }

    @Test
    fun startMatchContinuesWhenHealthServicesIsUnavailable() = runBlocking {
        val model = testWearModel(tipSeen = true, warmUpEnabled = false, workout = DeniedWorkoutManager())
        model.session.startMatch()
        assertNotNull(model.service.activeMatch)
        assertTrue(model.service.activeMatch!!.needsServerSelection)
    }

    @Test
    fun startMatchPersistsWithFileStoreOnApi33() = runBlocking {
        val dir = Files.createTempDirectory("wear-file-store")
        try {
            val service = MatchService(FileMatchStore(dir), autoRestore = false)
            val session = MatchSessionCoordinator(
                service = service,
                workoutManager = IdleWorkoutManager,
                tipStore = InMemoryTipStore().also { it.markTipSeen() },
                serveStore = InMemoryPreferenceStore(),
                scope = CoroutineScope(SupervisorJob() + Dispatchers.Unconfined),
            )
            session.startMatch()
            assertNotNull(service.activeMatch)
            val restored = MatchService(FileMatchStore(dir), autoRestore = true)
            assertNotNull(restored.activeMatch)
            assertEquals(service.activeMatch?.id, restored.activeMatch?.id)
        } finally {
            dir.toFile().deleteRecursively()
        }
    }
}
