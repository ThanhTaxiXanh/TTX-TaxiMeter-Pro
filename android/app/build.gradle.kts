plugins {
    id("com.android.application")
    id("kotlin-android")
    // Flutter Gradle Plugin phai dat sau Android va Kotlin plugin.
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "vn.ttx.taximeter"
    compileSdk = 34
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
        isCoreLibraryDesugaringEnabled = true
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_17.toString()
    }

    defaultConfig {
        applicationId = "vn.ttx.taximeter"
        minSdk = 24
        targetSdk = 34
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    buildTypes {
        release {
            // Tam thoi ky bang khoa debug de APK cai duoc truc tiep tu CI.
            // TODO(Phase 7): khoa phat hanh rieng (khong commit keystore).
            signingConfig = signingConfigs.getByName("debug")
        }
    }
}

flutter {
    source = "../.."
}

dependencies {
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.0.4")
}
