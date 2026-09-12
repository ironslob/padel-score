package com.wristrally.wear

import android.content.Context
import android.util.Log
import androidx.health.services.client.ExerciseClient
import androidx.health.services.client.HealthServices
import androidx.health.services.client.data.DataType
import androidx.health.services.client.data.ExerciseConfig
import androidx.health.services.client.data.ExerciseType
import androidx.health.services.client.data.ExerciseTypeCapabilities
import com.wristrally.domain.WorkoutSessionError
import kotlin.coroutines.cancellation.CancellationException
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.guava.await
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import kotlinx.coroutines.withContext

interface WorkoutSessionManaging {
    val isRunning: Boolean
    suspend fun startWorkout()
    suspend fun endWorkout(save: Boolean)
}

class HealthServicesWorkoutManager(
    private val context: Context,
) : WorkoutSessionManaging {
    private val mutex = Mutex()
    override var isRunning: Boolean = false
        private set

    private fun exerciseClient(): ExerciseClient? = try {
        HealthServices.getClient(context).exerciseClient
    } catch (error: Exception) {
        CrashLog.write(context, error)
        null
    }

    override suspend fun startWorkout() {
        mutex.withLock {
            if (isRunning) return
            val client = exerciseClient() ?: throw WorkoutSessionError.HealthDataUnavailable
            if (!WorkoutPermissions.hasActivityRecognition(context)) {
                throw WorkoutSessionError.AuthorizationDenied
            }
            try {
                Log.i(CrashLog.TAG, "Querying Health Services capabilities")
                val capabilities = withContext(Dispatchers.IO) {
                    client.getCapabilitiesAsync().await()
                }
                val type = preferredExerciseType(capabilities.supportedExerciseTypes)
                    ?: throw WorkoutSessionError.HealthDataUnavailable
                Log.i(CrashLog.TAG, "Starting exercise type=$type")
                val typeCaps = try {
                    capabilities.getExerciseTypeCapabilities(type)
                } catch (_: Exception) {
                    throw WorkoutSessionError.HealthDataUnavailable
                }
                val config = ExerciseConfig.builder(type)
                    .setDataTypes(supportedDataTypes(typeCaps))
                    .setIsAutoPauseAndResumeEnabled(false)
                    .setIsGpsEnabled(false)
                    .build()
                withContext(Dispatchers.IO) {
                    client.startExerciseAsync(config).await()
                }
                isRunning = true
            } catch (error: CancellationException) {
                throw error
            } catch (error: WorkoutSessionError) {
                CrashLog.write(context, error)
                throw error
            } catch (error: Exception) {
                CrashLog.write(context, error)
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
            val client = exerciseClient()
            try {
                if (client == null) return
                withContext(Dispatchers.IO) {
                    if (save) {
                        client.endExerciseAsync().await()
                    } else {
                        runCatching { client.endExerciseAsync().await() }
                    }
                }
            } finally {
                isRunning = false
            }
        }
    }

    private fun supportedDataTypes(typeCaps: ExerciseTypeCapabilities): Set<DataType<*, *>> {
        val supported = typeCaps.supportedDataTypes
        return buildSet {
            if (WorkoutPermissions.hasBodySensors(context) && DataType.HEART_RATE_BPM in supported) {
                add(DataType.HEART_RATE_BPM)
            }
            if (DataType.CALORIES_TOTAL in supported) {
                add(DataType.CALORIES_TOTAL)
            }
        }
    }

    companion object {
        internal val preferredExerciseTypes: List<ExerciseType> = listOf(
            ExerciseType.TENNIS,
            ExerciseType.TABLE_TENNIS,
            ExerciseType.BADMINTON,
            ExerciseType.SQUASH,
            ExerciseType.RACQUETBALL,
        )

        internal fun preferredExerciseType(supported: Set<ExerciseType>): ExerciseType? =
            preferredExerciseTypes.firstOrNull { it in supported }
    }
}
