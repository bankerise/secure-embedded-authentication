package com.bankerise.sea.demo.model

import android.content.Context
import android.content.SharedPreferences
import com.bankerise.sea.core.SEACapturePolicy
import com.bankerise.sea.core.SEAConfig
import com.bankerise.sea.core.SEAPresentation
import android.net.Uri

/**
 * SharedPreferences-backed tester-facing configuration for the demo harness.
 *
 * This is harness state only — it has no bearing on SEACore's own security
 * posture. `allowedDomains` here is the *host-supplied narrowing list* that
 * SEACore intersects with its compiled [com.bankerise.sea.core.SEAEnvironment.authDomains]
 * — it can never widen what the core accepts.
 */
class AppSettings private constructor(context: Context) {

    private val prefs: SharedPreferences =
        context.applicationContext.getSharedPreferences("sea_demo", Context.MODE_PRIVATE)

    var gatewayBaseUrl: String
        get() = prefs.getString(KEY_GATEWAY_BASE_URL, DEFAULTS.gatewayBaseUrl) ?: DEFAULTS.gatewayBaseUrl
        set(value) = prefs.edit().putString(KEY_GATEWAY_BASE_URL, value).apply()

    var callbackScheme: String
        get() = prefs.getString(KEY_CALLBACK_SCHEME, DEFAULTS.callbackScheme) ?: DEFAULTS.callbackScheme
        set(value) = prefs.edit().putString(KEY_CALLBACK_SCHEME, value).apply()

    var allowedDomains: String
        get() = prefs.getString(KEY_ALLOWED_DOMAINS, DEFAULTS.allowedDomains) ?: DEFAULTS.allowedDomains
        set(value) = prefs.edit().putString(KEY_ALLOWED_DOMAINS, value).apply()

    var presentation: String
        get() = prefs.getString(KEY_PRESENTATION, DEFAULTS.presentation) ?: DEFAULTS.presentation
        set(value) = prefs.edit().putString(KEY_PRESENTATION, value).apply()

    var timeoutMs: Long
        get() = prefs.getLong(KEY_TIMEOUT_MS, DEFAULTS.timeoutMs)
        set(value) = prefs.edit().putLong(KEY_TIMEOUT_MS, value).apply()

    var useMockGateway: Boolean
        get() = prefs.getBoolean(KEY_USE_MOCK_GATEWAY, DEFAULTS.useMockGateway)
        set(value) = prefs.edit().putBoolean(KEY_USE_MOCK_GATEWAY, value).apply()

    var mockRedirectUrl: String
        get() = prefs.getString(KEY_MOCK_REDIRECT_URL, DEFAULTS.mockRedirectUrl) ?: DEFAULTS.mockRedirectUrl
        set(value) = prefs.edit().putString(KEY_MOCK_REDIRECT_URL, value).apply()

    /**
     * Comma list → trimmed, non-empty array, in the shape
     * [SEAConfig.allowedDomains] expects.
     */
    val allowedDomainsArray: List<String>
        get() = allowedDomains
            .split(",")
            .map { it.trim() }
            .filter { it.isNotEmpty() }

    fun toSEAConfig(authorizeUrl: Uri): SEAConfig {
        val pres = try {
            SEAPresentation.valueOf(presentation.uppercase())
        } catch (_: Exception) { SEAPresentation.SHEET }

        return SEAConfig(
            authorizeUrl = authorizeUrl,
            callbackScheme = callbackScheme,
            allowedDomains = allowedDomainsArray,
            presentation = pres,
            timeoutMs = timeoutMs
        )
    }

    companion object {
        @Volatile
        private var instance: AppSettings? = null

        fun getInstance(context: Context): AppSettings {
            return instance ?: synchronized(this) {
                instance ?: AppSettings(context).also { instance = it }
            }
        }

        private object KEYS {
            const val GATEWAY_BASE_URL = "sea.demo.gatewayBaseURL"
            const val CALLBACK_SCHEME = "sea.demo.callbackScheme"
            const val ALLOWED_DOMAINS = "sea.demo.allowedDomains"
            const val PRESENTATION = "sea.demo.presentation"
            const val TIMEOUT_MS = "sea.demo.timeoutMs"
            const val USE_MOCK_GATEWAY = "sea.demo.useMockGateway"
            const val MOCK_REDIRECT_URL = "sea.demo.mockRedirectURL"
        }
        private const val KEY_GATEWAY_BASE_URL = KEYS.GATEWAY_BASE_URL
        private const val KEY_CALLBACK_SCHEME = KEYS.CALLBACK_SCHEME
        private const val KEY_ALLOWED_DOMAINS = KEYS.ALLOWED_DOMAINS
        private const val KEY_PRESENTATION = KEYS.PRESENTATION
        private const val KEY_TIMEOUT_MS = KEYS.TIMEOUT_MS
        private const val KEY_USE_MOCK_GATEWAY = KEYS.USE_MOCK_GATEWAY
        private const val KEY_MOCK_REDIRECT_URL = KEYS.MOCK_REDIRECT_URL

        private object DEFAULTS {
            const val gatewayBaseUrl = "https://auth-retail.demo.proxym-it.net"
            const val callbackScheme = "bankerise-auth"
            const val allowedDomains = "auth.bank.local,localhost,10.0.2.2,auth-retail.demo.proxym-it.net"
            const val presentation = "SHEET"
            const val timeoutMs = 120_000L
            const val useMockGateway = true
            const val mockRedirectUrl =
                "https://auth-retail.demo.proxym-it.net/realms/uib-qa-front/protocol/openid-connect/auth?response_type=code&client_id=Customer&scope=openid%20profile%20offline_access&state=GJlqE4BlC6kXKhNulrnrDmekbB2JC9JqL5N_sjL8K_s%3D&redirect_uri=http://uib-ebanking.test.proxym-it.tn/login/oauth2/code/Customer&nonce=Yotlp0gGrSVk5VHXJVWYsRtuiKl8BiOvSdbSLXgx0X8&code_challenge=Y_urVAne_932wZU8z6XrZrCg5l9Q4eOfron0Cma67bU&code_challenge_method=S256&ui_locales=fr&mode=light"
        }
    }
}
