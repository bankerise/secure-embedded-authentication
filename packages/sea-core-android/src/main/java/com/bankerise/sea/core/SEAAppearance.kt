package com.bankerise.sea.core

import androidx.annotation.ColorInt

/**
 * SDK-controlled appearance (contract §3.2, spec §18.1).
 *
 * Colors and text only. There is no layout injection here, and nothing in
 * this type is ever used to touch, restyle, or overlay web content (§13).
 */
data class SEAAppearance(
    @ColorInt val headerBackground: Int,
    @ColorInt val headerText: Int,
    @ColorInt val accent: Int,
    @ColorInt val closeIconTint: Int,
    val cornerRadius: Float,
    /** `null` means the header falls back to the live page title (contract §9). */
    val title: String? = null,
    val showsGrabber: Boolean = true,
    /** Top offset in dp between the device status bar and the sheet edge (§18.1). */
    val sheetTopOffset: Float = 64f
) {
    companion object {
        val default = SEAAppearance(
            headerBackground = 0xFFFAFAFA.toInt(),  // Light surface
            headerText = 0xFF212121.toInt(),          // On-surface
            accent = 0xFF1976D2.toInt(),              // Blue 700
            closeIconTint = 0xFF757575.toInt(),       // Grey 600
            cornerRadius = 28f,                        // Material bottom-sheet default
            title = null,
            showsGrabber = true,
            sheetTopOffset = 64f
        )
    }
}
