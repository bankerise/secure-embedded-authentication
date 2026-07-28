package com.bankerise.sea.core

/**
 * A single telemetry event (contract §3.6, spec §20.1).
 */
data class SEAEvent(
    val name: String,
    val properties: Map<String, String> = emptyMap(),
    val timestamp: Long = System.currentTimeMillis()
)

/**
 * Host-supplied telemetry sink. [record] is always called on the main thread.
 */
interface SEATelemetrySink {
    fun record(event: SEAEvent)
}
