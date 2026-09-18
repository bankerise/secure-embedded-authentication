package com.bankerise.sea.core

import android.content.Context

/**
 * Localized copy for SEA's native UI (contract §9, spec §18.4/§19).
 *
 * All strings are looked up from the core library's resource bundle,
 * never from the host app's resources or from web content.
 */
internal object SEAStrings {

    fun loading(context: Context): String =
        context.getString(R.string.sea_loading)

    fun actionRetry(context: Context): String =
        context.getString(R.string.sea_action_retry)

    fun actionClose(context: Context): String =
        context.getString(R.string.sea_action_close)

    fun captureWarning(context: Context): String =
        context.getString(R.string.sea_capture_warning)

    /**
     * Maps a [SEAError] to the (title, message) pair for the native error
     * state view. Only the error cases reachable in Phase 1 are given
     * distinct copy; [SEAError.WebauthnUnavailable] / [SEAError.KillSwitched]
     * are unreachable and fall back to generic copy.
     */
    fun copyFor(context: Context, error: SEAError): Pair<String, String> {
        return when (error) {
            is SEAError.Network -> Pair(
                context.getString(R.string.sea_error_network_title),
                context.getString(R.string.sea_error_network_message)
            )
            is SEAError.Timeout -> Pair(
                context.getString(R.string.sea_error_timeout_title),
                context.getString(R.string.sea_error_timeout_message)
            )
            is SEAError.ServerError -> Pair(
                context.getString(R.string.sea_error_server_title),
                context.getString(R.string.sea_error_server_message)
            )
            is SEAError.Cancelled,
            is SEAError.InvalidAuthorizeUrl,
            is SEAError.WebauthnUnavailable,
            is SEAError.KillSwitched -> Pair(
                context.getString(R.string.sea_error_generic_title),
                context.getString(R.string.sea_error_generic_message)
            )
        }
    }
}
