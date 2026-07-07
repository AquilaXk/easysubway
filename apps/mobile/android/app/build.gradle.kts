import org.gradle.api.GradleException

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

val releaseSigningValueNames = listOf(
    "EASYSUBWAY_ANDROID_KEYSTORE_PATH",
    "EASYSUBWAY_ANDROID_STORE_PASSWORD",
    "EASYSUBWAY_ANDROID_KEY_ALIAS",
    "EASYSUBWAY_ANDROID_KEY_PASSWORD",
)

fun releaseSigningValue(name: String): String? {
    return providers.gradleProperty(name)
        .orElse(providers.environmentVariable(name))
        .orNull
        ?.trim()
        ?.takeIf { it.isNotEmpty() }
}

val releaseBuildRequested = gradle.startParameter.taskNames.any { taskName ->
    taskName.contains("Release", ignoreCase = true)
}
val missingReleaseSigningValues = releaseSigningValueNames.filter { releaseSigningValue(it) == null }
if (releaseBuildRequested && missingReleaseSigningValues.isNotEmpty()) {
    throw GradleException(
        "Android release signing values are missing: ${missingReleaseSigningValues.joinToString()}. " +
            "Set them as Gradle properties or environment variables before building a release artifact.",
    )
}

android {
    namespace = "com.easysubway.easysubway_mobile"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
        // flutter_local_notifications(하차 알림 #1766)가 java.time API를 써서
        // core library desugaring을 요구한다.
        isCoreLibraryDesugaringEnabled = true
    }

    defaultConfig {
        applicationId = "com.easysubway.app"
        minSdk = flutter.minSdkVersion
        targetSdk = maxOf(35, flutter.targetSdkVersion)
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        create("release") {
            releaseSigningValue("EASYSUBWAY_ANDROID_KEYSTORE_PATH")?.let {
                storeFile = file(it)
            }
            storePassword = releaseSigningValue("EASYSUBWAY_ANDROID_STORE_PASSWORD")
            keyAlias = releaseSigningValue("EASYSUBWAY_ANDROID_KEY_ALIAS")
            keyPassword = releaseSigningValue("EASYSUBWAY_ANDROID_KEY_PASSWORD")
        }
    }

    buildTypes {
        release {
            signingConfig = signingConfigs.getByName("release")
        }
    }
}

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}

flutter {
    source = "../.."
}

dependencies {
    implementation("androidx.core:core-ktx:1.18.0")
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")
}
