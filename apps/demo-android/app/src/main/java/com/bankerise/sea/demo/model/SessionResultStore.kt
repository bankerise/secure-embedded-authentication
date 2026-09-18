package com.bankerise.sea.demo.model

import com.bankerise.sea.core.SEACallbackParams
import com.bankerise.sea.core.SEAError

/**
 * Stores the last session's terminal outcome for display in the Result screen.
 */
class SessionResultStore private constructor() {

    sealed class Result {
        data class Captured(val params: SEACallbackParams) : Result()
        object Cancelled : Result()
        data class Failed(val error: SEAError) : Result()
    }

    var lastResult: Result? = null
        private set

    private val listeners = mutableListOf<() -> Unit>()

    fun onCaptured(params: SEACallbackParams) {
        lastResult = Result.Captured(params)
        listeners.forEach { it() }
    }

    fun onCancelled() {
        lastResult = Result.Cancelled
        listeners.forEach { it() }
    }

    fun onError(error: SEAError) {
        lastResult = Result.Failed(error)
        listeners.forEach { it() }
    }

    fun addListener(listener: () -> Unit) {
        listeners.add(listener)
    }

    fun removeListener(listener: () -> Unit) {
        listeners.remove(listener)
    }

    companion object {
        val shared = SessionResultStore()
    }
}
