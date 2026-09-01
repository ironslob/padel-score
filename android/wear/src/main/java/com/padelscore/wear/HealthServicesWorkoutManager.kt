package com.padelscore.wear

import android.content.Context
import androidx.health.services.client.HealthServices
import androidx.health.services.client.ExerciseClient
import androidx.health.services.client.data.ExerciseConfig
import androidx.health.services.client.data.ExerciseType
import androidx.health.services.client.data.DataType
import com.padelscore.domain.WorkoutSessionError
import kotlinx.coroutines.guava.await
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock

interface WorkoutSessionManaging {
    val isRunning: Boolean
    suspend fun startWorkout()
    suspend fun endWorkout(save: Boolean)
}

class HealthServicesWorkoutManager(
    context: Context,
) : WorkoutSessionManaging {
    private val client: ExerciseClient = HealthServices.getClient(context).exerciseClient
    private val mutex = Mutex()
    override var isRunning: Boolean = false
        private set

    override suspend fun startWorkout() {
        mutex.withLock {
            if (isRunning) return
            try {
                val capabilities = client.getCapabilitiesAsync().await()
                val type = when {
                    ExerciseType.TENNIS in capabilities.supportedExerciseTypes -> ExerciseType.TENNIS
                    ExerciseType.BADMINTON in capabilities.supportedExerciseTypes -> ExerciseType.BADMINTON
                    else -> throw WorkoutSessionError.HealthDataUnavailable
                }
                val config = ExerciseConfig.builder(type)
                    .setDataTypes(setOf(DataType.HEART_RATE_BPM, DataType.CALORIES_TOTAL))
                    .setIsAutoPauseAndResumeEnabled(false)
                    .build()
                client.startExerciseAsync(config).await()
                isRunning = true
            } catch (error: WorkoutSessionError) {
                throw error
            } catch (error: Exception) {
                val message = error.message.orEmpty().lowercase()
                if (message.contains("already") || message.contains("active")) {
                    throw WorkoutSessionError.AnotherWorkoutSessionActive
                }
                if (message.contains("permission") || message.contains("security")) {
                    throw WorkoutSessionError.AuthorizationDenied
                }
                throw WorkoutSessionError.HealthDataUnavailable
            }
        }
    }

    override suspend fun endWorkout(save: Boolean) {
        mutex.withLock {
            if (!isRunning) return
            try {
                if (save) {
                    client.endExerciseAsync().await()
                } else {
                    runCatching { client.endExerciseAsync().await() }
                }
            } finally {
                isRunning = false
            }
        }
    }
}
