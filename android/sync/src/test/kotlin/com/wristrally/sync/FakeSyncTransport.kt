package com.wristrally.sync

class FakeSyncTransport : SyncTransport {
    val published = mutableListOf<Pair<String, ByteArray>>()
    val messages = mutableListOf<Pair<String, ByteArray>>()
    private var listener: ((String, ByteArray, Boolean) -> Unit)? = null

    override fun setListener(listener: (path: String, payload: ByteArray, fromLocalNode: Boolean) -> Unit) {
        this.listener = listener
    }

    override fun publish(path: String, payload: ByteArray) {
        published += path to payload
    }

    override fun sendMessage(path: String, payload: ByteArray) {
        messages += path to payload
    }

    fun deliver(path: String, payload: ByteArray, fromLocalNode: Boolean = false) {
        listener?.invoke(path, payload, fromLocalNode)
    }
}
