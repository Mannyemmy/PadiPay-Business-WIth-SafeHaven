plugins {
    id("com.android.application")
    // START: FlutterFire Configuration
    id("com.google.gms.google-services")
    // END: FlutterFire Configuration
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

import java.util.Properties
import org.gradle.api.GradleException

// Load keystore properties from key.properties (keystore file should be at android/app)
val keystorePropertiesFile = rootProject.file("key.properties")
val keystoreProperties = Properties()
if (keystorePropertiesFile.exists()) {
    keystoreProperties.load(keystorePropertiesFile.inputStream())
}

// Read and validate keystore properties to provide clear errors if something's missing
val storeFileProp = (keystoreProperties["storeFile"] as String?).takeUnless { it.isNullOrBlank() } ?: "padi_pay_business.jks"
val storePasswordProp = (keystoreProperties["storePassword"] as String?)
val keyAliasProp = (keystoreProperties["keyAlias"] as String?)
val keyPasswordProp = (keystoreProperties["keyPassword"] as String?)
val keystoreFileObj = file(storeFileProp)
// Diagnostic: print presence of properties (do not print actual passwords)
println("Keystore check: file=${keystoreFileObj.absolutePath}, storePasswordPresent=${!storePasswordProp.isNullOrBlank()}, keyAliasPresent=${!keyAliasProp.isNullOrBlank()}, keyPasswordPresent=${!keyPasswordProp.isNullOrBlank()}")

if (!keystoreFileObj.exists()) {
    throw GradleException("Keystore file not found: ${keystoreFileObj}. Generate it with keytool; see android/RELEASE_INSTRUCTIONS.md for the exact command.")
}
if (storePasswordProp.isNullOrBlank()) {
    throw GradleException("Keystore 'storePassword' is missing or empty in android/key.properties")
}
if (keyAliasProp.isNullOrBlank()) {
    throw GradleException("Keystore 'keyAlias' is missing or empty in android/key.properties")
}
if (keyPasswordProp.isNullOrBlank()) {
    throw GradleException("Keystore 'keyPassword' is missing or empty in android/key.properties")
}

android {
    namespace = "com.example.padi_pay_business"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_11
        targetCompatibility = JavaVersion.VERSION_11
        isCoreLibraryDesugaringEnabled = true
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_11.toString()
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "com.allgoodtech.padi_pay_bizness"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = 24
        targetSdk = flutter.targetSdkVersion
        versionCode = 3
        versionName = "1.0"
    }

    signingConfigs {
        create("release") {
            // use validated, non-null variables from above
            storeFile = keystoreFileObj
            storePassword = storePasswordProp
            keyAlias = keyAliasProp
            keyPassword = keyPasswordProp
        }
    }

    buildTypes {
        release {
            signingConfig = signingConfigs.getByName("release")
                isMinifyEnabled = true                      // enable code shrinking (R8)
        isShrinkResources = true 
            // Enable code shrinking and add proguard rules file if minification is enabled
            // (R8 will honor these files when minifyEnabled = true)
            // Keep proguard-rules.pro for targeted keep rules (do not use global -dont* unless necessary)
            proguardFiles(getDefaultProguardFile("proguard-android-optimize.txt"), "proguard-rules.pro")
        }
    }
}

flutter {
    source = "../.."
}

dependencies {
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")
    implementation(fileTree(mapOf("include" to listOf("*.aar","*.jar"), "dir" to "libs")))
}