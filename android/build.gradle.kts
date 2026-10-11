group = "com.hx.hx_liftoff_ads"
version = "0.1.0"

// Plugin and Kotlin versions come from the host app's Gradle setup.
plugins {
    id("com.android.library")
    id("org.jetbrains.kotlin.android")
}

android {
    namespace = "com.hx.hx_liftoff_ads"

    compileSdk = 35

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    sourceSets {
        getByName("main") {
            java.srcDirs("src/main/kotlin")
        }
    }

    defaultConfig {
        minSdk = 24
    }
}

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}

dependencies {
    // Liftoff Monetize (Vungle) SDK. Exposed so apps can use it directly.
    implementation("com.vungle:vungle-ads:7.7.9")
}
