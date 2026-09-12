package com.wristrally.wear

import android.content.Context
import android.content.Intent
import android.os.Build
import android.util.Log
import androidx.core.content.ContextCompat
import com.wristrally.domain.WorkoutSessionError

/** Starts [ExerciseTrackingService] from the UI process without talking to Health Services here. */
class ForegroundWorkoutManager(
    private val context: Context,
) : WorkoutSessionManaging {
    override var isRunning: Boolean = false
        private set

    override suspend fun startWorkout() {
        if (isRunning) return
        if (!WorkoutPermissions.hasActivityRecognition(context)) {
            throw WorkoutSessionError.AuthorizationDenied
        }
        try {
            val intent = Intent(context, ExerciseTrackingService::class.java)
                .setAction(ExerciseTrackingService.ACTION_START)
            ContextCompat.startForegroundService(context, intent)
            isRunning = true
            Log.i(CrashLog.TAG, "Requested health foreground service")
        } catch (error: Exception) {
            CrashLog.write(context, error)
            val message = error.message.orEmpty().lowercase()
            if (message.contains("permission") || message.contains("security") ||
                (Build.VERSION.SDK_INT >= 31 && error.javaClass.simpleName.contains("ForegroundService"))
            ) {
                throw WorkoutSessionError.AuthorizationDenied
            }
            throw WorkoutSessionError.HealthDataUnavailable
        }
    }

    override suspend fun endWorkout(save: Boolean) {
        if (!isRunning) return
        try {
            context.startService(
                Intent(context, ExerciseTrackingService::class.java)
                    .setAction(ExerciseTrackingService.ACTION_STOP)
                    .putExtra(ExerciseTrackingService.EXTRA_SAVE, save),
            )
        } catch (error: Exception) {
            CrashLog.write(context, error)
        } finally {
            isRunning = false
        }
    }
}
