package com.bankerise.sea.core

/**
 * Sanitizes a live page title for header display: single line, max 64
 * characters, never interpreted as markup (it is only ever set as
 * `TextView.text`, never HTML).
 */
internal object SEATitleSanitizer {
    private const val MAX_LENGTH = 64

    fun sanitize(raw: String?): String? {
        if (raw == null) return null
        val singleLine = raw
            .replace("\r\n", " ")
            .replace("\n", " ")
            .replace("\r", " ")
        val trimmed = singleLine.trim()
        if (trimmed.isEmpty()) return null
        return if (trimmed.length > MAX_LENGTH) {
            trimmed.take(MAX_LENGTH)
        } else {
            trimmed
        }
    }
}
