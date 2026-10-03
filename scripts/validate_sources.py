#!/usr/bin/env python3
"""Portable structural checks that can run before the Xcode/macOS build."""

from __future__ import annotations

import json
import plistlib
from pathlib import Path


ROOT = Path(__file__).resolve().parent.parent


def masked_swift(source: str) -> str:
    output: list[str] = []
    index = 0
    block_depth = 0
    state = "code"

    while index < len(source):
        pair = source[index : index + 2]
        triple = source[index : index + 3]

        if state == "code":
            if pair == "//":
                state = "line_comment"
                output.extend("  ")
                index += 2
                continue
            if pair == "/*":
                state = "block_comment"
                block_depth = 1
                output.extend("  ")
                index += 2
                continue
            if triple == '\"\"\"':
                state = "multiline_string"
                output.extend("   ")
                index += 3
                continue
            if source[index] == '"':
                state = "string"
                output.append(" ")
                index += 1
                continue
            output.append(source[index])
            index += 1
            continue

        if state == "line_comment":
            if source[index] == "\n":
                state = "code"
                output.append("\n")
            else:
                output.append(" ")
            index += 1
            continue

        if state == "block_comment":
            if pair == "/*":
                block_depth += 1
                output.extend("  ")
                index += 2
            elif pair == "*/":
                block_depth -= 1
                output.extend("  ")
                index += 2
                if block_depth == 0:
                    state = "code"
            else:
                output.append("\n" if source[index] == "\n" else " ")
                index += 1
            continue

        if state == "string":
            if source[index] == "\\" and index + 1 < len(source):
                output.extend("  ")
                index += 2
            elif source[index] == '"':
                state = "code"
                output.append(" ")
                index += 1
            else:
                output.append("\n" if source[index] == "\n" else " ")
                index += 1
            continue

        if state == "multiline_string":
            if triple == '\"\"\"':
                state = "code"
                output.extend("   ")
                index += 3
            else:
                output.append("\n" if source[index] == "\n" else " ")
                index += 1

    if state in {"block_comment", "string", "multiline_string"}:
        raise ValueError(f"unterminated Swift token: {state}")
    return "".join(output)


def validate_delimiters(path: Path) -> None:
    source = masked_swift(path.read_text(encoding="utf-8"))
    matching = {")": "(", "]": "[", "}": "{"}
    stack: list[tuple[str, int]] = []

    for line_number, line in enumerate(source.splitlines(), start=1):
        for character in line:
            if character in "([{":
                stack.append((character, line_number))
            elif character in matching:
                if not stack or stack[-1][0] != matching[character]:
                    raise ValueError(f"{path}:{line_number}: unmatched {character}")
                stack.pop()

    if stack:
        character, line_number = stack[-1]
        raise ValueError(f"{path}:{line_number}: unclosed {character}")


def main() -> None:
    swift_files = sorted(ROOT.rglob("*.swift"))
    for path in swift_files:
        validate_delimiters(path)

    plist_files = sorted([*ROOT.rglob("*.plist"), *ROOT.rglob("*.entitlements"), *ROOT.rglob("*.xcprivacy")])
    for path in plist_files:
        with path.open("rb") as handle:
            plistlib.load(handle)

    json_files = sorted(ROOT.rglob("Contents.json"))
    for path in json_files:
        json.loads(path.read_text(encoding="utf-8"))

    project = (ROOT / "project.yml").read_text(encoding="utf-8")
    required_project_tokens = [
        "PawPace:",
        "PawPaceWidgets:",
        "PawPaceLiveActivity:",
        "PawPaceTests:",
        "PawPaceWatch:",
        "Config/PawPace-Info.plist",
        "Config/PawPaceWidgets-Info.plist",
        "Config/PawPaceWatch-Info.plist",
        "Config/PawPaceWatch.entitlements",
        "destination: productsDirectory",
        'subpath: "$(CONTENTS_FOLDER_PATH)/Watch"',
    ]
    missing = [token for token in required_project_tokens if token not in project]
    if missing:
        raise ValueError(f"project.yml is missing: {', '.join(missing)}")

    print(
        f"Validated {len(swift_files)} Swift files, "
        f"{len(plist_files)} property lists, and {len(json_files)} asset catalogs."
    )


if __name__ == "__main__":
    main()
