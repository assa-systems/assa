// ============================================================
// android/app/build.gradle.kts  (APP-level Kotlin DSL)
// REPLACE your existing android/app/build.gradle.kts with this.
//
// IMPORTANT: Change "com.example.assa" to your actual
// application ID if it differs (check your current file).
// ============================================================

plugins {
    id("com.android.application")
    id("org.jetbrains.kotlin.android")
    id("dev.flutter.flutter-gradle-plugin")
    // Required for Firebase
    id("com.google.gms.google-services")
}

android {
    namespace = "com.example.assa"        // ← change if yours differs
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_1_8
        targetCompatibility = JavaVersion.VERSION_1_8
        isCoreLibraryDesugaringEnabled = true
    }

    kotlinOptions {
        jvmTarget = "1.8"
    }

    defaultConfig {
        applicationId = "com.example.assa"  // ← change if yours differs
        minSdk = flutter.minSdkVersion                          // FCM requires min 21
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
        multiDexEnabled = true
    }

    buildTypes {
        release {
            signingConfig = signingConfigs.getByName("debug")
        }
    }
}

flutter {
    source = "../.."
}

dependencies {
    // Core library desugaring (required by flutter_local_notifications)
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")
    // Firebase — explicit versions (no BOM needed)
    implementation("com.google.firebase:firebase-messaging-ktx:23.4.1")
    implementation("com.google.firebase:firebase-analytics-ktx:21.5.1")
    implementation("androidx.multidex:multidex:2.0.1")
}
