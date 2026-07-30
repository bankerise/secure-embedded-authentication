package com.bankerise.sea.core

import android.content.Context
import java.util.Properties

/**
 * Loads [SEAConfig] from a `bankerise-sea.properties` file in the app's
 * assets. If the file is absent all values fall back to safe defaults
 * (empty strings / empty lists) — the app never crashes.
 *
 * The host app places the file at `src/main/assets/bankerise-sea.properties`
 * (or copies it there at build time). Supported keys:
 *
 *   authorizeUrl       – Full authorize URL (required; validated at session time)
 *   callbackScheme     – Custom scheme for the callback redirect (§6.3)
 *   authDomains        – Comma-separated list of allowed host domains
 *   allowedPorts       – Comma-separated list of allowed ports (-1 = unset)
 *   maxUrlLengthBytes  – Max byte length of the authorize URL string
 */
object SEAPropertiesLoader {

    private const val FILENAME = "bankerise-sea.properties"

    /**
     * Loads all properties from the file, returning a [Properties] object.
     * Never throws; returns an empty [Properties] if the file is missing.
     */
    fun load(context: Context): Properties {
        val props = Properties()
        try {
            context.assets.open(FILENAME).use { stream ->
                props.load(stream)
            }
        } catch (_: Exception) {
            // File not present — safe defaults below.
        }
        return props
    }

    /**
     * Loads properties and builds a [SEAConfig]. All fields that are missing
     * or empty will cause downstream validation to reject the session at
     * start time (fail closed).
     */
    fun loadConfig(context: Context): SEAConfig {
        val props = load(context)
        return SEAConfig(
            authorizeUrl = android.net.Uri.parse(props.getProperty("authorizeUrl", "")),
            callbackScheme = props.getProperty("callbackScheme", ""),
            allowedDomains = parseCommaList(props.getProperty("authDomains", "")),
            allowedPorts = parseCommaList(props.getProperty("allowedPorts", "-1,443"))
                .mapNotNull { it.toIntOrNull() }
                .toSet(),
            maxUrlLengthBytes = props.getProperty("maxUrlLengthBytes", "2048").toIntOrNull() ?: 2048
        )
    }

    private fun parseCommaList(value: String): List<String> {
        if (value.isBlank()) return emptyList()
        return value.split(",").map { it.trim() }.filter { it.isNotEmpty() }
    }
}
