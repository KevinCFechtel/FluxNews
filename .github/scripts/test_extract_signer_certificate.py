#!/usr/bin/env python3

import base64
import hashlib
import subprocess
import tempfile
import unittest
from pathlib import Path
from unittest import mock

import extract_signer_certificate


def pem(certificate):
    encoded = base64.b64encode(certificate).decode("ascii")
    return (
        "Signer certificate:\n"
        "-----BEGIN CERTIFICATE-----\n"
        "{}\n"
        "-----END CERTIFICATE-----\n"
    ).format(encoded)


class ExtractSignerCertificateTest(unittest.TestCase):
    def setUp(self):
        self.temporary_directory = tempfile.TemporaryDirectory()
        self.root = Path(self.temporary_directory.name)
        self.apk = self.root / "release.apk"
        self.apk.write_bytes(b"apk")

    def tearDown(self):
        self.temporary_directory.cleanup()

    def run_extraction(self, certificates, expected):
        output = self.root / "signer-certificate.der"
        completed = subprocess.CompletedProcess(
            args=[],
            returncode=0,
            stdout="".join(pem(certificate) for certificate in certificates),
            stderr="",
        )
        with mock.patch.object(
            extract_signer_certificate,
            "find_apksigner",
            return_value=Path("/fake/apksigner"),
        ), mock.patch.object(
            extract_signer_certificate.subprocess,
            "run",
            return_value=completed,
        ):
            extract_signer_certificate.extract_signer_certificate(
                self.apk,
                output,
                expected,
            )
        return output

    def test_extracts_certificate_with_expected_fingerprint(self):
        certificate = b"developer-certificate"
        expected = hashlib.sha256(certificate).hexdigest()

        output = self.run_extraction([certificate], expected.upper())

        self.assertEqual(certificate, output.read_bytes())

    def test_selects_expected_certificate_from_multiple_signers(self):
        expected_certificate = b"expected"
        expected = hashlib.sha256(expected_certificate).hexdigest()

        output = self.run_extraction(
            [b"historical", expected_certificate],
            expected,
        )

        self.assertEqual(expected_certificate, output.read_bytes())

    def test_rejects_unexpected_signer(self):
        expected = hashlib.sha256(b"expected").hexdigest()

        with self.assertRaisesRegex(RuntimeError, "fingerprint mismatch"):
            self.run_extraction([b"unexpected"], expected)

    def test_rejects_invalid_expected_fingerprint(self):
        with self.assertRaisesRegex(ValueError, "64 hex characters"):
            extract_signer_certificate.normalize_fingerprint("not-a-fingerprint")


if __name__ == "__main__":
    unittest.main()
