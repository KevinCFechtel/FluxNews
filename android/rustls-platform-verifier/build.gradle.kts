// Builds the Android half of rustls-platform-verifier directly from the pinned upstream
// submodule. The Rust and Kotlin/JVM components communicate through private JNI contracts, so
// both the component version and release source revision are checked before every module build.
plugins {
    id("com.android.library")
}

val upstreamCommit = "252e25161a91af476cbea620e29d277592d27ec7"
val upstreamDir = rootDir.resolve("../vendor/rustls-platform-verifier")
val upstreamSources = upstreamDir.resolve("android/rustls-platform-verifier/src/main")

android {
    namespace = "org.rustls.platformverifier"
    compileSdk = 37

    defaultConfig {
        minSdk = 29
        // Upstream's mock trust store is test-only and must not be enabled in Flux builds.
        buildConfigField("boolean", "TEST", "false")
    }
    sourceSets {
        getByName("main") {
            manifest.srcFile(upstreamSources.resolve("AndroidManifest.xml"))
            kotlin.directories.add(upstreamSources.resolve("java").path)
            res.directories.add(upstreamSources.resolve("res").path)
        }
    }
    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }
    buildFeatures {
        buildConfig = true
    }
}

val verifyRustlsVerifierSource = tasks.register("verifyRustlsVerifierSource") {
    val crateName = "rustls-platform-verifier-android"
    val lockFile = rootDir.resolve("../core/Cargo.lock")
    val sourceManifest = upstreamDir.resolve("android-release-support/Cargo.toml")
    val rustSourceManifest = upstreamDir.resolve("rustls-platform-verifier/Cargo.toml")
    inputs.file(lockFile)
    inputs.file(sourceManifest)
    inputs.file(rustSourceManifest)

    doLast {
        check(sourceManifest.isFile) {
            "Missing rustls verifier source submodule; run: git submodule update --init"
        }

        fun packageVersion(text: String, packageName: String): String? = text
            .split("[[package]]")
            .singleOrNull { block ->
                block.lineSequence().any { it.trim() == "name = \"$packageName\"" }
            }
            ?.let { block ->
                Regex("(?m)^version = \"([^\"]+)\"$").find(block)?.groupValues?.get(1)
            }

        val lockedVersion = packageVersion(lockFile.readText(), crateName)
            ?: error("$crateName is absent from core/Cargo.lock")
        val sourceVersion = Regex("(?m)^version = \"([^\"]+)\"$")
            .find(sourceManifest.readText())
            ?.groupValues
            ?.get(1)
            ?: error("Missing $crateName version in the upstream source manifest")
        check(lockedVersion == sourceVersion) {
            "core/Cargo.lock selects $crateName $lockedVersion, but the pinned source is $sourceVersion"
        }

        val rustCrateName = "rustls-platform-verifier"
        val lockedRustVersion = packageVersion(lockFile.readText(), rustCrateName)
            ?: error("$rustCrateName is absent from core/Cargo.lock")
        val sourceRustVersion = Regex("(?m)^version = \"([^\"]+)\"$")
            .find(rustSourceManifest.readText())
            ?.groupValues
            ?.get(1)
            ?: error("Missing $rustCrateName version in the upstream source manifest")
        check(lockedRustVersion == sourceRustVersion) {
            "core/Cargo.lock selects $rustCrateName $lockedRustVersion, but the pinned source is $sourceRustVersion"
        }

        val checkedOutCommit = providers.exec {
            workingDir(upstreamDir)
            commandLine("git", "rev-parse", "HEAD")
        }.standardOutput.asText.get().trim()
        check(checkedOutCommit == upstreamCommit) {
            "Expected rustls verifier source $upstreamCommit, found $checkedOutCommit"
        }
    }
}

tasks.named("preBuild") {
    dependsOn(verifyRustlsVerifierSource)
}
