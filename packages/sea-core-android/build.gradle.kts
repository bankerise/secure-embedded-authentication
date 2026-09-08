plugins {
    id("com.android.library")
    id("org.jetbrains.kotlin.android")
    id("maven-publish")
}

android {
    namespace = "com.bankerise.sea.core"
    compileSdk = 35

    defaultConfig {
        minSdk = 24

        testInstrumentationRunner = "androidx.test.runner.AndroidJUnitRunner"
        consumerProguardFiles("consumer-rules.pro")

        // Manifest placeholder for the callback scheme — host app overrides
        // this with its own scheme in its build.gradle.kts.
        manifestPlaceholders["seaCallbackScheme"] = "sea-default-callback"
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
        }
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

// Distribution: published via JitPack, resolving this repo's git tags —
// mirrors sea-core-ios's podspec (:git/:tag source), since neither requires
// us to push artifacts anywhere. JitPack builds this module on demand the
// first time a consumer requests a given tag (see infra/README.md and
// jitpack.yml at the repo root). The groupId matches the coordinate JitPack
// serves this under (com.github.<user>.<repo>) so a local
// `publishToMavenLocal` lands at the same path a real consumer resolves.
publishing {
    publications {
        create<MavenPublication>("release") {
            groupId = "com.github.bankerise.secure-embedded-authentication"
            artifactId = "sea-core-android"
            // JitPack sets VERSION to the git tag being built (with "/"
            // replaced by "~"); this fallback only matters for a manual
            // `./gradlew publishToMavenLocal` outside of a JitPack build.
            version = System.getenv("VERSION") ?: "0.0.1-local"

            afterEvaluate {
                from(components["release"])
            }
        }
    }
}
