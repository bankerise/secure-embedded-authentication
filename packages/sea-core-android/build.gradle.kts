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
            // Not minified: this AAR is redistributed as a compiled
            // dependency (see the publishing block below), not consumed as
            // monorepo source, so shrinking it here would double-minify
            // ahead of the consuming app's own R8 pass — and there are no
            // -keep rules in proguard-rules.pro for this library's own
            // public API surface (only consumer-rules.pro, which governs
            // consumers' shrinking, not this library's compiled classes).
            isMinifyEnabled = false
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

    buildFeatures {
        buildConfig = true
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

// Distribution: there's no existing private Android Maven host in this org
// (checked retail-mobile's real Gradle config before choosing this — only
// google()/mavenCentral() anywhere), and an external host like GitHub
// Packages would force every consumer to configure a PAT just to resolve a
// transitive dependency. Instead sea-react-native bundles this as a
// prebuilt AAR directly inside its own npm package
// (packages/sea-react-native/android/local-maven/, included via that
// package's "files" array) — zero external host, zero consumer
// credentials, zero settings.gradle edits beyond normal RN autolinking.
//
// Regenerate after any sea-core-android change, then commit the output:
//   cd apps/demo-android && ./gradlew :sea-core-android:publishReleasePublicationToLocalNpmRepository
publishing {
    publications {
        create<MavenPublication>("release") {
            groupId = "com.bankerise"
            artifactId = "sea-core-android"
            version = "0.0.1"

            afterEvaluate {
                from(components["release"])
            }
        }
    }
    repositories {
        maven {
            name = "localNpm"
            url = uri(file("../sea-react-native/android/local-maven"))
        }
    }
}
