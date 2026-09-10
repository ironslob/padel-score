package com.wristrally.sync

/** Delivers Data Layer payloads without exposing Play services to tests. */
interface SyncTransport {
    fun setListener(listener: (path: String, payload: ByteArray, fromLocalNode: Boolean) -> Unit)
    fun publish(path: String, payload: ByteArray)
    fun sendMessage(path: String, payload: ByteArray)
}

class NoOpSyncTransport : SyncTransport {
    override fun setListener(listener: (path: String, payload: ByteArray, fromLocalNode: Boolean) -> Unit) {}
    override fun publish(path: String, payload: ByteArray) {}
    override fun sendMessage(path: String, payload: ByteArray) {}
}

interface WristRallySyncHost {
    val syncCoordinator: MatchSyncCoordinator
}
