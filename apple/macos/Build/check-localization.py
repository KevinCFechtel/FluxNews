#!/usr/bin/env python3
"""Check macOS Xcode catalog and untranslated Weblate XLIFF handoff."""
import json
import pathlib
import sys
import xml.etree.ElementTree as ET

ROOT = pathlib.Path(__file__).resolve().parents[1]
CATALOG = ROOT / "FluxNews" / "Localizable.xcstrings"
HANDOFF = ROOT / "Weblate"
LANGUAGES = ("es", "gl", "nl", "ta", "tr")
IGNORED = {"", "%@", "%arg", "·", "https://example.com"}


def main() -> int:
    catalog = json.loads(CATALOG.read_text(encoding="utf-8"))
    assert catalog["sourceLanguage"] == "en"
    entries = catalog["strings"]
    expected = set(entries) - IGNORED
    problems = []
    for key, value in entries.items():
        if key in IGNORED:
            continue
        de = value.get("localizations", {}).get("de", {}).get("stringUnit", {})
        if de.get("state") != "translated" or not de.get("value", "").strip():
            problems.append(f"German incomplete: {key}")
        for language in LANGUAGES:
            if language in value.get("localizations", {}):
                problems.append(f"Unreviewed locale has catalog values: {language} / {key}")
    ns = {"x": "urn:oasis:names:tc:xliff:document:1.2"}
    for language in LANGUAGES:
        path = HANDOFF / f"{language}.xliff"
        root = ET.parse(path).getroot()
        file = root.find("x:file", ns)
        if file is None or file.get("target-language") != language or file.get("source-language") != "en":
            problems.append(f"Wrong XLIFF language: {path}")
            continue
        units = file.findall(".//x:trans-unit", ns)
        keys = [unit.get("id") for unit in units]
        if len(keys) != len(set(keys)) or set(keys) != expected:
            problems.append(f"XLIFF source units do not match catalog: {language}")
        for unit in units:
            source = unit.find("x:source", ns)
            target = unit.find("x:target", ns)
            if source is None or source.text != unit.get("id") or target is not None:
                problems.append(f"Unexpected source/target value: {language} / {unit.get('id')}")
    if problems:
        print("\n".join(problems), file=sys.stderr)
        return 1
    print(f"macOS localization: {len(expected)} source strings, German complete; 5 untranslated XLIFF targets ready.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
