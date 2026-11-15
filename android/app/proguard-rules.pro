# The Android component of rustls-platform-verifier is only ever reached from Rust through JNI,
# so R8 cannot see the usage and would otherwise treat it as dead code.
-keep, includedescriptorclasses class org.rustls.platformverifier.** { *; }

# The TLS bootstrap entry point is bound by its fully qualified name from the Rust cdylib.
-keepclasseswithmembernames, includedescriptorclasses class de.circledev.fluxnews.nativeapp.AndroidPlatformTrust {
    native <methods>;
}


# UniFFI uses JNA for the generated Kotlin/Rust FFI boundary. JNA resolves native symbols and
# callback types reflectively, so release minification must preserve its runtime-facing types.
# These rules follow JNA's Android/ProGuard guidance and keep generated Library/Callback
# implementations from having their native method names rewritten.
-dontwarn java.awt.**
-keep class com.sun.jna.** { *; }
-keep class * extends com.sun.jna.** { *; }
-keep class * implements com.sun.jna.Library { *; }
-keep class * implements com.sun.jna.Callback { *; }
-keepclassmembers class * extends com.sun.jna.** { public *; }
