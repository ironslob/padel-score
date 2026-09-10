package com.wristrally.wear

import android.app.Application
import com.wristrally.domain.FileMatchStore
import com.wristrally.domain.MatchService
import com.wristrally.sync.DataLayerTransport
import com.wristrally.sync.MatchSyncCoordinator
import com.wristrally.sync.WristRallySyncHost

class WristRallyWearApp : Application(), WristRallySyncHost {
    lateinit var service: MatchService
        private set
    lateinit var session: MatchSessionCoordinator
        private set
    override lateinit var syncCoordinator: MatchSyncCoordinator
        private set

    override fun onCreate() {
        super.onCreate()
        val filesDir = filesDir.toPath().resolve("WristRally")
        service = MatchService(FileMatchStore(filesDir))
        session = MatchSessionCoordinator(
            service = service,
            workoutManager = HealthServicesWorkoutManager(this),
            tipStore = SharedPreferencesTipStore.create(this),
            serveStore = SharedPreferencesStore.create(this),
        )
        syncCoordinator = MatchSyncCoordinator(
            service = service,
            isWatch = true,
            transport = DataLayerTransport.create(this),
        )
    }
}
