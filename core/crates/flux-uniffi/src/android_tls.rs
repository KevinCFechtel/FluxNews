//! Narrow Android TLS bootstrap.
//!
//! The pinned `rustls-platform-verifier` needs a JVM handle, an Android `Context` and the
//! application class loader before the first Rust TLS handshake, and it only offers a JNI
//! typed entry point for that. This module provides exactly that hook and nothing else: it
//! carries no domain data, no JSON, no Miniflux concepts and no Core operations. UniFFI
//! remains the only product API between Android and the Core.
//!
//! The Kotlin counterpart is `de.circledev.fluxnews.nativeapp.AndroidPlatformTrust`; the JNI
//! symbol below is derived from that fully qualified name, so the two must stay in sync.

use jni::errors::ThrowRuntimeExAndDefault;
use jni::objects::{JClass, JObject};
use jni::strings::JNIString;
use jni::{EnvUnowned, jni_str};

/// Initializes the Android platform certificate verifier used by the Core's HTTP transport.
///
/// `context` must be an application-scoped `android.content.Context`. The underlying
/// initialization is idempotent for the lifetime of the process: repeated calls keep the
/// first successfully stored JVM handles. A failure raises `IllegalStateException` so the
/// caller cannot silently continue into an unverified TLS path.
#[unsafe(no_mangle)]
pub extern "system" fn Java_de_circledev_fluxnews_nativeapp_AndroidPlatformTrust_nativeInitialize<
    'local,
>(
    mut unowned_env: EnvUnowned<'local>,
    _class: JClass<'local>,
    context: JObject<'local>,
) {
    unowned_env
        .with_env(|env| -> jni::errors::Result<()> {
            if let Err(error) = rustls_platform_verifier::android::init_with_env(env, context) {
                // JNI calls can fail with a pending Java exception. Replace it with the stable
                // application-facing failure rather than attempting to throw through it.
                if env.exception_check() {
                    env.exception_clear();
                }
                env.throw_new(
                    jni_str!("java/lang/IllegalStateException"),
                    JNIString::new(format!(
                        "Android TLS platform verifier initialization failed: {error}"
                    )),
                )?;
            }
            Ok(())
        })
        .resolve::<ThrowRuntimeExAndDefault>();
}
