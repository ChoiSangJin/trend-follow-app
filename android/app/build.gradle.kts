import java.util.Properties

plugins {
    id("com.android.application")
    id("org.jetbrains.kotlin.android")
    id("dev.flutter.flutter-gradle-plugin")
}

val splitPerAbi = project.findProperty("split-per-abi")?.toString()?.toBoolean() == true
if (splitPerAbi) {
    require(project.findProperty("target-platform")?.toString() == "android-arm64") {
        "ARM64 only: use --split-per-abi --target-platform=android-arm64"
    }
}

val signingFile = rootProject.file("key.properties")
val releaseSigning = Properties()
if (signingFile.exists()) signingFile.inputStream().use { releaseSigning.load(it) }
val hasReleaseSigning = listOf("storeFile", "storePassword", "keyAlias", "keyPassword")
    .all { !releaseSigning.getProperty(it).isNullOrBlank() }
if (gradle.startParameter.taskNames.any { it.contains("release", ignoreCase = true) }) {
    require(hasReleaseSigning) {
        "Release signing required: configure android/key.properties (see README.md)."
    }
}

android {
    namespace = "com.malmun.app"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion
    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }
    defaultConfig {
        applicationId = "com.malmun.app"
        minSdk = 24
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
        // AGP rejects ndk.abiFilters together with --split-per-abi.
        // In split mode Flutter uses --target-platform=android-arm64 instead.
        if (!splitPerAbi) {
            ndk {
                abiFilters.clear()
                abiFilters += "arm64-v8a"
            }
        }
    }
    signingConfigs {
        if (hasReleaseSigning) {
            create("release") {
                storeFile = rootProject.file(releaseSigning.getProperty("storeFile"))
                storePassword = releaseSigning.getProperty("storePassword")
                keyAlias = releaseSigning.getProperty("keyAlias")
                keyPassword = releaseSigning.getProperty("keyPassword")
            }
        }
    }
    buildTypes {
        release {
            if (hasReleaseSigning) signingConfig = signingConfigs.getByName("release")
        }
    }
}

kotlin {
    compilerOptions { jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17 }
}
flutter { source = "../.." }
