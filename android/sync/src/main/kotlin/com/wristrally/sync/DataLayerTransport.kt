package com.wristrally.sync

import android.content.Context
import android.net.Uri
import com.google.android.gms.common.ConnectionResult
import com.google.android.gms.common.GoogleApiAvailability
import com.google.android.gms.wearable.CapabilityClient
import com.google.android.gms.wearable.DataClient
import com.google.android.gms.wearable.DataEvent
import com.google.android.gms.wearable.DataMapItem
import com.google.android.gms.wearable.MessageClient
import com.google.android.gms.wearable.PutDataMapRequest
import com.google.android.gms.wearable.Wearable
import java.util.logging.Logger
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.launch
import kotlinx.coroutines.tasks.await

class DataLayerTransport(
    context: Context,
    private val scope: CoroutineScope = CoroutineScope(SupervisorJob() + Dispatchers.Main.immediate),
) : SyncTransport {
    private val appContext = context.applicationContext
    private val logger = Logger.getLogger("com.wristrally.sync")
    private val dataClient: DataClient = Wearable.getDataClient(appContext)
    private val messageClient: MessageClient = Wearable.getMessageClient(appContext)
    private val capabilityClient: CapabilityClient = Wearable.getCapabilityClient(appContext)
    private val nodeClient = Wearable.getNodeClient(appContext)

    private var listener: ((String, ByteArray, Boolean) -> Unit)? = null
    @Volatile private var localNodeId: String? = null

    private val dataListener = DataClient.OnDataChangedListener { buffer ->
        buffer.use { events ->
            for (event in events) {
                if (event.type != DataEvent.TYPE_CHANGED && event.type != DataEvent.TYPE_DELETED) continue
                if (event.type == DataEvent.TYPE_DELETED) continue
                dispatchDataItem(event.dataItem.uri, DataMapItem.fromDataItem(event.dataItem).dataMap.getByteArray(SyncPaths.ENVELOPE_KEY))
            }
        }
    }

    private val messageListener = MessageClient.OnMessageReceivedListener { event ->
        dispatch(event.path, event.data ?: ByteArray(0), fromLocalNode = false)
    }

    override fun setListener(listener: (path: String, payload: ByteArray, fromLocalNode: Boolean) -> Unit) {
        this.listener = listener
        dataClient.addListener(dataListener)
        messageClient.addListener(messageListener)
        scope.launch(Dispatchers.IO) {
            runCatching { localNodeId = nodeClient.localNode.await().id }
        }
    }

    override fun publish(path: String, payload: ByteArray) {
        scope.launch(Dispatchers.IO) {
            runCatching {
                val request = PutDataMapRequest.create(path)
                request.dataMap.putByteArray(SyncPaths.ENVELOPE_KEY, payload)
                dataClient.putDataItem(request.setUrgent().asPutDataRequest()).await()
            }.onFailure { error ->
                logger.warning("Data Layer publish failed: ${error.message}")
            }
        }
    }

    override fun sendMessage(path: String, payload: ByteArray) {
        scope.launch(Dispatchers.IO) {
            runCatching {
                val info = capabilityClient
                    .getCapability(SyncPaths.CAPABILITY, CapabilityClient.FILTER_REACHABLE)
                    .await()
                val local = localNodeId ?: nodeClient.localNode.await().id.also { localNodeId = it }
                for (node in info.nodes) {
                    if (node.id == local) continue
                    messageClient.sendMessage(node.id, path, payload).await()
                }
            }.onFailure { error ->
                logger.warning("Data Layer message failed: ${error.message}")
            }
        }
    }

    fun handleDataItem(uri: Uri, payload: ByteArray?) {
        dispatchDataItem(uri, payload)
    }

    fun handleMessage(path: String, payload: ByteArray) {
        dispatch(path, payload, fromLocalNode = false)
    }

    private fun dispatchDataItem(uri: Uri, payload: ByteArray?) {
        val path = uri.path ?: return
        val bytes = payload ?: return
        val fromLocal = localNodeId != null && uri.host == localNodeId
        dispatch(path, bytes, fromLocal)
    }

    private fun dispatch(path: String, payload: ByteArray, fromLocalNode: Boolean) {
        val callback = listener ?: return
        scope.launch(Dispatchers.Main.immediate) {
            callback(path, payload, fromLocalNode)
        }
    }

    companion object {
        fun create(context: Context): SyncTransport {
            return try {
                val availability = GoogleApiAvailability.getInstance()
                    .isGooglePlayServicesAvailable(context)
                if (availability != ConnectionResult.SUCCESS) {
                    NoOpSyncTransport()
                } else {
                    DataLayerTransport(context)
                }
            } catch (_: Exception) {
                NoOpSyncTransport()
            }
        }
    }
}
