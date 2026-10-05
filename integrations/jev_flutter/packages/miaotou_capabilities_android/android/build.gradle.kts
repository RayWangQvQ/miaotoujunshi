group = "com.miaotoujunshi.capabilities.android"
version = "1.0-SNAPSHOT"

buildscript {
    val kotlinVersion = "2.4.0"
    repositories {
        google()
        mavenCentral()
    }
    dependencies {
        classpath("com.android.tools.build:gradle:9.1.0")
        classpath("org.jetbrains.kotlin:kotlin-gradle-plugin:$kotlinVersion")
    }
}

allprojects {
    repositories {
        google()
        mavenCentral()
    }
}

plugins {
    id("com.android.library")
    id("org.jetbrains.kotlin.android")
}

val retainedKotlin = layout.buildDirectory.dir("retainedKotlin")
val syncRetainedKotlin by tasks.registering(Sync::class) {
    from("../../../../jev_android/app/src/main/java") {
        include(
            "com/jev/probe/core/ChatApps.kt",
            "com/jev/probe/core/ChatModels.kt",
            "com/jev/probe/capture/ChatAppAdapter.kt",
            "com/jev/probe/capture/ocr/MlKitOcr.kt",
            "com/jev/probe/capture/ocr/OcrEngine.kt",
            "com/jev/probe/capture/ocr/ScreenCapture.kt",
        )
    }
    into(retainedKotlin)
}

android {
    namespace = "com.miaotoujunshi.capabilities.android"
    compileSdk = 36

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        minSdk = 30
    }

    sourceSets["main"].java.srcDir(retainedKotlin.get().asFile)

    testOptions {
        unitTests.isIncludeAndroidResources = true
    }

    tasks.matching { it.name.startsWith("compile") && it.name.endsWith("Kotlin") }
        .configureEach { dependsOn(syncRetainedKotlin) }
}

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }

    dependencies {
        implementation("com.google.mlkit:text-recognition-chinese:16.0.1")
        testImplementation("junit:junit:4.13.2")
    }
}
