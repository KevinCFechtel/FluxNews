import org.gradle.api.tasks.Exec
import org.gradle.api.tasks.TaskProvider
import java.util.Properties

plugins {
    id("com.android.application")
    id("androidx.baselineprofile")
    id("org.jetbrains.kotlin.plugin.compose")
}

val developmentBundleSigningProperties = Properties().apply {
    val propertiesFile = rootProject.file("developmentBundle-signing.properties")
    if (propertiesFile.exists()) propertiesFile.inputStream().use(::load)
}

// Explicit opt-in only for the Play upload build. Normal productionRelease APKs
// must not silently pick up the Play upload certificate: direct installs/rollback
// may require a different, Flutter-compatible app-signing certificate.
val signProductionBundle = providers.gradleProperty("fluxProductionBundleSigning")
    .map(String::toBoolean)
    .orElse(false)
    .get()
val productionBundleSigningProperties = Properties().apply {
    if (signProductionBundle) {
        val propertiesFile = rootProject.file("productionBundle-signing.properties")
        if (!propertiesFile.isFile) {
            throw GradleException("Missing android/productionBundle-signing.properties for signed Play bundle.")
        }
        propertiesFile.inputStream().use(::load)
        val required = listOf("keyAlias", "keyPassword", "storeFile", "storePassword")
        required.forEach { name ->
            if (getProperty(name).isNullOrBlank()) {
                throw GradleException("Missing ${name} in productionBundle-signing.properties.")
            }
        }
        val keyStore = rootProject.file(getProperty("storeFile"))
        if (!keyStore.isFile) {
            throw GradleException("Production Play upload keystore does not exist: ${keyStore.path}")
        }
    }
}

// Release versions are supplied by Build/build-app.sh. The fallback values are
// retained for CI and non-distributable local builds without release arguments.
val buildVersionCode = providers.gradleProperty("fluxBuildVersionCode").map(String::toInt).orElse(1)
val buildVersionName = providers.gradleProperty("fluxBuildVersionName").orElse("0.1.0")

android {
    namespace = "de.circledev.fluxnews.nativeapp"
    compileSdk = 37
    defaultConfig { applicationId = "de.circle_dev.flux_news"; minSdk = 29; targetSdk = 36; versionCode = buildVersionCode.get(); versionName = buildVersionName.get(); testInstrumentationRunner = "androidx.test.runner.AndroidJUnitRunner" }
    signingConfigs {
        if (developmentBundleSigningProperties.isNotEmpty()) {
            create("developmentBundle") {
                keyAlias = developmentBundleSigningProperties.getProperty("keyAlias")
                keyPassword = developmentBundleSigningProperties.getProperty("keyPassword")
                storeFile = developmentBundleSigningProperties.getProperty("storeFile")
                    ?.let(rootProject::file)
                storePassword = developmentBundleSigningProperties.getProperty("storePassword")
            }
        }
        if (signProductionBundle) {
            create("productionBundle") {
                keyAlias = productionBundleSigningProperties.getProperty("keyAlias")
                keyPassword = productionBundleSigningProperties.getProperty("keyPassword")
                storeFile = rootProject.file(productionBundleSigningProperties.getProperty("storeFile"))
                storePassword = productionBundleSigningProperties.getProperty("storePassword")
            }
        }
    }
    buildTypes {
        debug { isMinifyEnabled = false }
        release {
            isMinifyEnabled = true
            isShrinkResources = true
            proguardFiles(getDefaultProguardFile("proguard-android-optimize.txt"), "proguard-rules.pro")
        }
        create("migrationProbe") { initWith(getByName("debug")); isDebuggable = true; isMinifyEnabled = false; applicationIdSuffix = "" }
    }
    flavorDimensions += "distribution"
    productFlavors {
        create("development") {
            dimension = "distribution"
            applicationIdSuffix = ".native.dev"
            versionNameSuffix = "-native-dev"
            resValue("string", "app_name", "FluxNews Native Dev")
            signingConfigs.findByName("developmentBundle")?.let { signingConfig = it }
        }
        create("production") {
            dimension = "distribution"
            // Only build-app.sh productionBundle enables this signing configuration.
            if (signProductionBundle) {
                signingConfig = signingConfigs.getByName("productionBundle")
            }
        }
    }
    sourceSets {
        getByName("debug").apply {
            kotlin.directories.add("../Build/Products/Bindings/debug/kotlin")
            jniLibs.directories.add("../Build/Products/debug")
        }
        getByName("release").apply {
            kotlin.directories.add("../Build/Products/Bindings/release/kotlin")
            jniLibs.directories.add("../Build/Products/release")
        }
        getByName("migrationProbe").apply {
            java.directories.add("src/migrationProbe/java")
            kotlin.directories.add("../Build/Products/Bindings/debug/kotlin")
            jniLibs.directories.add("../Build/Products/debug")
        }
    }
    buildFeatures { buildConfig = true; compose = true; resValues = true }
    lint {
        // Other Weblate locales are intentionally incomplete and fall back to English.
        // Keep all other lint checks enabled; resource keys and placeholders are tested separately.
        disable += "MissingTranslation"
    }
    compileOptions { sourceCompatibility = JavaVersion.VERSION_17; targetCompatibility = JavaVersion.VERSION_17 }
}

androidComponents {
    beforeVariants { variantBuilder ->
        val flavor = variantBuilder.productFlavors.singleOrNull { it.first == "distribution" }?.second
        if (flavor == "production" && variantBuilder.buildType == "debug") variantBuilder.enable = false
    }
}

val uniffiBuildScript = file("../Build/build-uniffi.sh")
fun registerUniffiPreparation(variantName: String, mode: String): TaskProvider<Exec> = tasks.register<Exec>("prepare${variantName.replaceFirstChar { it.uppercase() }}Uniffi") {
    inputs.file(uniffiBuildScript)
    inputs.files(
        fileTree("../../core") {
            include("Cargo.toml", "Cargo.lock", "crates/**/*.rs", "crates/**/Cargo.toml", "crates/**/*.toml")
        },
    )
    outputs.dir(file("../Build/Products/$mode"))
    outputs.dir(file("../Build/Products/Bindings/$mode/kotlin"))
    // F-Droid sets this via gradleprops; ordinary builds retain their environment.
    val includeArmv7 = providers.gradleProperty("fluxAndroidIncludeArmv7")
        .orElse(providers.environmentVariable("FLUX_ANDROID_INCLUDE_ARMV7"))
        .orElse("0")
    inputs.property("fluxAndroidIncludeArmv7", includeArmv7)
    environment("FLUX_ANDROID_INCLUDE_ARMV7", includeArmv7.get())
    commandLine(uniffiBuildScript.absolutePath, mode)
}
fun wireUniffiPreparation(variantName: String, preparation: TaskProvider<Exec>) { val capitalized = variantName.replaceFirstChar { it.uppercase() }; tasks.matching { it.name == "compile${capitalized}Kotlin" || it.name == "merge${capitalized}JniLibFolders" || it.name == "merge${capitalized}NativeLibs" }.configureEach { dependsOn(preparation) } }
wireUniffiPreparation("developmentDebug", registerUniffiPreparation("developmentDebug", "debug"))
wireUniffiPreparation("developmentRelease", registerUniffiPreparation("developmentRelease", "release"))
wireUniffiPreparation("developmentNonMinifiedRelease", registerUniffiPreparation("developmentNonMinifiedRelease", "release"))
wireUniffiPreparation("productionMigrationProbe", registerUniffiPreparation("productionMigrationProbe", "debug"))

val migrationSigningProperties = Properties().apply { val file = rootProject.file("migration-signing.properties"); if (file.exists()) file.inputStream().use(::load) }
android.buildTypes.named("migrationProbe") { if (migrationSigningProperties.isNotEmpty()) signingConfig = android.signingConfigs.maybeCreate("migrationProbe").apply { keyAlias = migrationSigningProperties.getProperty("keyAlias"); keyPassword = migrationSigningProperties.getProperty("keyPassword"); storeFile = migrationSigningProperties.getProperty("storeFile")?.let(::file); storePassword = migrationSigningProperties.getProperty("storePassword") } }
val migrationVersionCode = providers.gradleProperty("fluxMigrationVersionCode").map(String::toInt).orElse(1)
androidComponents.onVariants(androidComponents.selector().withBuildType("migrationProbe")) { variant -> variant.outputs.forEach { output -> output.versionCode.set(migrationVersionCode) } }

// Keep the legacy development Play override compatible with existing callers.
// The unified build-app.sh flow uses fluxBuildVersionCode for all release variants.
val developmentPlayVersionCode = providers.gradleProperty("fluxDevelopmentPlayVersionCode")
    .map(String::toInt)
    .orElse(buildVersionCode)
androidComponents.onVariants(
    androidComponents.selector()
        .withFlavor("distribution" to "development")
        .withBuildType("release"),
) { variant ->
    variant.outputs.forEach { output ->
        output.versionCode.set(developmentPlayVersionCode)
    }
}
tasks.matching { it.name == "testProductionMigrationProbeUnitTest" }.configureEach { (this as org.gradle.api.tasks.testing.Test).exclude("**/DevelopmentIdentityTest.class") }
wireUniffiPreparation("productionRelease", registerUniffiPreparation("productionRelease", "release"))


baselineProfile {
    // One generated profile is shared by Development and Production releases so the
    // Play internal-test build exercises the same compiled app paths as production.
    mergeIntoMain = true
}

dependencies {
    implementation(platform("androidx.compose:compose-bom:2026.09.00"))
    implementation("androidx.core:core-ktx:1.19.1")
    implementation("androidx.lifecycle:lifecycle-runtime-ktx:2.11.0")
    implementation("androidx.activity:activity-compose:1.13.0")
    implementation("androidx.browser:browser:1.10.0")
    implementation("androidx.navigation:navigation-compose:2.10.2")
    implementation("androidx.datastore:datastore-preferences:1.3.0")
    implementation("androidx.work:work-runtime-ktx:2.12.0")
    implementation("androidx.media3:media3-exoplayer:1.11.1")
    implementation("androidx.media3:media3-session:1.11.1")
    add("developmentImplementation", "androidx.car.app:app:1.9.0-alpha03")
    add("developmentImplementation", "androidx.car.app:app-projected:1.9.0-alpha03")
    add("developmentImplementation", "androidx.media:media:1.8.0")
    implementation("androidx.profileinstaller:profileinstaller:1.4.1")
    implementation("androidx.compose.material3:material3")
    implementation("androidx.compose.material:material-icons-extended")
    implementation("io.coil-kt.coil3:coil-compose:3.6.3")
    implementation("io.coil-kt.coil3:coil-network-okhttp:3.6.3")
    implementation("com.squareup.okhttp3:okhttp:5.5.1")
    implementation("com.google.android.material:material:1.14.0")
    implementation("net.java.dev.jna:jna:5.19.1@aar")
    implementation(project(":rustls-platform-verifier"))
    testImplementation("junit:junit:4.13.2")
    testImplementation("org.json:json:20260814")
    androidTestImplementation("androidx.test.ext:junit:1.3.0")
    androidTestImplementation("androidx.test:core-ktx:1.7.0")
    androidTestImplementation("androidx.test:runner:1.7.0")
    baselineProfile(project(":baselineprofile"))
}
