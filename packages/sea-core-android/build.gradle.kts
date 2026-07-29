plugins {
    id("com.android.library")
    id("org.jetbrains.kotlin.android")
}

android {
    namespace = "com.bankerise.sea.core"
    compileSdk = 35

    defaultConfig {
        minSdk = 26

        testInstrumentationRunner = "androidx.test.runner.AndroidJUnitRunner"
        consumerProguardFiles("consumer-rules.pro")

        // Build-config-selected compiled environment (§7.1, §6.2).
        // mirrors iOS's #if SEA_ENV_PRODUCTION / SEA_ENV_STAGING / #else DEBUG.
        buildConfigField(
            "String[]",
            "COMPILED_AUTH_DOMAINS",
            """{"auth.bank.com"}"""
        )
        buildConfigField("String", "COMPILED_CALLBACK_SCHEME", "\"bankerise-auth\"")
    }

    buildTypes {
        release {
            isMinifyEnabled = true
            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"),
                "proguard-rules.pro"
            )
        }
        debug {
            // DEV ONLY, structurally unable to escape a release build:
            // the local TLS Keycloak (infra/) and the demo harness authenticate
            // against these. BuildConfig.DEBUG is false in any release
            // configuration, so no release binary can ever have these domains.
            buildConfigField(
                "String[]",
                "COMPILED_AUTH_DOMAINS",
                """{"auth.bank.com", "auth-staging.bank.com", "localhost", "auth.bank.local", "10.0.2.2", "auth-retail.demo.proxym-it.net", "platform-keycloak.pres.proxym-it.net"}"""
            )
            buildConfigField("String", "COMPILED_CALLBACK_SCHEME", "\"bkrmob\"")
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

    testOptions {
        unitTests.isReturnDefaultValues = true
    }
}

dependencies {
    implementation("androidx.core:core-ktx:1.15.0")
    implementation("androidx.appcompat:appcompat:1.7.0")
    implementation("com.google.android.material:material:1.12.0")

    testImplementation("junit:junit:4.13.2")
    testImplementation("org.jetbrains.kotlin:kotlin-test-junit:2.0.21")
}
