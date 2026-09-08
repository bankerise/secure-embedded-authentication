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

// sea-core-android is resolved from JitPack (see infra/README.md), not a
// monorepo-local project reference — this repositories block lets an
// external consumer resolve it purely via autolinking, with no changes to
// their own settings.gradle/build.gradle beyond what autolinking already
// requires for any RN native module.
repositories {
    maven { url = uri("https://jitpack.io") }
}

dependencies {
    // Version string is the git tag "sea-core-android/x.y.z" with "/"
    // replaced by "~", per JitPack's convention for tags containing slashes.
    implementation("com.github.bankerise.secure-embedded-authentication:sea-core-android:sea-core-android~0.0.1")
    implementation("com.facebook.react:react-android:+")
}
