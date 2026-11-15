package de.circledev.fluxnews.nativeapp.transport

import java.io.BufferedReader
import java.io.Closeable
import java.io.InputStreamReader
import java.net.InetAddress
import java.net.ServerSocket
import java.net.Socket
import java.nio.charset.StandardCharsets
import java.security.KeyFactory
import java.security.KeyStore
import java.security.cert.CertificateFactory
import java.security.cert.X509Certificate
import java.security.spec.PKCS8EncodedKeySpec
import java.util.Collections
import javax.net.ssl.KeyManager
import javax.net.ssl.KeyManagerFactory
import javax.net.ssl.SSLContext
import kotlin.concurrent.thread

/**
 * TEST ONLY loopback stand-in for the single Miniflux endpoint that account validation calls.
 *
 * It exists so the E1-C transport gates stay reproducible without a real Miniflux server, a host
 * IP or a Wi-Fi connection. It is only a server: the Miniflux client stays in Rust, and no
 * assertion in this package inspects Kotlin-side HTTP behaviour as a substitute for it.
 */
class LoopbackMinifluxServer private constructor(
    private val socket: ServerSocket,
    scheme: String,
    private val requiredHeader: Pair<String, String>?,
) : Closeable {
    private val observedRequests = Collections.synchronizedList(mutableListOf<RecordedRequest>())

    /** Installation base URL the Rust client is pointed at. */
    val installationBase: String = "$scheme://$HOST:${socket.localPort}"

    /** Every request line and header set that the Rust client actually put on the wire. */
    val requests: List<RecordedRequest>
        get() = observedRequests.toList()

    data class RecordedRequest(val requestLine: String, val headers: Map<String, String>)

    private val worker = thread(name = "loopback-miniflux", isDaemon = true) {
        while (!socket.isClosed) {
            val connection = try {
                socket.accept()
            } catch (_: Exception) {
                // A closed server socket ends the loop; a rejected handshake must not.
                if (socket.isClosed) break else continue
            }
            try {
                serve(connection)
            } catch (_: Exception) {
                // Rejected handshakes and abandoned connections are expected in the TLS gates.
            } finally {
                runCatching { connection.close() }
            }
        }
    }

    private fun serve(connection: Socket) {
        connection.soTimeout = SOCKET_TIMEOUT_MILLIS
        val reader =
            BufferedReader(InputStreamReader(connection.getInputStream(), StandardCharsets.UTF_8))
        val requestLine = reader.readLine() ?: return
        val headers = mutableMapOf<String, String>()
        while (true) {
            val line = reader.readLine() ?: break
            if (line.isEmpty()) break
            val separator = line.indexOf(':')
            if (separator > 0) {
                headers[line.substring(0, separator).trim().lowercase()] =
                    line.substring(separator + 1).trim()
            }
        }
        observedRequests.add(RecordedRequest(requestLine, headers))

        val path = requestLine.split(' ').getOrNull(1)
        val response = when {
            path != VERSION_PATH -> status(404, """{"error_message":"not found"}""")
            headers[AUTH_HEADER.lowercase()] != API_TOKEN ->
                status(401, """{"error_message":"access unauthorized"}""")
            requiredHeader != null &&
                headers[requiredHeader.first.lowercase()] != requiredHeader.second ->
                status(401, """{"error_message":"required custom header missing"}""")
            else -> status(200, """{"version":"$MINIFLUX_VERSION"}""")
        }
        connection.getOutputStream().apply {
            write(response.toByteArray(StandardCharsets.UTF_8))
            flush()
        }
    }

    private fun status(code: Int, body: String): String {
        val reason = when (code) {
            200 -> "OK"
            401 -> "Unauthorized"
            else -> "Not Found"
        }
        val length = body.toByteArray(StandardCharsets.UTF_8).size
        return "HTTP/1.1 $code $reason\r\n" +
            "Content-Type: application/json\r\n" +
            "Content-Length: $length\r\n" +
            "Connection: close\r\n\r\n" +
            body
    }

    override fun close() {
        runCatching { socket.close() }
        worker.join(SOCKET_TIMEOUT_MILLIS.toLong())
    }

    companion object {
        const val AUTH_HEADER = "X-Auth-Token"
        const val API_TOKEN = "flux-e1c-transport-token"
        const val CUSTOM_HEADER_NAME = "X-Flux-Transport-Test"
        const val CUSTOM_HEADER_VALUE = "expected-value"
        const val MINIFLUX_VERSION = "2.2.16"
        const val VERSION_PATH = "/v1/version"

        private const val HOST = "127.0.0.1"
        private const val BACKLOG = 8
        private const val SOCKET_TIMEOUT_MILLIS = 15_000

        /** Plain HTTP, proving the product keeps supporting cleartext Miniflux installations. */
        fun http(requiredHeader: Pair<String, String>? = null): LoopbackMinifluxServer =
            LoopbackMinifluxServer(
                ServerSocket(0, BACKLOG, InetAddress.getByName(HOST)),
                "http",
                requiredHeader,
            )

        /** HTTPS terminated with one of the TEST ONLY instrumentation certificates. */
        fun https(fixture: TestCertificateFixture): LoopbackMinifluxServer {
            val context = SSLContext.getInstance("TLS")
            context.init(fixture.keyManagers(), null, null)
            val socket = context.serverSocketFactory
                .createServerSocket(0, BACKLOG, InetAddress.getByName(HOST))
            return LoopbackMinifluxServer(socket, "https", null)
        }
    }
}

/** TEST ONLY certificate material loaded from `src/androidTest/resources`. */
enum class TestCertificateFixture(
    private val chainResource: String,
    private val keyResource: String,
) {
    /** Signed by the test CA that the user-installed-CA gate adds to the Android user store. */
    USER_INSTALLED_CA("flux-test-usertrust-server.crt", "flux-test-usertrust-server.pk8"),

    /** Self-signed and present in no trust store at all. */
    UNTRUSTED("flux-test-untrusted-server.crt", "flux-test-untrusted-server.pk8"),
    ;

    fun keyManagers(): Array<KeyManager> {
        val chain = CertificateFactory.getInstance("X.509")
            .generateCertificates(readResource(chainResource).inputStream())
            .map { it as X509Certificate }
            .toTypedArray()
        val key = KeyFactory.getInstance("RSA")
            .generatePrivate(PKCS8EncodedKeySpec(readResource(keyResource)))

        val keyStore = KeyStore.getInstance("PKCS12")
        keyStore.load(null, null)
        keyStore.setKeyEntry("flux-test-server", key, KEY_PASSWORD, chain)

        val factory = KeyManagerFactory.getInstance(KeyManagerFactory.getDefaultAlgorithm())
        factory.init(keyStore, KEY_PASSWORD)
        return factory.keyManagers
    }

    companion object {
        /** Resource name of the TEST ONLY CA the user-installed-CA gate expects on the device. */
        const val USER_CA_RESOURCE = "flux-test-user-ca.crt"

        private val KEY_PASSWORD = CharArray(0)

        fun readResource(name: String): ByteArray =
            checkNotNull(
                TestCertificateFixture::class.java.classLoader?.getResourceAsStream(name),
            ) { "Missing instrumentation test resource: $name" }.use { it.readBytes() }
    }
}
