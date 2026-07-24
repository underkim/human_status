allprojects {
    repositories {
        google()
        mavenCentral()
    }
}

val newBuildDir: Directory =
    rootProject.layout.buildDirectory
        .dir("../../build")
        .get()
rootProject.layout.buildDirectory.value(newBuildDir)

subprojects {
    val newSubprojectBuildDir: Directory = newBuildDir.dir(project.name)
    project.layout.buildDirectory.value(newSubprojectBuildDir)
}

// Some published plugins (e.g. sentry_flutter 8.14.2's own android/build.gradle)
// pin an old explicit Kotlin `languageVersion` (e.g. "1.6") against the
// project-wide Kotlin Gradle Plugin declared in settings.gradle.kts. Newer
// KGP releases (2.2+) dropped support for compiling with such old language
// versions entirely ("Language version 1.6 is no longer supported"), which
// breaks those plugins' own Kotlin sources even though this app's own code
// never asked for language version 1.6. Since we don't control third-party
// plugin sources, normalize every subproject's Kotlin language/API version
// to a version the toolchain still supports -- this only affects how much
// old Kotlin *syntax* the compiler accepts, not JVM bytecode target (each
// subproject/app module keeps its own jvmTarget untouched).
//
// Registered BEFORE `evaluationDependsOn(":app")` below: that call eagerly
// evaluates the `:app` subproject as a side effect of configuring *every*
// other subproject, and Gradle forbids calling `afterEvaluate` on a project
// that has already been evaluated -- so this block must be declared first.
subprojects {
    // `afterEvaluate` is required, not just `plugins.withId`: some plugins
    // (e.g. sentry_flutter) apply the Kotlin plugin near the top of their
    // own build.gradle and only set languageVersion/kotlinOptions further
    // down in that same file. A `plugins.withId` callback registered from
    // the root project fires immediately when the plugin is applied --
    // i.e. before the subproject's own script finishes running -- so its
    // later `languageVersion = "1.6"` would silently overwrite our
    // override again. `afterEvaluate` runs only once the whole subproject
    // build script (including that later line) has already executed.
    afterEvaluate {
        plugins.withId("org.jetbrains.kotlin.android") {
            extensions.configure<org.jetbrains.kotlin.gradle.dsl.KotlinAndroidProjectExtension> {
                compilerOptions {
                    languageVersion.set(org.jetbrains.kotlin.gradle.dsl.KotlinVersion.KOTLIN_2_0)
                    apiVersion.set(org.jetbrains.kotlin.gradle.dsl.KotlinVersion.KOTLIN_2_0)
                }
            }
        }

        // sentry_flutter 8.14.2's own android/build.gradle also hardcodes
        // `compileSdkVersion 34` instead of deferring to the Flutter Gradle
        // plugin's shared `flutter.compileSdkVersion` (as package_info_plus
        // and this app's own :app module do). AGP's "AAR metadata" check
        // then fails the build the moment any *other* dependency (e.g.
        // package_info_plus) requires compiling against a newer Android
        // API than sentry_flutter's own fixed 34. Force every Android
        // library subproject's compileSdk up to match :app's, so a
        // dependency bump elsewhere in the tree can't get silently capped
        // by whatever a third-party plugin happened to hardcode.
        val appCompileSdk = project(":app").extensions
            .getByType<com.android.build.api.dsl.ApplicationExtension>()
            .compileSdk
        extensions.findByType<com.android.build.gradle.LibraryExtension>()?.apply {
            val currentCompileSdk = compileSdkVersion
                ?.removePrefix("android-")?.toIntOrNull() ?: 0
            if (appCompileSdk != null && appCompileSdk > currentCompileSdk) {
                compileSdk = appCompileSdk
            }
        }
    }
}

subprojects {
    project.evaluationDependsOn(":app")
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
