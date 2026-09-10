package com.wristrally.phone

import android.app.Application
import com.wristrally.domain.FileMatchStore
import com.wristrally.domain.MatchService
import com.wristrally.sync.DataLayerTransport
import com.wristrally.sync.MatchSyncCoordinator
import com.wristrally.sync.WristRallySyncHost

class WristRallyPhoneApp : Application(), WristRallySyncHost {
    lateinit var service: MatchService
        private set
    override lateinit var syncCoordinator: MatchSyncCoordinator
        private set
    lateinit var liveNotification: MatchLiveNotificationManager
        private set

    override fun onCreate() {
        super.onCreate()
        val store = FileMatchStore(filesDir.toPath().resolve("WristRally"))
        service = MatchService(store, autoRestore = false)
        service.restore()
        syncCoordinator = MatchSyncCoordinator(
            service = service,
            isWatch = false,
            transport = DataLayerTransport.create(this),
        )
        liveNotification = MatchLiveNotificationManager(this)
        service.addListener { liveNotification.sync(service.activeMatch) }
        liveNotification.sync(service.activeMatch)
    }
}
