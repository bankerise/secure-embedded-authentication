package com.bankerise.sea.demo.model

import com.bankerise.sea.core.SEAEvent
import com.bankerise.sea.core.SEATelemetrySink

/**
 * In-memory telemetry event store for the demo harness. Events are
 * retained for display in the Telemetry screen and for export.
 */
class TelemetryStore private constructor() : SEATelemetrySink {

    private val _events = mutableListOf<SEAEvent>()
    val events: List<SEAEvent> get() = _events.toList()

    private val listeners = mutableListOf<() -> Unit>()

    override fun record(event: SEAEvent) {
        _events.add(event)
        listeners.forEach { it() }
    }

    fun addListener(listener: () -> Unit) {
        listeners.add(listener)
    }

    fun removeListener(listener: () -> Unit) {
        listeners.remove(listener)
    }

    fun clear() {
        _events.clear()
        listeners.forEach { it() }
    }

    fun allEventsAsText(): String {
        return _events.joinToString("\n") { event ->
            val props = event.properties.entries.joinToString(", ") { "${it.key}=${it.value}" }
            "${event.name} {$props}"
        }
    }

    companion object {
        val shared = TelemetryStore()
    }
}
