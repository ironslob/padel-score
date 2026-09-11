package com.wristrally.wear

import android.Manifest
import android.content.Context
import android.content.pm.PackageManager
import androidx.core.content.ContextCompat

/** Runtime permissions needed before talking to Wear Health Services. */
object WorkoutPermissions {
    val requested: Array<String> = arrayOf(
        Manifest.permission.ACTIVITY_RECOGNITION,
        Manifest.permission.BODY_SENSORS,
    )

    fun missing(context: Context): Array<String> =
        requested.filter { permission ->
            ContextCompat.checkSelfPermission(context, permission) != PackageManager.PERMISSION_GRANTED
        }.toTypedArray()

    fun hasActivityRecognition(context: Context): Boolean =
        ContextCompat.checkSelfPermission(
            context,
            Manifest.permission.ACTIVITY_RECOGNITION,
        ) == PackageManager.PERMISSION_GRANTED

    fun hasBodySensors(context: Context): Boolean =
        ContextCompat.checkSelfPermission(
            context,
            Manifest.permission.BODY_SENSORS,
        ) == PackageManager.PERMISSION_GRANTED
}
