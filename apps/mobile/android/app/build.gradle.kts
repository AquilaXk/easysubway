import org.gradle.api.GradleException

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// 키 파일은 리포 커밋 금지(.gitignore). CI/로컬 시크릿으로 주입된 경우에만 플러그인 적용.
val googleServicesFile = file("google-services.json")
if (googleServicesFile.exists()) {
    apply(plugin = "com.google.gms.google-services")
    apply(plugin = "com.google.firebase.crashlytics")
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

// AGP UTP 내부 구성(_internal-unified-test-platform-*) transitive 보안 패치 강제(#2459).
// APK runtime이 아니라 빌드/테스트 classpath 전용이다.
configurations.configureEach {
    resolutionStrategy {
        force("org.bouncycastle:bcprov-jdk18on:1.84")
        force("org.bouncycastle:bcpkix-jdk18on:1.84")
        force("org.bouncycastle:bcutil-jdk18on:1.84")
        force("io.netty:netty-buffer:4.1.136.Final")
        force("io.netty:netty-codec:4.1.136.Final")
        force("io.netty:netty-codec-http:4.1.136.Final")
        force("io.netty:netty-codec-http2:4.1.136.Final")
        force("io.netty:netty-codec-socks:4.1.136.Final")
        force("io.netty:netty-common:4.1.136.Final")
        force("io.netty:netty-handler:4.1.136.Final")
        force("io.netty:netty-handler-proxy:4.1.136.Final")
        force("io.netty:netty-resolver:4.1.136.Final")
        force("io.netty:netty-transport:4.1.136.Final")
        force("io.netty:netty-transport-native-unix-common:4.1.136.Final")
        force("com.google.protobuf:protobuf-java:3.25.5")
        force("com.google.protobuf:protobuf-kotlin:3.25.5")
        force("org.apache.commons:commons-lang3:3.18.0")
        force("org.apache.httpcomponents:httpclient:4.5.13")
        // Flutter integration-test의 오래된 test-only transitive 보안 버전을 고정한다.
        force("com.google.guava:guava:32.0.0-android", "junit:junit:4.13.2")
    }
}

dependencies {
    implementation("com.google.android.play:integrity:1.6.0")
    implementation("androidx.core:core-ktx:1.18.0")
    implementation("androidx.work:work-runtime:2.10.2")
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")
}
