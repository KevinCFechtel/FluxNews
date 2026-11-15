# TEST ONLY — NOT FOR PRODUCTION

Every file in this directory is an Android instrumentation fixture for the E1-C transport proof.
The private keys here are throwaway keys generated for local loopback test servers. They carry no
production value, must never be copied into `src/main`, a production APK or a release asset, and
must never be used as a trust anchor for anything but these tests.

| File | Contents |
| --- | --- |
| `flux-test-user-ca.crt` | PEM certificate of the test CA that the user-installed-CA gate installs into the Android user trust store. |
| `flux-test-usertrust-server.crt` | PEM chain (leaf + test CA) for the loopback HTTPS server used by the user-CA gate. |
| `flux-test-usertrust-server.pk8` | PKCS#8 DER **test** private key for that leaf. |
| `flux-test-untrusted-server.crt` | PEM self-signed leaf that no trust store ever contains, used by the invalid-certificate gate. |
| `flux-test-untrusted-server.pk8` | PKCS#8 DER **test** private key for that leaf. |

Both leaves carry `subjectAltName = DNS:localhost, IP:127.0.0.1` and `extendedKeyUsage = serverAuth`,
which is what rustls and the Android verifier require. They are RSA-2048/SHA-256 and valid until
2046 so the fixtures do not expire during the lifetime of this project.

They were produced with OpenSSL:

```
openssl req -x509 -newkey rsa:2048 -nodes -sha256 -days 7300 \
  -keyout user-ca.key -out flux-test-user-ca.crt \
  -subj "/CN=Flux TEST ONLY User CA/O=Flux Instrumentation Tests" \
  -addext "basicConstraints=critical,CA:TRUE,pathlen:0" \
  -addext "keyUsage=critical,keyCertSign,cRLSign"

openssl req -newkey rsa:2048 -nodes -sha256 -keyout server.key -out server.csr \
  -subj "/CN=localhost/O=Flux Instrumentation Tests"
openssl x509 -req -in server.csr -CA flux-test-user-ca.crt -CAkey user-ca.key -CAcreateserial \
  -days 7300 -sha256 -out server.crt \
  -extfile <(printf 'basicConstraints=critical,CA:FALSE\nkeyUsage=critical,digitalSignature,keyEncipherment\nextendedKeyUsage=serverAuth\nsubjectAltName=DNS:localhost,IP:127.0.0.1\n')
openssl pkcs8 -topk8 -nocrypt -in server.key -outform DER -out flux-test-usertrust-server.pk8
```

The CA private key is deliberately not kept anywhere in this repository.
