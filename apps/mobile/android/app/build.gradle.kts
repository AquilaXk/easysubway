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

// AGP UTP 내부 구성(_internal-unified-test-platform-gradle-work-action)이 끌어오는
// bcprov 1.79의 GHSA-574f-3g2m-x479(CVE-2025-14813) 해소 — 권고 최소 패치 1.80.2 강제.
// bcpkix·bcutil은 bcprov와 버전 정합을 위해 함께 맞춘다.
configurations.configureEach {
    resolutionStrategy {
        force("org.bouncycastle:bcprov-jdk18on:1.80.2")
        force("org.bouncycastle:bcpkix-jdk18on:1.80.2")
        force("org.bouncycastle:bcutil-jdk18on:1.80.2")
    }
}

dependencies {
    implementation("androidx.core:core-ktx:1.18.0")
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")
}
