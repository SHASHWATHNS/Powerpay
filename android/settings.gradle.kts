pluginManagement {
    val flutterSdkPath = run {
        val props = java.util.Properties()
        file("local.properties").inputStream().use { props.load(it) }
        val path = props.getProperty("flutter.sdk")
        require(path != null) { "flutter.sdk not set in local.properties" }
        path
    }

    includeBuild("$flutterSdkPath/packages/flutter_tools/gradle")

    repositories {
        google()
        mavenCentral()
        gradlePluginPortal()
        // (optional) also expose flutter repo to plugin resolution, harmless
        maven { url = uri("https://storage.googleapis.com/download.flutter.io") }
    }
}

dependencyResolutionManagement {
    // Prefer the settings-defined repos for all subprojects
    repositoriesMode.set(RepositoriesMode.PREFER_SETTINGS)
    repositories {
        google()
        mavenCentral()
        // ⬅️ REQUIRED so Gradle can fetch io.flutter artifacts
        maven { url = uri("https://storage.googleapis.com/download.flutter.io") }
    }
}

plugins {
    id("dev.flutter.flutter-plugin-loader") version "1.0.0"
    id("com.android.application") version "8.7.0" apply false
    // Kotlin 2.x is now recommended by Flutter (warning you saw)
    id("org.jetbrains.kotlin.android") version "2.1.0" apply false
    id("com.google.gms.google-services") version "4.4.3" apply false
}

include(":app")
