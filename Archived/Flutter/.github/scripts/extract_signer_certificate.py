#!/usr/bin/env python3

import argparse
import base64
import hashlib
import os
import re
import shutil
import subprocess
import sys
from pathlib import Path


CERTIFICATE_PATTERN = re.compile(
    r"-----BEGIN CERTIFICATE-----\s*(.*?)\s*-----END CERTIFICATE-----",
    re.DOTALL,
)


def normalize_fingerprint(value):
    fingerprint = value.replace(":", "").strip().lower()
    if not re.fullmatch(r"[0-9a-f]{64}", fingerprint):
        raise ValueError("expected SHA-256 fingerprint must contain 64 hex characters")
    return fingerprint


def decode_certificates(output):
    certificates = []
    for encoded in CERTIFICATE_PATTERN.findall(output):
        compact = re.sub(r"\s+", "", encoded)
        certificates.append(base64.b64decode(compact, validate=True))
    return certificates


def _version_key(path):
    return tuple(
        (0, int(part)) if part.isdigit() else (1, part.lower())
        for part in re.split(r"(\d+)", path.parent.name)
    )


def find_apksigner(explicit_path=None):
    if explicit_path:
        candidate = Path(explicit_path)
        if candidate.is_file():
            return candidate
        raise FileNotFoundError("apksigner not found at {}".format(candidate))

    command = shutil.which("apksigner")
    if command:
        return Path(command)

    candidates = []
    for variable in ("ANDROID_HOME", "ANDROID_SDK_ROOT"):
        sdk_root = os.environ.get(variable)
        if sdk_root:
            candidates.extend(Path(sdk_root).glob("build-tools/*/apksigner"))

    candidates = [candidate for candidate in candidates if candidate.is_file()]
    if not candidates:
        raise FileNotFoundError(
            "apksigner not found in PATH, ANDROID_HOME, or ANDROID_SDK_ROOT"
        )
    return max(candidates, key=_version_key)


def extract_signer_certificate(
    apk_path,
    output_path,
    expected_fingerprint,
    apksigner_path=None,
):
    apk = Path(apk_path)
    output = Path(output_path)
    if not apk.is_file():
        raise FileNotFoundError("APK not found: {}".format(apk))

    expected = normalize_fingerprint(expected_fingerprint)
    apksigner = find_apksigner(apksigner_path)
    result = subprocess.run(
        [str(apksigner), "verify", "--print-certs-pem", str(apk)],
        check=False,
        capture_output=True,
        text=True,
    )
    if result.returncode != 0:
        details = (result.stderr or result.stdout).strip()
        raise RuntimeError("apksigner verification failed: {}".format(details))

    certificates = decode_certificates(result.stdout)
    if not certificates:
        raise RuntimeError("apksigner returned no PEM signing certificate")

    matches = {
        certificate
        for certificate in certificates
        if hashlib.sha256(certificate).hexdigest() == expected
    }
    if not matches:
        observed = sorted(
            hashlib.sha256(certificate).hexdigest()
            for certificate in certificates
        )
        raise RuntimeError(
            "APK signer fingerprint mismatch; expected {}, observed {}".format(
                expected,
                ", ".join(observed),
            )
        )
    if len(matches) != 1:
        raise RuntimeError("APK contains ambiguous matching signer certificates")

    certificate = matches.pop()
    output.parent.mkdir(parents=True, exist_ok=True)
    temporary = output.with_name(output.name + ".tmp")
    temporary.write_bytes(certificate)
    temporary.replace(output)
    return expected


def main():
    parser = argparse.ArgumentParser(
        description="Extract and verify the F-Droid signer-certificate.der file"
    )
    parser.add_argument("--apk", required=True)
    parser.add_argument("--output", required=True)
    parser.add_argument("--expected-sha256", required=True)
    parser.add_argument("--apksigner")
    args = parser.parse_args()

    try:
        fingerprint = extract_signer_certificate(
            args.apk,
            args.output,
            args.expected_sha256,
            args.apksigner,
        )
    except (FileNotFoundError, RuntimeError, ValueError) as error:
        print("error: {}".format(error), file=sys.stderr)
        return 1

    print(
        "Saved verified signer certificate {} to {}".format(
            fingerprint,
            args.output,
        )
    )
    return 0


if __name__ == "__main__":
    sys.exit(main())
