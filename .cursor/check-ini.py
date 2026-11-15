#!/usr/bin/env python3
"""Check that an rdpwrap.ini file is internally consistent.

Version sections name patch codes and offsets. Each code name must exist in
[PatchCodes], and each offset must be hexadecimal. This does not apply any
configuration; it only checks the file the repository already ships.
"""

import re
import sys
from pathlib import Path

SECTION_RE = re.compile(
    r"^(?:Main|SLPolicy|PatchCodes|SLInit|\d+\.\d+\.X\.X|\d+\.\d+\.\d+\.\d+(?:-[A-Za-z0-9]+)?)$"
)
VERSION_RE = re.compile(r"^\d+\.\d+\.\d+\.\d+(?:-[A-Za-z0-9]+)?$")
CODE_RE = re.compile(r"Code\.(x86|x64|arm)$")
OFFSET_RE = re.compile(r"Offset\.(x86|x64|arm)$")
PATCH_RE = re.compile(r"Patch\.(x86|x64|arm)$")
HEX_RE = re.compile(r"^[0-9A-Fa-f]+$")
DATE_RE = re.compile(r"^\d{4}-\d{2}-\d{2}$")


def parse_ini(text):
    sections = []
    current = None
    for line_no, raw in enumerate(text.splitlines(), 1):
        line = raw.strip()
        if not line or line.startswith(";"):
            continue
        if line.startswith("[") and line.endswith("]"):
            name = line[1:-1].strip()
            current = {"name": name, "line": line_no, "items": []}
            sections.append(current)
            continue
        if "=" not in line:
            # The C++ parser ignores remark lines that are not comments,
            # sections, or key=value pairs.
            continue
        if current is None:
            raise ValueError(f"{line_no}: key=value before any section")
        key, value = line.split("=", 1)
        current["items"].append((key.strip(), value.strip(), line_no))
    return sections


def check(path: Path):
    errors = []
    sections = parse_ini(path.read_text(encoding="utf-8", errors="replace"))
    by_name = {}
    for section in sections:
        if not SECTION_RE.match(section["name"]):
            errors.append(f"{path}:{section['line']}: unexpected section [{section['name']}]")
        by_name.setdefault(section["name"], section)

    for required in ("Main", "SLPolicy", "PatchCodes"):
        if required not in by_name:
            errors.append(f"{path}: missing [{required}]")

    updated = None
    if "Main" in by_name:
        for key, value, line_no in by_name["Main"]["items"]:
            if key == "Updated":
                updated = value
                if not DATE_RE.match(value):
                    errors.append(f"{path}:{line_no}: Updated is not YYYY-MM-DD ({value!r})")
        if updated is None:
            errors.append(f"{path}: [Main] has no Updated")

    codes = {}
    if "PatchCodes" in by_name:
        for key, value, line_no in by_name["PatchCodes"]["items"]:
            codes[key] = (value, line_no)
            if not value or len(value) % 2 != 0 or not HEX_RE.match(value):
                errors.append(f"{path}:{line_no}: PatchCodes.{key} is not even-length hex")

    version_count = 0
    for section in sections:
        if not VERSION_RE.match(section["name"]):
            continue
        version_count += 1
        for key, value, line_no in section["items"]:
            if CODE_RE.search(key):
                if value not in codes:
                    errors.append(
                        f"{path}:{line_no}: [{section['name']}] {key}={value} is not in [PatchCodes]"
                    )
            elif OFFSET_RE.search(key):
                if not HEX_RE.match(value):
                    errors.append(f"{path}:{line_no}: [{section['name']}] {key} is not hex")
            elif PATCH_RE.search(key) or key.startswith("SLInitHook."):
                if value not in ("0", "1"):
                    errors.append(f"{path}:{line_no}: [{section['name']}] {key} is not 0 or 1")

    if version_count == 0:
        errors.append(f"{path}: no version sections")

    return errors, {
        "updated": updated,
        "sections": len(sections),
        "versions": version_count,
        "codes": len(codes),
    }


def main(argv):
    if len(argv) < 2:
        print("usage: check-ini.py <file.ini> [more.ini ...]", file=sys.stderr)
        return 2
    failed = False
    for arg in argv[1:]:
        path = Path(arg)
        errors, summary = check(path)
        print(
            f"{path}: updated={summary['updated']} sections={summary['sections']} "
            f"versions={summary['versions']} patch_codes={summary['codes']}"
        )
        for error in errors:
            print(error, file=sys.stderr)
            failed = True
    if failed:
        return 1
    print("check-ini ok")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
