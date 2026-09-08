package com.wristrally.wear

import com.wristrally.domain.DeuceFormat
import com.wristrally.domain.MatchService
import com.wristrally.domain.MatchSettings
import com.wristrally.domain.MatchSetFormat
import com.wristrally.domain.MatchStatus
import com.wristrally.domain.ServeSelectionPreferenceStoring
import com.wristrally.domain.WorkoutConflictCopy
import com.wristrally.domain.WorkoutSessionError
import com.wristrally.domain.WristRaiseTipStoring
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import java.time.Duration
import java.time.Instant
import java.util.logging.Logger

class MatchSessionCoordinator(
    private val service: MatchService,
    private val workoutManager: WorkoutSessionManaging,
    private val tipStore: WristRaiseTipStoring,
    private val serveStore: ServeSelectionPreferenceStoring,
    private val scope: CoroutineScope = CoroutineScope(SupervisorJob() + Dispatchers.Main.immediate),
) {
    enum class WorkoutConflictResolution { ContinueWithoutWorkout, CancelMatchStart }

    private val logger = Logger.getLogger("com.wristrally.MatchSession")
    private val listeners = mutableListOf<() -> Unit>()
    private var inactivityJob: Job? = null

    var alwaysAskServeAtSetStart: Boolean = serveStore.alwaysAskServeAtSetStart
        private set
    var fixedServerPositions: Boolean = serveStore.fixedServerPositions
        private set
    var usThemLabels: Boolean = serveStore.usThemLabels
        private set
    var deuceFormat: DeuceFormat = serveStore.deuceFormat
        private set
    var matchSetFormat: MatchSetFormat = serveStore.matchSetFormat
        private set
    var warmUpEnabled: Boolean = serveStore.warmUpEnabled
        private set
    var warmUpMinutes: Int = serveStore.warmUpMinutes
        private set
    var isWorkoutSessionActive: Boolean = false
        private set
    var workoutErrorMessage: String? = null
        private set
    var showFirstLaunchTip: Boolean = false
    var showWorkoutConflictPrompt: Boolean = false

    init {
        service.addListener {
            handleActiveMatchChanged()
            rescheduleInactivityTimer()
            notifyListeners()
        }
    }

    fun addListener(listener: () -> Unit) {
        listeners += listener
    }

    fun setUsThemLabels(value: Boolean) {
        usThemLabels = value
        serveStore.usThemLabels = value
        syncPreferencesToActiveMatch()
        notifyListeners()
    }

    fun setFixedServerPositions(value: Boolean) {
        fixedServerPositions = value
        serveStore.fixedServerPositions = value
        syncPreferencesToActiveMatch()
        notifyListeners()
    }

    fun setAlwaysAskServeAtSetStart(value: Boolean) {
        alwaysAskServeAtSetStart = value
        serveStore.alwaysAskServeAtSetStart = value
        syncPreferencesToActiveMatch()
        notifyListeners()
    }

    fun setDeuceFormat(value: DeuceFormat) {
        deuceFormat = value
        serveStore.deuceFormat = value
        service.setDeuceFormat(value)
        notifyListeners()
    }

    fun setMatchSetFormat(value: MatchSetFormat) {
        matchSetFormat = value
        serveStore.matchSetFormat = value
        notifyListeners()
    }

    fun setWarmUpEnabled(value: Boolean) {
        warmUpEnabled = value
        serveStore.warmUpEnabled = value
        notifyListeners()
    }

    fun setWarmUpMinutes(value: Int) {
        val clamped = MatchSettings.clampedWarmUpMinutes(value)
        warmUpMinutes = clamped
        serveStore.warmUpMinutes = clamped
        notifyListeners()
    }

    suspend fun startMatch() {
        if (service.activeMatch != null) return
        var settings = MatchSettings()
        settings = settings.copy(deuceFormat = deuceFormat)
        settings = matchSetFormat.apply(settings)
        settings = settings.copy(
            askServeAtSetStart = alwaysAskServeAtSetStart,
            fixedServerPositions = fixedServerPositions,
            usThemLabels = usThemLabels,
            warmUpEnabled = warmUpEnabled,
            warmUpMinutes = warmUpMinutes,
        )
        service.startMatch(settings)
        startWorkoutSession()
    }

    fun presentFirstLaunchTipIfNeeded() {
        if (!tipStore.shouldShowTip) return
        showFirstLaunchTip = true
        notifyListeners()
    }

    fun dismissFirstLaunchTip() {
        showFirstLaunchTip = false
        tipStore.markTipSeen()
        notifyListeners()
    }

    fun handleBecameActive() {
        service.expireInactiveMatchIfNeeded()
        rescheduleInactivityTimer()
    }

    fun dismissWorkoutError() {
        workoutErrorMessage = null
        notifyListeners()
    }

    fun resolveWorkoutConflict(resolution: WorkoutConflictResolution) {
        showWorkoutConflictPrompt = false
        when (resolution) {
            WorkoutConflictResolution.ContinueWithoutWorkout -> workoutErrorMessage = null
            WorkoutConflictResolution.CancelMatchStart -> {
                service.discardMatch()
                workoutErrorMessage = null
            }
        }
        notifyListeners()
    }

    private fun syncPreferencesToActiveMatch() {
        service.syncActiveMatchPreferences(
            usThemLabels = usThemLabels,
            fixedServerPositions = fixedServerPositions,
            askServeAtSetStart = alwaysAskServeAtSetStart,
        )
    }

    private fun rescheduleInactivityTimer() {
        inactivityJob?.cancel()
        inactivityJob = null
        val match = service.activeMatch ?: return
        if (match.status != MatchStatus.InProgress) return
        val elapsed = Duration.between(match.lastScoringActivityAt, Instant.now()).seconds
        val remaining = MatchSettings.INACTIVITY_TIMEOUT_SECONDS - elapsed
        if (remaining <= 0) {
            service.expireInactiveMatchIfNeeded()
            return
        }
        inactivityJob = scope.launch {
            delay((remaining * 1000).toLong())
            service.expireInactiveMatchIfNeeded()
        }
    }

    private fun handleActiveMatchChanged() {
        val match = service.activeMatch
        if (match == null) {
            scope.launch { endWorkoutSession(saveWorkout = false) }
            return
        }
        when (match.status) {
            MatchStatus.InProgress -> Unit
            MatchStatus.Completed, MatchStatus.EndedEarly ->
                scope.launch { endWorkoutSession(saveWorkout = true) }
            MatchStatus.Discarded ->
                scope.launch { endWorkoutSession(saveWorkout = false) }
        }
    }

    private suspend fun startWorkoutSession() {
        try {
            workoutManager.startWorkout()
            isWorkoutSessionActive = true
            workoutErrorMessage = null
            logger.info("Workout session started")
        } catch (error: WorkoutSessionError) {
            isWorkoutSessionActive = false
            if (error == WorkoutSessionError.AnotherWorkoutSessionActive) {
                showWorkoutConflictPrompt = true
                workoutErrorMessage = null
            } else {
                workoutErrorMessage = error.userMessage
            }
            logger.warning("Workout start failed: ${error.userMessage}")
        } catch (error: Exception) {
            isWorkoutSessionActive = false
            workoutErrorMessage = WorkoutConflictCopy.genericFailureMessage
            logger.warning("Workout start failed: ${error.message}")
        }
        notifyListeners()
    }

    private suspend fun endWorkoutSession(saveWorkout: Boolean) {
        if (!isWorkoutSessionActive && !workoutManager.isRunning) return
        try {
            workoutManager.endWorkout(saveWorkout)
        } finally {
            isWorkoutSessionActive = false
        }
    }

    private fun notifyListeners() {
        listeners.toList().forEach { it() }
    }
}
