package com.bankerise.sea.demo.networking

import android.net.Uri
import org.json.JSONObject
import java.io.BufferedReader
import java.io.InputStreamReader
import java.io.OutputStreamWriter
import java.net.HttpURLConnection
import java.net.URL

/**
 * Real implementation of the §6.1 two-hop gateway start sequence:
 *
 *   1. POST {baseURL}/authorization/start  -> { redirect, authMode, provider }
 *   2. GET  {redirect}                     -> { redirectUrl, provider }
 *          + Set-Cookie: SESSION (pre-auth), landing in the NATIVE cookie jar
 *
 * Per §6.5, the pre-auth SESSION cookie must be retained in this native jar
 * and must NEVER be handed to the WebView.
 *
 * Uses [HttpURLConnection] to avoid adding OkHttp as a dependency.
 */
class GatewayClient(private val baseUrl: String) : AuthGateway {

    override suspend fun startAuthorization(locale: String?): GatewayStartResult {
        // Hop 1: POST /authorization/start
        val startResponse = postAuthorizationStart(locale)
        // Hop 2: GET {redirect}
        val redirectResponse = getRedirect(startResponse.redirect)

        val finalUrl = Uri.parse(redirectResponse.redirectUrl)
            ?: throw GatewayError("Malformed redirectUrl: ${redirectResponse.redirectUrl}")

        return GatewayStartResult(
            redirectUrl = finalUrl,
            authMode = startResponse.authMode,
            provider = redirectResponse.provider
        )
    }

    private data class StartResponse(
        val redirect: String,
        val authMode: String,
        val provider: String
    )

    private data class RedirectResponse(
        val redirectUrl: String,
        val provider: String
    )

    private fun postAuthorizationStart(locale: String?): StartResponse {
        val url = URL("$baseUrl/authorization/start")
        val conn = (url.openConnection() as HttpURLConnection).apply {
            requestMethod = "POST"
            setRequestProperty("Content-Type", "application/json")
            doOutput = true
            connectTimeout = 15_000
            readTimeout = 15_000
        }

        try {
            val body = JSONObject().apply {
                if (locale != null) put("locale", locale)
            }
            OutputStreamWriter(conn.outputStream).use { it.write(body.toString()) }

            val responseCode = conn.responseCode
            if (responseCode !in 200..299) {
                val errorBody = BufferedReader(InputStreamReader(conn.errorStream)).use { it.readText() }
                throw GatewayError("Gateway returned HTTP $responseCode: $errorBody")
            }

            val json = JSONObject(BufferedReader(InputStreamReader(conn.inputStream)).use { it.readText() })
            return StartResponse(
                redirect = json.getString("redirect"),
                authMode = json.optString("authMode", "EMBEDDED"),
                provider = json.optString("provider", "gw")
            )
        } finally {
            conn.disconnect()
        }
    }

    private fun getRedirect(redirect: String): RedirectResponse {
        val url = if (redirect.startsWith("http")) {
            URL(redirect)
        } else {
            URL(URL(baseUrl), redirect)
        }

        val conn = (url.openConnection() as HttpURLConnection).apply {
            requestMethod = "GET"
            connectTimeout = 15_000
            readTimeout = 15_000
        }

        try {
            val responseCode = conn.responseCode
            if (responseCode !in 200..299) {
                val errorBody = BufferedReader(InputStreamReader(conn.errorStream)).use { it.readText() }
                throw GatewayError("Gateway returned HTTP $responseCode: $errorBody")
            }

            val json = JSONObject(BufferedReader(InputStreamReader(conn.inputStream)).use { it.readText() })
            return RedirectResponse(
                redirectUrl = json.getString("redirectUrl"),
                provider = json.optString("provider", "gw")
            )
        } finally {
            conn.disconnect()
        }
    }
}
