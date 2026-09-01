plugins {
    id("com.android.application")
    kotlin("android")
    kotlin("plugin.compose")
}

android {
    namespace = "com.padelscore.wear"
    compileSdk = 35

    defaultConfig {
        applicationId = "com.codebrewery.padelscore.wear"
        minSdk = 30
        targetSdk = 35
        versionCode = 1
        versionName = "1.0"
    }

    buildTypes {
        release {
            isMinifyEnabled = false
        }
    }

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    buildFeatures {
        compose = true
    }
}

kotlin {
    compilerOptions {
        jvmTarget.set(org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17)
    }
}

dependencies {
    implementation(project(":domain"))
    implementation("androidx.core:core-ktx:1.15.0")
    implementation("androidx.activity:activity-compose:1.9.3")
    implementation("androidx.lifecycle:lifecycle-runtime-compose:2.8.7")
    implementation("androidx.wear.compose:compose-material3:1.5.0")
    implementation("androidx.wear.compose:compose-foundation:1.5.0")
    implementation("androidx.compose.ui:ui-tooling-preview:1.7.6")
    implementation("androidx.health:health-services-client:1.0.0")
    implementation("org.jetbrains.kotlinx:kotlinx-coroutines-android:1.9.0")
    implementation("org.jetbrains.kotlinx:kotlinx-coroutines-guava:1.9.0")
    implementation("androidx.concurrent:concurrent-futures-ktx:1.2.0")
}
