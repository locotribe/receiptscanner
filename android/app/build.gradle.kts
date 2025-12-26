plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
    // Google Servicesプラグイン (認証に必須)
    id("com.google.gms.google-services")
}

android {
    namespace = "com.example.receiptscanner"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = "27.0.12077973"

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_11
        targetCompatibility = JavaVersion.VERSION_11
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_11.toString()
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "com.example.receiptscanner"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.

        // 【修正】Firebase等の要件に合わせて 21 -> 23 に変更
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    buildTypes {
        release {
            // TODO: Add your own signing config for the release build.
            // Signing with the debug keys for now, so `flutter run --release` works.
            signingConfig = signingConfigs.getByName("debug")
        }
    }
}

flutter {
    source = "../.."
}

dependencies {
    // 日本語の文字認識モデル (これがないと日本語設定時にクラッシュします)
    implementation("com.google.mlkit:text-recognition-japanese:16.0.1")

    // Note: Flutterの場合、Firebaseの個別のライブラリ（analytics等）はここには記述せず、
    // 必要な場合は pubspec.yaml に追加します。
    // google-servicesプラグインがあれば認証設定は読み込まれます。
}
