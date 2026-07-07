import java.io.FileInputStream
import java.util.Properties

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "com.eatwise.eatwise"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "com.eatwise.eatwise"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = 31  // 动态取色（Material You）需 Android 12+（API 31）；flutter_secure_storage 10.x 要求 23+，31 满足
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
        // M27 APK 体积优化：仅打包 arm64-v8a（64 位 ARM，2019 年后手机主流架构）
        // 默认打 3 ABI（arm64-v8a + armeabi-v7a + x86_64）致 release APK 87MB，
        // 仅 arm64-v8a 后降至 ~30MB（减 65%）。
        // minSdk=31（Android 12+）已排除老手机，arm64 普及率 >99%，覆盖充分。
        // 模拟器（x86_64）无法安装此 release 包，开发用 --target-platform android-x64 单独打。
        ndk {
            abiFilters += "arm64-v8a"
        }
    }

    // M16 应用内更新：固定签名 keystore（保证 CI 与本地 build 签名一致，支持覆盖安装）
    // keystore 文件路径与密码从 key.properties 读取（文件不进 repo）
    // key.properties 不存在时回退到 debug 签名（开发期不阻塞）
    val keystoreProperties = Properties()
    val keystorePropertiesFile = rootProject.file("app/key.properties")
    if (keystorePropertiesFile.exists()) {
        keystoreProperties.load(FileInputStream(keystorePropertiesFile))
    }

    signingConfigs {
        create("release") {
            if (keystoreProperties.isNotEmpty()) {
                keyAlias = keystoreProperties["keyAlias"] as String
                keyPassword = keystoreProperties["keyPassword"] as String
                storeFile = file(keystoreProperties["storeFile"] as String)
                storePassword = keystoreProperties["storePassword"] as String
            }
        }
    }

    buildTypes {
        release {
            // M16 应用内更新：有 key.properties 用固定 release 签名，否则回退 debug
            signingConfig = if (keystoreProperties.isNotEmpty()) {
                signingConfigs.getByName("release")
            } else {
                signingConfigs.getByName("debug")
            }
            // 禁用 R8 代码压缩：sentry_flutter/workmanager 等插件依赖反射注册，
            // R8 默认规则会剥掉关键类导致 native 启动崩溃（Dart try-catch 抓不住）。
            // 个人自用 app 体积稍大可接受，稳定性优先。
            isMinifyEnabled = false
            isShrinkResources = false
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
