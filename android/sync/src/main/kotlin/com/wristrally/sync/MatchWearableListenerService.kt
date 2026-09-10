package com.wristrally.sync

import com.google.android.gms.wearable.DataEvent
import com.google.android.gms.wearable.DataEventBuffer
import com.google.android.gms.wearable.DataMapItem
import com.google.android.gms.wearable.MessageEvent
import com.google.android.gms.wearable.WearableListenerService

/** Applies inbound Data Layer events when the UI process is not in the foreground. */
class MatchWearableListenerService : WearableListenerService() {
    override fun onDataChanged(dataEvents: DataEventBuffer) {
        val coordinator = (application as? WristRallySyncHost)?.syncCoordinator ?: return
        dataEvents.use { events ->
            for (event in events) {
                if (event.type != DataEvent.TYPE_CHANGED) continue
                val item = event.dataItem
                val path = item.uri.path ?: continue
                val payload = DataMapItem.fromDataItem(item).dataMap.getByteArray(SyncPaths.ENVELOPE_KEY)
                    ?: continue
                coordinator.apply(path, payload, fromLocalNode = false)
            }
        }
    }

    override fun onMessageReceived(messageEvent: MessageEvent) {
        val coordinator = (application as? WristRallySyncHost)?.syncCoordinator ?: return
        coordinator.apply(messageEvent.path, messageEvent.data ?: ByteArray(0), fromLocalNode = false)
    }
}
