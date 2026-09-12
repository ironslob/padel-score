package com.wristrally.wear

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.Service
import android.content.Intent
import android.content.pm.ServiceInfo
import android.os.Build
import android.os.IBinder
import android.util.Log
import androidx.core.app.NotificationCompat
import androidx.core.app.ServiceCompat
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.launch

/**
 * Owns Wear Health Services in a separate process. Samsung's Health Services
 * client can native-crash; keeping that off the UI process lets scoring survive.
 */
class ExerciseTrackingService : Service() {
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.Main.immediate)
    private var workout: HealthServicesWorkoutManager? = null

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onCreate() {
        super.onCreate()
        CrashLog.install(this)
        promoteToForeground()
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        promoteToForeground()
        when (intent?.action) {
            ACTION_START -> scope.launch {
                try {
                    manager().startWorkout()
                    Log.i(CrashLog.TAG, "Health Services exercise started")
                } catch (error: Exception) {
                    CrashLog.write(this@ExerciseTrackingService, error)
                    Log.w(CrashLog.TAG, "Health Services exercise start failed: ${error.message}")
                }
            }
            ACTION_STOP -> scope.launch {
                try {
                    manager().endWorkout(intent.getBooleanExtra(EXTRA_SAVE, true))
                } catch (error: Exception) {
                    CrashLog.write(this@ExerciseTrackingService, error)
                } finally {
                    stopForeground(STOP_FOREGROUND_REMOVE)
                    stopSelf()
                }
            }
        }
        return START_STICKY
    }

    private fun manager(): HealthServicesWorkoutManager {
        return workout ?: HealthServicesWorkoutManager(applicationContext).also { workout = it }
    }

    private fun promoteToForeground() {
        val manager = getSystemService(NotificationManager::class.java)
        manager.createNotificationChannel(
            NotificationChannel(CHANNEL_ID, getString(R.string.workout_channel_name), NotificationManager.IMPORTANCE_LOW),
        )
        val notification: Notification = NotificationCompat.Builder(this, CHANNEL_ID)
            .setContentTitle(getString(R.string.app_name))
            .setContentText(getString(R.string.workout_notification_text))
            .setSmallIcon(android.R.drawable.ic_media_play)
            .setOngoing(true)
            .setForegroundServiceBehavior(NotificationCompat.FOREGROUND_SERVICE_IMMEDIATE)
            .build()
        val type = if (Build.VERSION.SDK_INT >= 34) {
            ServiceInfo.FOREGROUND_SERVICE_TYPE_HEALTH
        } else {
            0
        }
        ServiceCompat.startForeground(this, NOTIFICATION_ID, notification, type)
    }

    companion object {
        const val ACTION_START = "com.wristrally.wear.START_EXERCISE"
        const val ACTION_STOP = "com.wristrally.wear.STOP_EXERCISE"
        const val EXTRA_SAVE = "save"
        private const val CHANNEL_ID = "match_workout"
        private const val NOTIFICATION_ID = 41
    }
}
