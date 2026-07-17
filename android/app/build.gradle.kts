import java.io.FileInputStream
import java.util.Properties

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// --- Release signing --------------------------------------------------
//
// Release signing credentials are never committed. They come from either:
//   1. android/key.properties (git-ignored; copy android/key.properties.example
//      to create it) for local release builds, or
//   2. CI environment variables: ANDROID_KEYSTORE_PATH, ANDROID_STORE_PASSWORD,
//      ANDROID_KEY_ALIAS, ANDROID_KEY_PASSWORD.
//
// Precedence: a non-empty CI environment value always overrides the value
// from android/key.properties, so a CI run can never silently pick up a
// stale local file. Missing/blank values fall through to the next source.
//
// This block only *reads* files/env vars and never prints their contents.
// Configuration (assembleDebug, test, analyze, etc.) always succeeds even
// when no credentials are present -- only an actual release task
// (any task whose name contains "release", case-insensitively) fails early,
// with a message naming which fields/input channels are missing but never
// echoing a secret value. signingConfigs.release is always what
// buildTypes.release points at; there is no debug-signing fallback and no
// path that produces a silently-unsigned release artifact.
data class ReleaseSigningField(
    val propertyKey: String,
    val envVar: String,
    val description: String,
)

val releaseSigningFields = listOf(
    ReleaseSigningField("storeFile", "ANDROID_KEYSTORE_PATH", "keystore 파일 경로"),
    ReleaseSigningField("storePassword", "ANDROID_STORE_PASSWORD", "keystore 비밀번호"),
    ReleaseSigningField("keyAlias", "ANDROID_KEY_ALIAS", "key alias"),
    ReleaseSigningField("keyPassword", "ANDROID_KEY_PASSWORD", "key 비밀번호"),
)

val keyPropertiesFile = rootProject.file("key.properties")
val keyProperties = Properties()
if (keyPropertiesFile.exists()) {
    FileInputStream(keyPropertiesFile).use { keyProperties.load(it) }
}

fun resolveReleaseSigningValue(field: ReleaseSigningField): String? {
    val envValue = System.getenv(field.envVar)
    if (!envValue.isNullOrBlank()) return envValue
    val localValue = keyProperties.getProperty(field.propertyKey)
    if (!localValue.isNullOrBlank()) return localValue
    return null
}

val resolvedReleaseSigning = releaseSigningFields.associateWith { resolveReleaseSigningValue(it) }

fun releaseSigningValue(propertyKey: String): String? =
    resolvedReleaseSigning.entries.firstOrNull { it.key.propertyKey == propertyKey }?.value

// File(...) resolves both "C:\\keys\\release.jks"-style Windows paths and
// forward-slash CI paths natively; a relative path resolves against the
// android/ directory (this project's rootProject), matching where
// android/key.properties itself lives.
val releaseStoreFilePathValue = releaseSigningValue("storeFile")
val releaseKeystoreFile: File? = releaseStoreFilePathValue?.let { path ->
    val candidate = File(path)
    if (candidate.isAbsolute) candidate else rootProject.file(path)
}

val releaseMissingFields = releaseSigningFields.filter { resolvedReleaseSigning[it] == null }
val releaseKeystoreMissing = releaseKeystoreFile == null || !releaseKeystoreFile.exists()

val requestedTaskNames = gradle.startParameter.taskNames
val isReleaseTaskRequested = requestedTaskNames.any { it.contains("release", ignoreCase = true) }

if (isReleaseTaskRequested && (releaseMissingFields.isNotEmpty() || releaseKeystoreMissing)) {
    val problems = mutableListOf<String>()
    problems.addAll(
        releaseMissingFields.map {
            "${it.propertyKey} (${it.description}; android/key.properties의 '${it.propertyKey}' " +
                "또는 환경변수 \$${it.envVar})"
        },
    )
    if (releaseKeystoreMissing && releaseMissingFields.none { it.propertyKey == "storeFile" }) {
        problems.add(
            "storeFile (keystore 파일 경로; android/key.properties의 'storeFile' 또는 " +
                "환경변수 \$ANDROID_KEYSTORE_PATH)가 가리키는 파일이 존재하지 않습니다",
        )
    }
    throw GradleException(
        "Android 릴리즈 서명이 구성되지 않았습니다. 누락/무효 항목: " +
            problems.joinToString("; ") +
            ". android/key.properties.example를 복사해 android/key.properties(커밋 금지)를 " +
            "채우거나, CI에서는 ANDROID_KEYSTORE_PATH / ANDROID_STORE_PASSWORD / " +
            "ANDROID_KEY_ALIAS / ANDROID_KEY_PASSWORD 환경변수로 주입하세요. " +
            "이 오류 메시지에는 실제 비밀 값을 포함하지 않습니다. " +
            "자세한 절차는 docs/RELEASE_CHECKLIST.md 를 참고하세요.",
    )
}

android {
    namespace = "com.example.human_status"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
        isCoreLibraryDesugaringEnabled = true
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "com.example.human_status"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
        multiDexEnabled = true
    }

    signingConfigs {
        create("release") {
            // Fields stay null when credentials are absent (e.g. `flutter test`,
            // `assembleDebug`); the guard above already fails early for any
            // actual release task before this would matter.
            releaseKeystoreFile?.let { storeFile = it }
            releaseSigningValue("storePassword")?.let { storePassword = it }
            releaseSigningValue("keyAlias")?.let { keyAlias = it }
            releaseSigningValue("keyPassword")?.let { keyPassword = it }
        }
    }

    buildTypes {
        release {
            // Always the dedicated release signing config -- never debug, and
            // never silently unsigned: see the fail-early guard above.
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
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")
}
