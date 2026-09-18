package com.bankerise.sea.core

import android.os.Looper

/**
 * Threading guard for SEACore's public API (contract §2, spec §4.7 — normative).
 *
 * All public API is main-thread-only. Every public entry point begins with
 * [assertMain]. In debug builds this throws [IllegalStateException]; in
 * release builds the check compiles away via `BuildConfig.DEBUG` gating.
 */
object SEAThread {
    fun assertMain() {
        if (BuildConfig.DEBUG) {
            check(Looper.myLooper() == Looper.getMainLooper()) {
                "SEACore API must be called from the main thread"
            }
        }
    }
}
