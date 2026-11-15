package de.circledev.fluxnews.nativeapp.transport

import java.security.KeyStore
import java.security.cert.CertificateFactory
import java.security.cert.X509Certificate

/**
 * Read-only view of the Android trust infrastructure, used to state which E1-C user-CA phase a
 * device is currently in. The tests never modify the trust store; installing the TEST ONLY CA is
 * an explicit, documented step of `android/Build/test-transport-runtime.sh`.
 */
object AndroidUserTrustStore {
    private const val ANDROID_CA_STORE = "AndroidCAStore"
    private const val USER_ALIAS_PREFIX = "user:"

    /** True when the TEST ONLY CA is present as a user-installed anchor. */
    fun containsFluxTestUserCa(): Boolean = aliasOfFluxTestUserCa() != null

    fun aliasOfFluxTestUserCa(): String? {
        val expected = CertificateFactory.getInstance("X.509")
            .generateCertificate(
                TestCertificateFixture.readResource(TestCertificateFixture.USER_CA_RESOURCE)
                    .inputStream(),
            ) as X509Certificate

        val store = KeyStore.getInstance(ANDROID_CA_STORE)
        store.load(null, null)
        return store.aliases().asSequence().firstOrNull { alias ->
            alias.startsWith(USER_ALIAS_PREFIX) && store.getCertificate(alias) == expected
        }
    }
}
