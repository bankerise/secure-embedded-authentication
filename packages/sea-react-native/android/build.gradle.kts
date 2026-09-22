plugins {
    id("com.android.library")
    id("org.jetbrains.kotlin.android")
    id("com.facebook.react")
}

android {
    namespace = "com.bankerise.seareactnative"
    compileSdk = 35

    defaultConfig {
        minSdk = 24
    }

    buildTypes {
        release {
            isMinifyEnabled = false
        }
        debug {
        }
    }

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    kotlinOptions {
        jvmTarget = "17"
    }
}

// sea-core-android is resolved from Maven Central (com.bankerise), which
// every React Native app already declares — no extra repository or
// credentials needed on the consumer side. Published by
// .github/workflows/sea-core-android.yml.
val seaCoreAndroidVersion = "0.0.1"

dependencies {
    implementation("com.bankerise:sea-core-android:$seaCoreAndroidVersion")
    implementation("com.facebook.react:react-android:+")
}
