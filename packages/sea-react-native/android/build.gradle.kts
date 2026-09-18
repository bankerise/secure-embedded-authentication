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

// sea-core-android ships as a prebuilt AAR bundled directly inside this npm
// package (see packages/sea-core-android/build.gradle.kts's publishing
// block for how it's regenerated) rather than resolved from an external
// Maven host — there's no existing private Android artifact repo in this
// org, so this keeps external consumers at zero extra host, credential, or
// settings.gradle setup, the same as any other RN autolinked native module.
repositories {
    maven { url = uri("$projectDir/local-maven") }
}

dependencies {
    implementation("com.bankerise:sea-core-android:0.0.1")
    implementation("com.facebook.react:react-android:+")
}
