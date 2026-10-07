plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// The shared payload keeps repository-relative paths at runtime. This is the
// retained Android pipeline: Sync removes stale files, and AGP packages the
// source directory recursively without a Flutter assets declaration.
val repoRoot = rootProject.projectDir.parentFile.parentFile.parentFile
    .parentFile
val sharedAssets = layout.buildDirectory.dir("sharedAssets")
val copySharedMaterial by tasks.registering(Sync::class) {
    description = "Copies the shared payload material into assets, paths unchanged"
    from(File(repoRoot, "miaotoujunshi")) { into("miaotoujunshi") }
    from(File(repoRoot, "goutoujunshi")) { into("goutoujunshi") }
    into(sharedAssets)
}
// The payload assertion is a Dart script (ADR-0027), so it runs on the Dart SDK
// that already ships with Flutter — no Python, and nothing extra to install.
// `local.properties` is where Flutter records that SDK: its own Gradle plugin
// reads `flutter.sdk` from the same file, and reading it here is what keeps this
// task working when Gradle is started by Android Studio, where the Flutter SDK is
// not on Gradle's `PATH`. `DART` overrides the lookup.
//
// The value is parsed out of the text rather than through `java.util.Properties`:
// `Properties.load` is overloaded on `InputStream` and `Reader`, and a build
// script cannot choose between the two while the stream's own type is still being
// inferred.
val localProperties = File(rootProject.projectDir, "local.properties")
val localPropertiesText: String =
    if (localProperties.exists()) localProperties.readText() else ""
val flutterSdk: String = localPropertiesText
    .lines()
    .firstOrNull { line -> line.startsWith("flutter.sdk=") }
    ?.removePrefix("flutter.sdk=")
    ?.trim()
    ?: ""

// The path names the VM under `bin/cache/dart-sdk/`, not the SDK's `bin/dart`
// launcher: that launcher is a shell script on POSIX and a `.bat` on Windows, and
// a process cannot be started from either.
val dartVm: String? = if (flutterSdk.isEmpty()) {
    null
} else {
    listOf("dart", "dart.exe")
        .map { name -> File(flutterSdk, "bin/cache/dart-sdk/bin/$name") }
        .firstOrNull { candidate -> candidate.exists() }
        ?.absolutePath
}
val dartExecutable = providers.environmentVariable("DART").getOrElse(dartVm ?: "dart")

val validateSharedPayload by tasks.registering(Exec::class) {
    description = "Asserts every runtime payload key is present in Android assets"
    dependsOn(copySharedMaterial)
    commandLine(
        dartExecutable,
        File(
            repoRoot,
            "app/apps/miaotou_app/tool/validate_payload_keys.dart",
        ),
        repoRoot,
        sharedAssets.get().asFile,
    )
}
tasks.matching { it.name.startsWith("merge") && it.name.endsWith("Assets") }
    .configureEach { dependsOn(validateSharedPayload) }

android {
    namespace = "com.miaotoujunshi.miaotou_app"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "com.miaotoujunshi.miaotou_app"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        // The retained accessibility screenshot layer requires Android 11.
        minSdk = 30
        targetSdk = flutter.targetSdkVersion
        // Uses the version code from pubspec.yaml. When using split APKs, 1000 * ABI_VERSION
        // is added automatically by Flutter. (https://developer.android.com/studio/build/configure-apk-splits#configure-APK-versions)
        // You can force using the value of versionCode by specifying the `-P force-version-code-ignoring-abi=true`
        // flag during build.
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    buildTypes {
        release {
            // TODO: Add your own signing config for the release build.
            // Signing with the debug keys for now, so `flutter run --release` works.
            signingConfig = signingConfigs.getByName("debug")
        }

        sourceSets["main"].assets.srcDir(sharedAssets.get().asFile)
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
