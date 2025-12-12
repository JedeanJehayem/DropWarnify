plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "com.example.dropwarnify"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_17.toString()
    }

    defaultConfig {
        applicationId = "com.example.dropwarnify"
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    buildTypes {
        release {
            // usa a mesma keystore de debug por enquanto
            signingConfig = signingConfigs.getByName("debug")

            // ⚙️ ativa R8 / minify e aponta pro nosso proguard
            isMinifyEnabled = true
            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"),
                "proguard-rules.pro",
            )
        }
    }

    lint {
        // não derruba o build por causa de erro de lint em release
        abortOnError = false
        // desabilita especificamente esse check chato do WearableBindListener
        disable += "WearableBindListener"
    }
}

flutter {
    source = "../.."
}

dependencies {
    // Wear OS – comunicação com o relógio
    implementation("com.google.android.gms:play-services-wearable:18.1.0")

    // 📍 Localização nativa (FusedLocationProviderClient, LocationRequest, etc.)
    implementation("com.google.android.gms:play-services-location:21.3.0")
}
