pluginManagement {
    repositories {
        google()
        mavenCentral()
        gradlePluginPortal()
    }
}

dependencyResolutionManagement {
    repositoriesMode.set(RepositoriesMode.FAIL_ON_PROJECT_REPOS)
    repositories {
        google()
        mavenCentral()
    }
}

rootProject.name = "bankerise-sea-demo"

include(":app")
include(":sea-core-android")
project(":sea-core-android").projectDir = file("../../packages/sea-core-android")
