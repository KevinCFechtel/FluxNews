#!/usr/bin/env python3
"""Prepare a native F-Droid candidate offline; never submit or modify historical recipes."""
import argparse
from pathlib import Path
import re

MARKER = "  # Native Flux 3.0 source-build candidate."
def parse_version_file(path):
    props = {}
    for line in path.read_text().splitlines():
        if not line.strip() or line.startswith("#"): continue
        key, sep, value = line.partition("=")
        if not sep or key not in ("VERSION_NAME", "BUILD_NUMBER") or key in props: raise ValueError("Malformed version file")
        props[key] = value
    name, number = props.get("VERSION_NAME", ""), props.get("BUILD_NUMBER", "")
    if not re.fullmatch(r"[0-9]+\.[0-9]+\.[0-9]+", name): raise ValueError("Bad version name")
    if not re.fullmatch(r"[1-9][0-9]*", number) or int(number) > 2100000000: raise ValueError("Bad Android version code")
    return name, int(number)

def prepare(text, name, number, sha):
    if not re.fullmatch(r"[0-9a-f]{40}", sha): raise ValueError("Source SHA must be exactly 40 lowercase hex characters")
    if text.count(MARKER) != 1: raise ValueError("Native recipe marker missing or duplicated")
    before, rest = text.split(MARKER, 1)
    native, separator, after = rest.partition("\nAllowedAPKSigningKeys:")
    if not separator or native.count("\n  - versionName:") != 1 or native.count("    subdir: android") != 1: raise ValueError("Ambiguous native build or signing block")
    updates = {
        r"(?m)^  - versionName: [^\n]+$": f"  - versionName: {name}",
        r"(?m)^    versionCode: [^\n]+$": f"    versionCode: {number}",
        r"(?m)^    commit: [^\n]+$": f"    commit: {sha}",
        r"(?m)^      - fluxBuildVersionCode=[^\n]+$": f"      - fluxBuildVersionCode={number}",
        r"(?m)^      - fluxBuildVersionName=[^\n]+$": f"      - fluxBuildVersionName={name}",
    }
    for pattern, replacement in updates.items():
        native, count = re.subn(pattern, lambda _: replacement, native)
        if count != 1: raise ValueError("Expected exactly one native field: " + pattern)
    return before + MARKER + native + separator + after

if __name__ == "__main__":
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument("--source-sha", required=True)
    p.add_argument("--output", type=Path, required=True)
    p.add_argument("--metadata", type=Path, default=Path("fdroid/metadata/de.circle_dev.flux_news.yml"))
    p.add_argument("--version-file", type=Path, default=Path("Build/versions/android.properties"))
    args = p.parse_args()
    if args.output.resolve() == args.metadata.resolve(): p.error("Cannot overwrite committed metadata")
    try:
        name, number = parse_version_file(args.version_file)
        prepared = prepare(args.metadata.read_text(), name, number, args.source_sha)
    except (ValueError, OSError) as err: p.error(str(err))
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(prepared)
    print(f"Validated native recipe {name}/{number} at {args.source_sha}")
