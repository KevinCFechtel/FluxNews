package de.circledev.fluxnews.nativeapp.transport

import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import de.circledev.fluxnews.nativeapp.AndroidPlatformTrust
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith
import uniffi.flux_uniffi.AccountValidationAttempt
import uniffi.flux_uniffi.AccountValidationException
import uniffi.flux_uniffi.HttpHeader
import uniffi.flux_uniffi.validateMinifluxAccount
import uniffi.flux_uniffi.validateMinifluxAccountWithDiagnostic

/**
 * E1-C transport proof.
 *
 * Every gate runs through the production path: Kotlin -> UniFFI -> flux-core -> MinifluxClient ->
 * ureq -> rustls -> Android trust infrastructure. Nothing here asserts on Kotlin HTTP behaviour,
 * and nothing here asserts on raw rustls or ureq error text; the assertions use the Core's own
 * account-validation result and error semantics.
 */
@RunWith(AndroidJUnit4::class)
class MinifluxTransportTest {
    @Test
    fun platformTrustBootstrapIsIdempotent() {
        // FluxApplication.onCreate() already ran it for this process; a second call must be a
        // no-op rather than a second verifier installation.
        val context = InstrumentationRegistry.getInstrumentation().targetContext
        AndroidPlatformTrust.initialize(context)
        AndroidPlatformTrust.initialize(context)
    }

    @Test
    fun plainHttpReachesMinifluxThroughTheRustClient() {
        LoopbackMinifluxServer.http().use { server ->
            val result = validateMinifluxAccount(
                server.installationBase,
                LoopbackMinifluxServer.API_TOKEN,
                emptyList(),
            )

            assertEquals(LoopbackMinifluxServer.MINIFLUX_VERSION, result.version)
            assertEquals(server.installationBase, result.installationBase)

            val request = server.requests.last()
            assertTrue(
                "Unexpected request line: ${request.requestLine}",
                request.requestLine.startsWith("GET ${LoopbackMinifluxServer.VERSION_PATH} "),
            )
            assertEquals(
                LoopbackMinifluxServer.API_TOKEN,
                request.headers[LoopbackMinifluxServer.AUTH_HEADER.lowercase()],
            )
        }
    }

    @Test
    fun customHeadersAreSentOnTheRustRequest() {
        val required = LoopbackMinifluxServer.CUSTOM_HEADER_NAME to
            LoopbackMinifluxServer.CUSTOM_HEADER_VALUE

        LoopbackMinifluxServer.http(requiredHeader = required).use { server ->
            val withoutHeader = runCatching {
                validateMinifluxAccount(
                    server.installationBase,
                    LoopbackMinifluxServer.API_TOKEN,
                    emptyList(),
                )
            }.exceptionOrNull()
            assertTrue(
                "Expected the server to reject a request without the custom header, got $withoutHeader",
                withoutHeader is AccountValidationException.Unauthorized,
            )

            val result = validateMinifluxAccount(
                server.installationBase,
                LoopbackMinifluxServer.API_TOKEN,
                listOf(HttpHeader(required.first, required.second)),
            )
            assertEquals(LoopbackMinifluxServer.MINIFLUX_VERSION, result.version)
            assertEquals(
                LoopbackMinifluxServer.CUSTOM_HEADER_VALUE,
                server.requests.last().headers[required.first.lowercase()],
            )
        }
    }

    @Test
    fun untrustedCertificateIsRejected() {
        LoopbackMinifluxServer.https(TestCertificateFixture.UNTRUSTED).use { server ->
            val attempt = validateMinifluxAccountWithDiagnostic(
                server.installationBase,
                LoopbackMinifluxServer.API_TOKEN,
                emptyList(),
            )

            assertNull(
                "An untrusted certificate must never validate as a Miniflux server",
                attempt.result,
            )
            assertTlsRejection(attempt)
            assertTrue(
                "The client must not have received a Miniflux response",
                server.requests.isEmpty(),
            )
        }
    }

    @Test
    fun userInstalledCaTrustFollowsTheAndroidUserStore() {
        val installed = AndroidUserTrustStore.containsFluxTestUserCa()
        expectedUserCaState()?.let { expected ->
            assertEquals(
                "The Android user trust store does not match the requested E1-C phase. " +
                    "Run android/Build/test-transport-runtime.sh, which owns the installation step.",
                expected,
                installed,
            )
        }

        LoopbackMinifluxServer.https(TestCertificateFixture.USER_INSTALLED_CA).use { server ->
            val attempt = validateMinifluxAccountWithDiagnostic(
                server.installationBase,
                LoopbackMinifluxServer.API_TOKEN,
                emptyList(),
            )

            if (installed) {
                assertNull(
                    "A user-installed CA must be trusted by the Rust transport, got " +
                        "${attempt.error} / ${attempt.diagnostic}",
                    attempt.error,
                )
                val result = attempt.result
                assertNotNull("Account validation returned neither a result nor an error", result)
                assertEquals(LoopbackMinifluxServer.MINIFLUX_VERSION, result!!.version)
            } else {
                assertNull(
                    "Without the test CA installed the same server must stay untrusted",
                    attempt.result,
                )
                assertTlsRejection(attempt)
            }
        }
    }

    private fun assertTlsRejection(attempt: AccountValidationAttempt) {
        assertTrue(
            "Expected a transport-level rejection, got ${attempt.error} / ${attempt.diagnostic}",
            attempt.error is AccountValidationException.Network,
        )
        assertEquals(
            "Expected the Core to categorise the failure as a certificate problem",
            "TLS/certificate",
            attempt.diagnostic?.category,
        )
    }

    private fun expectedUserCaState(): Boolean? =
        InstrumentationRegistry.getArguments()
            .getString(USER_CA_EXPECTATION_ARGUMENT)
            ?.lowercase()
            ?.let { it == "true" }

    private companion object {
        const val USER_CA_EXPECTATION_ARGUMENT = "fluxUserCaInstalled"
    }
}
