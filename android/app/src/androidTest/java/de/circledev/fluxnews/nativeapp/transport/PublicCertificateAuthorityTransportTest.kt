package de.circledev.fluxnews.nativeapp.transport

import androidx.test.ext.junit.runners.AndroidJUnit4
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith
import uniffi.flux_uniffi.AccountValidationException
import uniffi.flux_uniffi.validateMinifluxAccountWithDiagnostic

/**
 * E1-C public/system CA gate.
 *
 * This is the one E1-C gate that needs outbound internet access, so it is a deliberate online
 * integration test and is not part of the offline host gate `android/Build/test.sh`.
 *
 * The proof is a semantic one rather than "some error was thrown": the Core maps a failed
 * transport to [AccountValidationException.Network] and only maps an actually received HTTP
 * response to an HTTP-level outcome. Reaching an HTTP-level outcome against a public host is
 * therefore evidence that the Android platform verifier accepted a public/system trust anchor.
 */
@RunWith(AndroidJUnit4::class)
class PublicCertificateAuthorityTransportTest {
    @Test
    fun publicTrustAnchorCompletesTheHandshakeAndReachesHttp() {
        val attempt = validateMinifluxAccountWithDiagnostic(
            PUBLIC_HTTPS_HOST,
            "flux-e1c-public-ca-probe",
            emptyList(),
        )

        assertNull(
            "$PUBLIC_HTTPS_HOST is not a Miniflux server and must not validate as one",
            attempt.result,
        )
        assertTrue(
            "TLS against a public certificate authority failed: " +
                "${attempt.error} / ${attempt.diagnostic}",
            attempt.error !is AccountValidationException.Network,
        )
        assertTrue(
            "Expected an HTTP-level outcome, got ${attempt.error}",
            attempt.error is AccountValidationException.IncompatibleServer ||
                attempt.error is AccountValidationException.Unauthorized ||
                attempt.error is AccountValidationException.InvalidResponse ||
                attempt.error is AccountValidationException.ServerUnavailable,
        )
    }

    @Test
    fun hostnameMismatchIsRejectedAfterChainValidation() {
        val attempt = validateMinifluxAccountWithDiagnostic(
            HOSTNAME_MISMATCH_HTTPS_HOST,
            "flux-e1c-hostname-probe",
            emptyList(),
        )

        assertNull(
            "A certificate for another hostname must never validate as a Miniflux server",
            attempt.result,
        )
        assertTrue(
            "Expected hostname validation to reject TLS, got ${attempt.error} / " +
                "${attempt.diagnostic}",
            attempt.error is AccountValidationException.Network &&
                attempt.diagnostic?.category == "TLS/certificate",
        )
    }

    private companion object {
        /**
         * IANA's reserved documentation host. It serves a publicly trusted certificate and answers
         * `/v1/version` with an ordinary HTTP status, which is exactly the "TLS succeeded, this is
         * not Miniflux" evidence this gate needs.
         */
        const val PUBLIC_HTTPS_HOST = "https://example.com"

        /** Publicly trusted chain deliberately presented for the wrong DNS name. */
        const val HOSTNAME_MISMATCH_HTTPS_HOST = "https://wrong.host.badssl.com"
    }
}
