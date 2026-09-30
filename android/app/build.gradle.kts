plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "in.citchennai.neurascan_ai"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17

        // flutter_local_notifications schedules reminders with java.time, which does not
        // exist below API 26 in the platform itself. Desugaring back-ports it into the APK.
        // Required even though minSdk is 26, because the library declares the requirement
        // and Gradle refuses the build without it.
        isCoreLibraryDesugaringEnabled = true
    }

    defaultConfig {
        applicationId = "in.citchennai.neurascan_ai"

        // API 26 (Android 8.0), from the project's portability requirement. It is
        // also the floor for SQLCipher on the versions of the Android NDK that
        // current Flutter builds against, and it covers the overwhelming majority
        // of devices still in use in the target population.
        minSdk = 26
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
            // Signed with the debug keys so that `flutter run --release` works for
            // coursework builds. A real distribution would need its own keystore,
            // configured through android/key.properties, which .gitignore excludes
            // so a signing key can never be committed by accident.
            signingConfig = signingConfigs.getByName("debug")

            isMinifyEnabled = true
            isShrinkResources = true
            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"),
                "proguard-rules.pro",
            )
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
    // Supplies the back-ported java.time used by the notifications plugin. The version has
    // to be at least 2.0.4 for the plugin's API level.
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.5")
}
