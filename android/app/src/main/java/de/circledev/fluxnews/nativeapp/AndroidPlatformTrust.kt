package de.circledev.fluxnews.nativeapp

import android.content.Context

/**
 * Narrow bootstrap for the Android certificate verifier used by the Rust core transport.
 *
 * The pinned `rustls-platform-verifier` needs a JVM handle, an application [Context] and the
 * application class loader before the first Rust TLS handshake. This object hands exactly those
 * over and nothing else; every product call into the core keeps going through UniFFI.
 *
 * The native symbol is derived from this object's fully qualified name, so the Rust counterpart
 * in `flux-uniffi` (`android_tls.rs`) must be kept in sync with it.
 */
object AndroidPlatformTrust {
    private const val NATIVE_LIBRARY = "flux_uniffi"

    private var initialized = false

    /**
     * Prepares Android platform trust for the process. Safe to call repeatedly; only the first
     * successful call performs work.
     */
    @Synchronized
    fun initialize(context: Context) {
        if (initialized) {
            return
        }
        // UniFFI reaches the same library through JNA, which does not register it with the JVM.
        // The JNI entry point below needs the JVM-visible registration.
        System.loadLibrary(NATIVE_LIBRARY)
        nativeInitialize(context.applicationContext)
        initialized = true
    }

    @JvmStatic
    private external fun nativeInitialize(context: Context)
}
