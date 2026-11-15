#!/usr/bin/env python3
"""Export, validate, and import the iOS Weblate XLIFF handoff.

The runtime source of truth remains FluxNews/Localizable.xcstrings. The XLIFF
files are bilingual handoff files for Weblate and are intentionally not bundled
into the app.
"""
from __future__ import annotations

import argparse
import json
import pathlib
import re
import sys
import xml.etree.ElementTree as ET
from dataclasses import dataclass

ROOT = pathlib.Path(__file__).resolve().parents[1]
CATALOG = ROOT / "FluxNews" / "Localizable.xcstrings"
HANDOFF = ROOT / "Weblate"
LANGUAGES = ("de", "es", "gl", "nl", "ta", "tr")
PLURAL_ORDER = ("zero", "one", "two", "few", "many", "other")
PLURAL_MARKER = " |==|plural."
NS = "urn:oasis:names:tc:xliff:document:1.2"
XSI = "http://www.w3.org/2001/XMLSchema-instance"
XML = "http://www.w3.org/XML/1998/namespace"
NEEDS_EDIT = {"new", "needs-translation", "needs-adaptation", "needs-l10n"}
PLACEHOLDER = re.compile(r"%(?:\d+\$)?(lld|ld|d|@|s|f|arg)")

ET.register_namespace("", NS)
ET.register_namespace("xsi", XSI)


@dataclass(frozen=True)
class Unit:
    unit_id: str
    key: str
    category: str | None
    source: str


def load_catalog() -> dict:
    data = json.loads(CATALOG.read_text(encoding="utf-8"))
    if data.get("sourceLanguage") != "en":
        raise ValueError("iOS String Catalog sourceLanguage must remain en")
    return data


def source_units(catalog: dict) -> list[Unit]:
    result: list[Unit] = []
    for key in sorted(catalog["strings"]):
        entry = catalog["strings"][key]
        en = entry.get("localizations", {}).get("en")
        plural = (en or {}).get("variations", {}).get("plural")
        if plural:
            categories = sorted(
                plural,
                key=lambda item: (
                    PLURAL_ORDER.index(item) if item in PLURAL_ORDER else len(PLURAL_ORDER),
                    item,
                ),
            )
            for category in categories:
                value = plural[category].get("stringUnit", {}).get("value")
                if not isinstance(value, str):
                    raise ValueError(f"Missing English plural value: {key} / {category}")
                result.append(Unit(f"{key}{PLURAL_MARKER}{category}", key, category, value))
            continue

        value = (en or {}).get("stringUnit", {}).get("value", key)
        result.append(Unit(key, key, None, value))
    return result


def target_unit(entry: dict, language: str, category: str | None) -> dict | None:
    localization = entry.get("localizations", {}).get(language)
    if not localization:
        return None
    if category is None:
        unit = localization.get("stringUnit")
    else:
        unit = localization.get("variations", {}).get("plural", {}).get(category, {}).get("stringUnit")
    if not unit or not isinstance(unit.get("value"), str) or not unit["value"]:
        return None
    return unit


def make_tree(catalog: dict, language: str) -> ET.ElementTree:
    root = ET.Element(
        f"{{{NS}}}xliff",
        {
            "version": "1.2",
            f"{{{XSI}}}schemaLocation": (
                "urn:oasis:names:tc:xliff:document:1.2 "
                "http://docs.oasis-open.org/xliff/v1.2/os/xliff-core-1.2-strict.xsd"
            ),
        },
    )
    file_element = ET.SubElement(
        root,
        f"{{{NS}}}file",
        {
            "original": "Localizable.xcstrings",
            "source-language": "en",
            "target-language": language,
            "datatype": "plaintext",
        },
    )
    header = ET.SubElement(file_element, f"{{{NS}}}header")
    ET.SubElement(
        header,
        f"{{{NS}}}tool",
        {
            "tool-id": "dev.kevincfechtel.fluxnews.weblate-handoff",
            "tool-name": "FluxNews Weblate handoff",
            "tool-version": "1",
        },
    )
    body = ET.SubElement(file_element, f"{{{NS}}}body")
    for unit in source_units(catalog):
        trans = ET.SubElement(
            body,
            f"{{{NS}}}trans-unit",
            {"id": unit.unit_id, f"{{{XML}}}space": "preserve"},
        )
        source = ET.SubElement(trans, f"{{{NS}}}source")
        source.text = unit.source
        target_data = target_unit(catalog["strings"][unit.key], language, unit.category)
        if target_data:
            target = ET.SubElement(
                trans,
                f"{{{NS}}}target",
                {"state": "needs-l10n" if target_data.get("state") == "needs_review" else "translated"},
            )
            target.text = target_data["value"]
        if unit.category:
            note = ET.SubElement(trans, f"{{{NS}}}note")
            note.text = f"Plural form: {unit.category}"
    ET.indent(root, space="  ")
    return ET.ElementTree(root)


def export_handoff() -> int:
    catalog = load_catalog()
    HANDOFF.mkdir(parents=True, exist_ok=True)
    for language in LANGUAGES:
        tree = make_tree(catalog, language)
        tree.write(
            HANDOFF / f"{language}.xliff",
            encoding="utf-8",
            xml_declaration=True,
            short_empty_elements=True,
        )
    return check_handoff()


def normalized_placeholders(value: str) -> list[str]:
    return sorted(match.group(1) for match in PLACEHOLDER.finditer(value))


def read_units(path: pathlib.Path, language: str) -> tuple[ET.Element, dict[str, ET.Element]]:
    root = ET.parse(path).getroot()
    file_element = root.find(f"{{{NS}}}file")
    if file_element is None:
        raise ValueError(f"Missing XLIFF file element: {path}")
    if file_element.get("source-language") != "en" or file_element.get("target-language") != language:
        raise ValueError(f"Wrong XLIFF language declaration: {path}")
    if file_element.get("original") != "Localizable.xcstrings":
        raise ValueError(f"Wrong XLIFF original: {path}")
    units: dict[str, ET.Element] = {}
    for element in file_element.findall(f".//{{{NS}}}trans-unit"):
        unit_id = element.get("id")
        if not unit_id or unit_id in units:
            raise ValueError(f"Missing or duplicate XLIFF id: {path} / {unit_id!r}")
        units[unit_id] = element
    return file_element, units


def check_handoff() -> int:
    catalog = load_catalog()
    expected = {unit.unit_id: unit for unit in source_units(catalog)}
    problems: list[str] = []
    translated = 0
    needs_review = 0
    missing = 0

    for language in LANGUAGES:
        path = HANDOFF / f"{language}.xliff"
        if not path.exists():
            problems.append(f"Missing XLIFF handoff: {path}")
            continue
        try:
            _, actual = read_units(path, language)
        except (ET.ParseError, ValueError) as error:
            problems.append(str(error))
            continue

        if set(actual) != set(expected):
            missing_ids = sorted(set(expected) - set(actual))
            extra_ids = sorted(set(actual) - set(expected))
            problems.append(
                f"XLIFF unit set differs for {language}: "
                f"missing={missing_ids[:3]} extra={extra_ids[:3]}"
            )
            continue

        for unit_id, expected_unit in expected.items():
            trans = actual[unit_id]
            source = trans.find(f"{{{NS}}}source")
            if source is None or (source.text or "") != expected_unit.source:
                problems.append(f"Source mismatch: {language} / {unit_id}")
                continue
            target = trans.find(f"{{{NS}}}target")
            if target is None:
                missing += 1
                continue
            value = target.text or ""
            if not value:
                problems.append(f"Empty target: {language} / {unit_id}")
                continue
            if normalized_placeholders(value) != normalized_placeholders(expected_unit.source):
                problems.append(f"Placeholder mismatch: {language} / {unit_id}")
            if target.get("state") in NEEDS_EDIT:
                needs_review += 1
            else:
                translated += 1

    if problems:
        print("\n".join(problems), file=sys.stderr)
        return 1
    print(
        "iOS Weblate handoff: "
        f"{len(expected)} source units across {len(LANGUAGES)} languages; "
        f"translated={translated}, needs-review={needs_review}, missing={missing}."
    )
    return 0


def import_handoff() -> int:
    catalog = load_catalog()
    expected = {unit.unit_id: unit for unit in source_units(catalog)}
    if check_handoff() != 0:
        return 1

    for language in LANGUAGES:
        _, actual = read_units(HANDOFF / f"{language}.xliff", language)
        for unit_id, unit in expected.items():
            target = actual[unit_id].find(f"{{{NS}}}target")
            if target is None or not (target.text or ""):
                continue
            state = "needs_review" if target.get("state") in NEEDS_EDIT else "translated"
            entry = catalog["strings"][unit.key]
            localizations = entry.setdefault("localizations", {})
            localization = localizations.setdefault(language, {})
            if unit.category is None:
                localization["stringUnit"] = {"state": state, "value": target.text}
            else:
                plural = localization.setdefault("variations", {}).setdefault("plural", {})
                plural[unit.category] = {
                    "stringUnit": {"state": state, "value": target.text}
                }

    CATALOG.write_text(
        json.dumps(catalog, ensure_ascii=False, indent=2) + "\n",
        encoding="utf-8",
    )
    print(f"Imported Weblate targets into {CATALOG}. Run the iOS test gate before merging.")
    return 0


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("action", choices=("check", "export", "import"))
    args = parser.parse_args()
    if args.action == "check":
        return check_handoff()
    if args.action == "export":
        return export_handoff()
    return import_handoff()


if __name__ == "__main__":
    raise SystemExit(main())
