#!/usr/bin/env python3

from __future__ import annotations

import argparse
import re
from dataclasses import dataclass
from pathlib import Path


class MetadataError(RuntimeError):
    pass


@dataclass(frozen=True)
class AbiSpec:
    name: str
    offset: int
    markers: tuple[str, ...]


ABI_SPECS = (
    AbiSpec("x86_64", 1, ("app-x86_64-release.apk", "android-x64")),
    AbiSpec("armeabi_v7a", 2, ("app-armeabi-v7a-release.apk", "android-arm\"")),
    AbiSpec("arm64_v8a", 3, ("app-arm64-v8a-release.apk", "android-arm64")),
)

TOP_LEVEL_FIELD = re.compile(r"^[A-Za-z][A-Za-z0-9]*:")
BUILD_START = re.compile(r"^  - versionName:\s*(.+?)\s*$")


@dataclass
class BuildBlock:
    start: int
    end: int
    lines: list[str]
    version_name: str
    version_code: int
    commit: str
    abi: str | None
    disabled: bool


def _parse_scalar(value: str) -> str:
    value = value.strip()
    if len(value) >= 2 and value[0] == value[-1] and value[0] in "\"'":
        return value[1:-1]
    return value


def _field_value(lines: list[str], field: str) -> str:
    pattern = re.compile(rf"^    {re.escape(field)}:\s*(.+?)\s*$")
    matches = [pattern.match(line.rstrip("\r\n")) for line in lines]
    values = [match.group(1) for match in matches if match]
    if len(values) != 1:
        raise MetadataError(
            f"Expected exactly one {field} field in a build block, found {len(values)}"
        )
    return _parse_scalar(values[0])


def _classify_abi(lines: list[str]) -> str | None:
    text = "".join(lines)
    matches = [
        spec.name
        for spec in ABI_SPECS
        if any(marker in text for marker in spec.markers)
    ]
    if len(matches) > 1:
        raise MetadataError(f"Build block matches multiple ABIs: {matches}")
    return matches[0] if matches else None


def _find_builds(lines: list[str]) -> tuple[list[BuildBlock], int]:
    try:
        builds_header = next(
            index
            for index, line in enumerate(lines)
            if line.rstrip("\r\n") == "Builds:"
        )
    except StopIteration as error:
        raise MetadataError("Builds section is missing") from error

    builds_end = next(
        (
            index
            for index in range(builds_header + 1, len(lines))
            if TOP_LEVEL_FIELD.match(lines[index])
        ),
        len(lines),
    )
    starts = [
        index
        for index in range(builds_header + 1, builds_end)
        if BUILD_START.match(lines[index].rstrip("\r\n"))
    ]
    if not starts:
        raise MetadataError("Builds section has no build blocks")

    blocks = []
    for position, start in enumerate(starts):
        end = starts[position + 1] if position + 1 < len(starts) else builds_end
        block_lines = lines[start:end]
        version_match = BUILD_START.match(block_lines[0].rstrip("\r\n"))
        if version_match is None:
            raise MetadataError("Could not parse versionName")
        blocks.append(
            BuildBlock(
                start=start,
                end=end,
                lines=block_lines,
                version_name=_parse_scalar(version_match.group(1)),
                version_code=int(_field_value(block_lines, "versionCode")),
                commit=_field_value(block_lines, "commit"),
                abi=_classify_abi(block_lines),
                disabled=any(
                    re.match(r"^    disable:", line) for line in block_lines
                ),
            )
        )
    return blocks, builds_end


def _replace_indented_field(
    lines: list[str], field: str, value: str
) -> list[str]:
    pattern = re.compile(
        rf"^(\s*(?:-\s+)?{re.escape(field)}:\s*).*(\r?\n?)$"
    )
    result = list(lines)
    matches = []
    for index, line in enumerate(result):
        match = pattern.match(line)
        if match:
            matches.append(index)
            result[index] = f"{match.group(1)}{value}{match.group(2)}"
    if len(matches) != 1:
        raise MetadataError(
            f"Expected exactly one {field} field, found {len(matches)}"
        )
    return result


def _clone_build(
    template: BuildBlock, version: str, version_code: int, commit: str
) -> list[str]:
    lines = _replace_indented_field(template.lines, "versionName", version)
    lines = _replace_indented_field(lines, "versionCode", str(version_code))
    lines = _replace_indented_field(lines, "commit", commit)
    while lines and not lines[-1].strip():
        lines.pop()
    lines.append("\n")
    return lines


def _replace_top_level_field(
    lines: list[str], field: str, value: str
) -> None:
    pattern = re.compile(rf"^({re.escape(field)}:\s*).*(\r?\n?)$")
    matches = []
    for index, line in enumerate(lines):
        match = pattern.match(line)
        if match:
            matches.append(index)
            lines[index] = f"{match.group(1)}{value}{match.group(2)}"
    if len(matches) != 1:
        raise MetadataError(
            f"Expected exactly one {field} field, found {len(matches)}"
        )


def _top_level_section(lines: list[str], field: str) -> tuple[int, int] | None:
    start_pattern = re.compile(rf"^{re.escape(field)}:")
    starts = [index for index, line in enumerate(lines) if start_pattern.match(line)]
    if not starts:
        return None
    if len(starts) != 1:
        raise MetadataError(f"Expected at most one {field} section")
    start = starts[0]
    end = next(
        (
            index
            for index in range(start + 1, len(lines))
            if TOP_LEVEL_FIELD.match(lines[index])
        ),
        len(lines),
    )
    return start, end


def _ensure_signing_keys(
    lines: list[str], developer_key: str, fdroid_key: str
) -> None:
    expected = (developer_key.lower(), fdroid_key.lower())
    for key in expected:
        if not re.fullmatch(r"[0-9a-f]{64}", key):
            raise MetadataError(f"Invalid SHA-256 signing key: {key}")

    section = _top_level_section(lines, "AllowedAPKSigningKeys")
    if section is None:
        auto_update = _top_level_section(lines, "AutoUpdateMode")
        if auto_update is None:
            raise MetadataError("AutoUpdateMode field is missing")
        insertion = auto_update[0]
        lines[insertion:insertion] = [
            "AllowedAPKSigningKeys:\n",
            *(f"  - {key}\n" for key in expected),
            "\n",
        ]
        return

    _, end = section
    existing = {
        match.group(1).lower()
        for line in lines[section[0] + 1 : end]
        if (match := re.match(r"^\s+-\s+([0-9a-fA-F]{64})\s*$", line))
    }
    missing = [key for key in expected if key not in existing]
    if missing:
        insertion = end
        while insertion > section[0] + 1 and not lines[insertion - 1].strip():
            insertion -= 1
        lines[insertion:insertion] = [f"  - {key}\n" for key in missing]


def _validate_vercode_operations(lines: list[str]) -> None:
    section = _top_level_section(lines, "VercodeOperation")
    if section is None:
        raise MetadataError("VercodeOperation section is missing")
    values = [
        _parse_scalar(match.group(1))
        for line in lines[section[0] + 1 : section[1]]
        if (match := re.match(r"^\s+-\s+(.+?)\s*$", line.rstrip("\r\n")))
    ]
    expected = ["%c + 1", "%c + 2", "%c + 3"]
    if values != expected:
        raise MetadataError(
            f"Unexpected VercodeOperation values: {values}; expected {expected}"
        )


def prepare_metadata(
    text: str,
    version: str,
    base_version_code: int,
    commit: str,
    developer_key: str,
    fdroid_key: str,
) -> tuple[str, bool]:
    if not re.fullmatch(r"[0-9a-f]{40}", commit):
        raise MetadataError("Release commit must be a full 40-character Git SHA")

    lines = text.splitlines(keepends=True)
    if lines and not lines[-1].endswith(("\n", "\r")):
        lines[-1] += "\n"

    _validate_vercode_operations(lines)
    blocks, builds_end = _find_builds(lines)
    desired_codes = {
        spec.name: base_version_code + spec.offset for spec in ABI_SPECS
    }
    existing_codes = {block.version_code: block for block in blocks}
    present = {
        abi
        for abi, version_code in desired_codes.items()
        if version_code in existing_codes
    }

    builds_added = False
    if present and len(present) != len(ABI_SPECS):
        raise MetadataError(
            f"Only part of the release build entries exists: {sorted(present)}"
        )

    if present:
        for abi, version_code in desired_codes.items():
            block = existing_codes[version_code]
            if block.abi != abi:
                raise MetadataError(
                    f"Version code {version_code} is {block.abi}, expected {abi}"
                )
            if block.version_name != version:
                raise MetadataError(
                    f"Version code {version_code} has version "
                    f"{block.version_name}, expected {version}"
                )
            if block.commit != commit:
                raise MetadataError(
                    f"Version code {version_code} uses commit "
                    f"{block.commit}, expected {commit}"
                )
            if block.disabled:
                raise MetadataError(f"Version code {version_code} is disabled")
    else:
        templates: dict[str, BuildBlock] = {}
        for block in reversed(blocks):
            if block.abi and not block.disabled and block.abi not in templates:
                templates[block.abi] = block
            if len(templates) == len(ABI_SPECS):
                break

        missing_templates = [
            spec.name for spec in ABI_SPECS if spec.name not in templates
        ]
        if missing_templates:
            raise MetadataError(
                f"Missing latest build templates for: {missing_templates}"
            )

        template_versions = {template.version_name for template in templates.values()}
        if len(template_versions) != 1:
            raise MetadataError(
                f"Latest ABI templates use different versions: {template_versions}"
            )

        new_blocks = []
        for spec in ABI_SPECS:
            new_blocks.extend(
                _clone_build(
                    templates[spec.name],
                    version,
                    desired_codes[spec.name],
                    commit,
                )
            )
        lines[builds_end:builds_end] = new_blocks
        builds_added = True

    _ensure_signing_keys(lines, developer_key, fdroid_key)
    _replace_top_level_field(lines, "AutoUpdateMode", "None")
    _replace_top_level_field(lines, "CurrentVersion", version)
    _replace_top_level_field(
        lines, "CurrentVersionCode", str(desired_codes["arm64_v8a"])
    )
    return "".join(lines), builds_added


def main() -> None:
    parser = argparse.ArgumentParser(
        description="Prepare Flux News fdroiddata metadata for a signed release"
    )
    parser.add_argument("--metadata", required=True, type=Path)
    parser.add_argument("--version", required=True)
    parser.add_argument("--base-version-code", required=True, type=int)
    parser.add_argument("--commit", required=True)
    parser.add_argument("--developer-key", required=True)
    parser.add_argument("--fdroid-key", required=True)
    args = parser.parse_args()

    original = args.metadata.read_text(encoding="utf-8")
    updated, builds_added = prepare_metadata(
        original,
        args.version,
        args.base_version_code,
        args.commit,
        args.developer_key,
        args.fdroid_key,
    )
    args.metadata.write_text(updated, encoding="utf-8")
    action = "added new ABI build entries" if builds_added else "reused ABI build entries"
    print(f"Prepared {args.version}: {action}")


if __name__ == "__main__":
    main()
