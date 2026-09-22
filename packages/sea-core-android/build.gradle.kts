import com.vanniktech.maven.publish.AndroidSingleVariantLibrary

plugins {
    id("com.android.library")
    id("org.jetbrains.kotlin.android")
    id("com.vanniktech.maven.publish")
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
        // Robolectric needs merged resources for tests that touch android.*
        unitTests.isIncludeAndroidResources = true
    }
}

dependencies {
    implementation("androidx.core:core-ktx:1.15.0")
    implementation("androidx.appcompat:appcompat:1.7.0")
    implementation("com.google.android.material:material:1.12.0")

    testImplementation("junit:junit:4.13.2")
    testImplementation("org.jetbrains.kotlin:kotlin-test-junit:2.0.21")
    testImplementation("org.robolectric:robolectric:4.14.1")
    testImplementation("org.mockito:mockito-core:5.14.2")
}

// Distribution: published to Maven Central (Central Portal, namespace
// com.bankerise) by .github/workflows/sea-core-android.yml on a
// `sea-core-android/X.Y.Z` tag. The version comes from the tag via
// -PseaVersion; the default below is only used for local builds.
//
// Local smoke test (unsigned, no credentials needed):
//   cd apps/demo-android && ./gradlew :sea-core-android:publishToMavenLocal
val seaVersion = providers.gradleProperty("seaVersion").getOrElse("0.0.1-SNAPSHOT")

mavenPublishing {
    configure(AndroidSingleVariantLibrary(variant = "release", sourcesJar = true, publishJavadocJar = true))

    publishToMavenCentral(automaticRelease = true)

    // Central rejects unsigned artifacts, but local publishToMavenLocal
    // runs shouldn't need a GPG key — sign only when CI provides one.
    if (providers.gradleProperty("signingInMemoryKey").isPresent) {
        signAllPublications()
    }

    coordinates("com.bankerise", "sea-core-android", seaVersion)

    pom {
        name.set("Bankerise SEA Core (Android)")
        description.set("Bankerise SEA — hardened embedded WebView authentication core for Android.")
        inceptionYear.set("2026")
        url.set("https://github.com/bankerise/secure-embedded-authentication")
        licenses {
            license {
                name.set("MIT License")
                url.set("https://opensource.org/licenses/MIT")
                distribution.set("repo")
            }
        }
        developers {
            developer {
                id.set("bankerise")
                name.set("Bankerise")
                url.set("https://bankerise.com")
            }
        }
        scm {
            url.set("https://github.com/bankerise/secure-embedded-authentication")
            connection.set("scm:git:https://github.com/bankerise/secure-embedded-authentication.git")
            developerConnection.set("scm:git:ssh://git@github.com/bankerise/secure-embedded-authentication.git")
        }
    }
}
