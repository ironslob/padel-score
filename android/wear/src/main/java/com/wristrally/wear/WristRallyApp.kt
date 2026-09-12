package com.wristrally.wear

import android.app.Application

class WristRallyApp : Application() {
    override fun onCreate() {
        super.onCreate()
        CrashLog.install(this)
    }
}
