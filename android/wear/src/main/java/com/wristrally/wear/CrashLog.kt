package com.wristrally.wear

import android.content.Context
import android.util.Log
import java.io.File
import java.time.Instant

/** Persists the last uncaught exception so it can be pulled when logcat is empty. */
object CrashLog {
    const val TAG = "WristRally"
    const val FILE_NAME = "last-crash.txt"

    fun install(context: Context) {
        val appContext = context.applicationContext
        val previous = Thread.getDefaultUncaughtExceptionHandler()
        Thread.setDefaultUncaughtExceptionHandler { thread, error ->
            write(appContext, error)
            previous?.uncaughtException(thread, error)
        }
    }

    fun write(context: Context, error: Throwable) {
        Log.e(TAG, error.message, error)
        runCatching {
            File(context.filesDir, FILE_NAME).writeText(
                buildString {
                    appendLine(Instant.now().toString())
                    appendLine(error.stackTraceToString())
                },
            )
        }
    }
}
