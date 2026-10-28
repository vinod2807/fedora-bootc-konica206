#!/usr/bin/env python3
"""Minimal local YAML/JSON syntax check for repository files."""
import glob
import json
import sys

import yaml


def main() -> int:
    ok = True
    paths = sorted(glob.glob(".github/workflows/*.yml") + glob.glob(".github/workflows/*.yaml"))
    for path in paths:
        try:
            with open(path, encoding="utf-8") as fh:
                yaml.safe_load(fh)
            print(f"OK   {path}")
        except Exception as exc:  # noqa: BLE001 - report every parse error
            ok = False
            print(f"FAIL {path}: {exc}", file=sys.stderr)

    try:
        with open("desktop/waybar/config", encoding="utf-8") as fh:
            json.load(fh)
        print("OK   desktop/waybar/config")
    except Exception as exc:  # noqa: BLE001
        ok = False
        print(f"FAIL desktop/waybar/config: {exc}", file=sys.stderr)

    return 0 if ok else 1


if __name__ == "__main__":
    sys.exit(main())
