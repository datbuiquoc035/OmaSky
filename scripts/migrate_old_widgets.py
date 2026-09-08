#!/usr/bin/env python3
"""Replace legacy OmaShards/OmaEvents bar entries with the unified OmaSky entry.

The standalone ``qdot.omashard`` and ``qdot.omaevents`` widgets were merged
into ``qdot.omasky``. When OmaSky is installed via the standard flow
(``omarchy plugin add <url> --enable``) no installer runs — Omarchy
deliberately never executes plugin code at install time — so the bar layout
migration happens here, at widget runtime from BarWidget.qml
(``Component.onCompleted`` -> this script -> ``rescanPlugins``).

Usage:
    python3 migrate_old_widgets.py [shell.json]

Output is one compact JSON line:
    {"swapped": true}   # old entries found, backup written, layout rewritten
    {"swapped": false}  # nothing to do (no file, no layout, no old entries)

Behaviour mirrors the retired ``scripts/install.sh`` swap step: the first
legacy entry's position is kept for ``qdot.omasky``, any inline settings are
carried over except ``format`` (each plugin has its own vocabulary), remaining
legacy entries are dropped, and ``shell.json`` is backed up first as
``shell.json.bak.YYYYMMDDHHMMSS``.
"""

from __future__ import annotations

import json
import os
import shutil
import sys
from datetime import datetime
from pathlib import Path

OLD_IDS = {"qdot.omashard", "qdot.omaevents"}
NEW_ID = "qdot.omasky"
# Keys inherited from the old widgets that do not map onto the unified
# plugin's settings (each old plugin had its own "format" vocabulary).
SKIP_KEYS = {"format"}
MAX_CONFIG_BYTES = 1024 * 1024  # 1 MiB


def default_shell_json() -> Path:
    xdg_config = os.environ.get("XDG_CONFIG_HOME")
    config_dir = Path(xdg_config) if xdg_config else Path.home() / ".config"
    return config_dir / "omarchy" / "shell.json"


def find_layout(config: object) -> dict | None:
    if not isinstance(config, dict):
        return None
    layout = config.get("bar", {}).get("layout") if isinstance(config.get("bar"), dict) else None
    if not isinstance(layout, dict):
        layout = config.get("layout")
    return layout if isinstance(layout, dict) else None


def migrate(path: Path) -> bool:
    try:
        resolved_path = path.resolve()
        if not resolved_path.is_file():
            return False
        stat = resolved_path.stat()
        if stat.st_size > MAX_CONFIG_BYTES:
            return False
        raw_text = resolved_path.read_text(encoding="utf-8")
        if len(raw_text.encode("utf-8")) > MAX_CONFIG_BYTES:
            return False
        config = json.loads(raw_text)
    except FileNotFoundError:
        return False
    except (OSError, json.JSONDecodeError, UnicodeDecodeError):
        return False

    layout = find_layout(config)
    if layout is None:
        return False

    first_section: str | None = None
    first_index: int | None = None
    merged: dict = {}
    for section in ("left", "center", "right"):
        entries = layout.get(section)
        if not isinstance(entries, list):
            continue
        for index, entry in enumerate(entries):
            if isinstance(entry, dict) and entry.get("id") in OLD_IDS:
                if first_index is None:
                    first_index = index
                    first_section = section
                    merged = {
                        key: value
                        for key, value in entry.items()
                        if key != "id" and key not in SKIP_KEYS
                    }
                else:
                    for key, value in entry.items():
                        if key != "id" and key not in SKIP_KEYS and key not in merged:
                            merged[key] = value

    if first_index is None or first_section is None:
        return False

    # Idempotent: the slot already holds the unified widget.
    current = layout[first_section][first_index]
    if isinstance(current, dict) and current.get("id") == NEW_ID:
        return False

    backup = resolved_path.with_name(f"{resolved_path.name}.bak.{datetime.now():%Y%m%d%H%M%S}")
    try:
        shutil.copy2(resolved_path, backup)
    except OSError:
        return False

    layout[first_section][first_index] = {"id": NEW_ID, **merged}
    for section in ("left", "center", "right"):
        entries = layout.get(section)
        if isinstance(entries, list):
            layout[section] = [
                entry
                for entry in entries
                if not (isinstance(entry, dict) and entry.get("id") in OLD_IDS)
            ]

    # Atomic write to avoid shell corruption or partial reads by inotify watchers
    temp_path = resolved_path.with_name(
        f".{resolved_path.name}.tmp.{datetime.now():%Y%m%d%H%M%S}.{os.getpid()}"
    )
    try:
        temp_path.write_text(json.dumps(config, indent=2) + "\n", encoding="utf-8")
        try:
            shutil.copymode(resolved_path, temp_path)
        except OSError:
            pass
        os.replace(temp_path, resolved_path)
    except OSError:
        try:
            temp_path.unlink(missing_ok=True)
        except OSError:
            pass
        return False
    return True


def main(argv: list[str]) -> int:
    path = Path(argv[1]).resolve() if len(argv) > 1 else default_shell_json()
    print(json.dumps({"swapped": migrate(path)}))
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv))
