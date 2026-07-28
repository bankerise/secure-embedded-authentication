plugins {
    id("com.android.library")
    id("org.jetbrains.kotlin.android")
    id("com.facebook.react")
}

android {
    namespace = "com.bankerise.seareactnative"
    compileSdk = 35

    defaultConfig {
        minSdk = 26

        // ── Security config (equivalent of iOS SEASecurityConfig.plist) ──
        // §6.2/§7.1: compiled callback scheme for the OAuth redirect.
        // Host app overrides by redefining these buildConfigField values in
        // its own app/build.gradle.kts defaultConfig block — same pattern
        // as the plist in the iOS host app bundle.
        buildConfigField(
            "String",
            "BRIDGE_CALLBACK_SCHEME",
            "\"bankerise-auth\""
        )
        // §6.2: compiled auth-domain allowlist. These are the default
        // domains available for React Native bridge sessions. The core
        // library's SEAEnvironment.current provides the authoritative
        // compiled allowlist for validation; these mirror the plist's
        // AuthDomains array for the bridge layer.
        buildConfigField(
            "String[]",
            "BRIDGE_AUTH_DOMAINS",
            """{"auth.bank.com"}"""
        )
    }

    buildTypes {
        release {
            isMinifyEnabled = false
        }
        debug {
            // DEV ONLY — mirrors infra/ local Keycloak and remote dev
            // instances. Compiled out of any release configuration.
            buildConfigField(
                "String[]",
                "BRIDGE_AUTH_DOMAINS",
                """{"auth.bank.com", "auth-staging.bank.com", "localhost", "auth.bank.local", "10.0.2.2", "auth-retail.demo.proxym-it.net"}"""
            )
        }
    }

    buildFeatures {
        buildConfig = true
    }

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    kotlinOptions {
        jvmTarget = "17"
    }
}

dependencies {
    implementation(project(":sea-core-android"))
    implementation("com.facebook.react:react-android:+")
}
