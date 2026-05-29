plugins {
    id("com.android.application")
    id("kotlin-android")
    id("dev.flutter.flutter-gradle-plugin")
    // google-services.json 파일을 넣기 전까지는 아래 줄을 주석으로 유지해야 빌드 에러가 나지 않습니다.
    // id("com.google.gms.google-services")
}

android {
    namespace = "com.fashionai.ai_fashion_assistant"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_11
        targetCompatibility = JavaVersion.VERSION_11
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_11.toString()
    }

    defaultConfig {
        applicationId = "com.fashionai.ai_fashion_assistant"
        minSdk = flutter.minSdkVersion // Firebase 사용을 위해 21 이상 권장
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
        
        // 라이브러리가 많아질 경우를 대비해 멀티덱스 활성화
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
