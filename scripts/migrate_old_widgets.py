#!/usr/bin/env python3
"""Replace legacy OmaShards/OmaEvents bar entries with the unified OmaSky entry.

The standalone ``qdot.omashard`` and ``qdot.omaevents`` widgets were merged
into ``qdot.omasky``.

Following security guidelines, this script:
1. Requires explicit user consent (--yes/--consent or interactive confirmation)
   before modifying configuration.
2. Supports a non-mutating check mode (--check) for GUI notice display.
3. Employs atomic, no-follow-safe file replacement (O_NOFOLLOW on read/backup/temp,
   permission preservation, fsync, and atomic swap) to prevent symlink attacks and
   file corruption.

Usage:
    python3 migrate_old_widgets.py [--check] [--yes|--consent] [shell.json]
"""

from __future__ import annotations

import argparse
import json
import os
import stat
import sys
from datetime import datetime
from pathlib import Path

OLD_IDS = {"qdot.omashard", "qdot.omaevents"}
NEW_ID = "qdot.omasky"
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


def read_config_no_follow(path: Path) -> tuple[dict, bytes, os.stat_result] | None:
    """Read configuration from path without following symlinks.

    Returns (parsed_dict, raw_bytes, stat_result) or None if unreadable / symlink / oversized.
    """
    try:
        # Pre-check: reject explicit symlinks
        if path.is_symlink():
            return None
        flags = os.O_RDONLY | getattr(os, "O_NOFOLLOW", 0) | getattr(os, "O_CLOEXEC", 0)
        fd = os.open(path, flags)
    except (OSError, ValueError):
        return None

    try:
        stat_res = os.fstat(fd)
        if not stat.S_ISREG(stat_res.st_mode):
            return None
        if stat_res.st_size > MAX_CONFIG_BYTES:
            return None
        raw_bytes = os.read(fd, MAX_CONFIG_BYTES + 1)
        if len(raw_bytes) > MAX_CONFIG_BYTES:
            return None
    except OSError:
        return None
    finally:
        os.close(fd)

    try:
        text = raw_bytes.decode("utf-8")
        config = json.loads(text)
    except (UnicodeDecodeError, json.JSONDecodeError):
        return None

    return config, raw_bytes, stat_res


def check_migration_needed(config: dict) -> tuple[bool, str | None, int | None, dict]:
    """Check if config contains legacy bar entries needing migration.

    Returns (needed, first_section, first_index, merged_settings).
    """
    layout = find_layout(config)
    if layout is None:
        return False, None, None, {}

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
        return False, None, None, {}

    # Idempotent: the slot already holds the unified widget.
    current = layout[first_section][first_index]
    if isinstance(current, dict) and current.get("id") == NEW_ID:
        return False, None, None, {}

    return True, first_section, first_index, merged


def write_backup_no_follow(path: Path, raw_bytes: bytes, mode: int) -> bool:
    """Create a backup file without following symlinks, preserving permissions."""
    backup_path = path.with_name(f"{path.name}.bak.{datetime.now():%Y%m%d%H%M%S}")
    flags = (
        os.O_WRONLY
        | os.O_CREAT
        | os.O_EXCL
        | getattr(os, "O_NOFOLLOW", 0)
        | getattr(os, "O_CLOEXEC", 0)
    )
    try:
        fd = os.open(backup_path, flags, mode=mode)
    except OSError:
        return False

    try:
        written = 0
        while written < len(raw_bytes):
            n = os.write(fd, raw_bytes[written:])
            if n <= 0:
                return False
            written += n
        os.fsync(fd)
        return True
    except OSError:
        try:
            backup_path.unlink(missing_ok=True)
        except OSError:
            pass
        return False
    finally:
        os.close(fd)


def atomic_replace_no_follow(path: Path, new_content: str, mode: int) -> bool:
    """Atomically replace path with new_content without following symlinks."""
    temp_path = path.with_name(
        f".{path.name}.tmp.{datetime.now():%Y%m%d%H%M%S}.{os.getpid()}"
    )
    flags = (
        os.O_WRONLY
        | os.O_CREAT
        | os.O_EXCL
        | getattr(os, "O_NOFOLLOW", 0)
        | getattr(os, "O_CLOEXEC", 0)
    )
    try:
        fd = os.open(temp_path, flags, mode=mode)
    except OSError:
        return False

    raw_bytes = new_content.encode("utf-8")
    try:
        written = 0
        while written < len(raw_bytes):
            n = os.write(fd, raw_bytes[written:])
            if n <= 0:
                return False
            written += n
        os.fsync(fd)
    except OSError:
        try:
            temp_path.unlink(missing_ok=True)
        except OSError:
            pass
        return False
    finally:
        os.close(fd)

    # Pre-replacement safety verification:
    # Ensure destination has not become a symlink (preventing TOCTOU attacks)
    try:
        target_stat = os.lstat(path)
        if stat.S_ISLNK(target_stat.st_mode) or not stat.S_ISREG(target_stat.st_mode):
            temp_path.unlink(missing_ok=True)
            return False
        temp_stat = os.lstat(temp_path)
        if stat.S_ISLNK(temp_stat.st_mode) or not stat.S_ISREG(temp_stat.st_mode):
            temp_path.unlink(missing_ok=True)
            return False
        os.replace(temp_path, path)
        return True
    except OSError:
        try:
            temp_path.unlink(missing_ok=True)
        except OSError:
            pass
        return False


def migrate(path: Path, consent: bool = False, check_only: bool = False) -> dict:
    """Migrate legacy widgets in path if needed and authorized.

    Returns dict with keys:
        - "migration_needed": bool
        - "swapped": bool
        - "consent_required": bool (when needed but consent not given)
        - "error": str (on failure)
    """
    data = read_config_no_follow(path)
    if data is None:
        return {"swapped": False, "migration_needed": False}

    config, raw_bytes, stat_res = data
    needed, first_section, first_index, merged = check_migration_needed(config)
    if not needed:
        return {"swapped": False, "migration_needed": False}

    if check_only:
        return {"swapped": False, "migration_needed": True}

    if not consent:
        return {"swapped": False, "migration_needed": True, "consent_required": True}

    # Perform migration with explicit consent
    layout = find_layout(config)
    layout[first_section][first_index] = {"id": NEW_ID, **merged}
    for section in ("left", "center", "right"):
        entries = layout.get(section)
        if isinstance(entries, list):
            layout[section] = [
                entry
                for entry in entries
                if not (isinstance(entry, dict) and entry.get("id") in OLD_IDS)
            ]

    file_mode = stat.S_IMODE(stat_res.st_mode)
    if not write_backup_no_follow(path, raw_bytes, file_mode):
        return {"swapped": False, "migration_needed": True, "error": "backup_failed"}

    new_text = json.dumps(config, indent=2) + "\n"
    if not atomic_replace_no_follow(path, new_text, file_mode):
        return {"swapped": False, "migration_needed": True, "error": "write_failed"}

    return {"swapped": True, "migration_needed": False}


def main(argv: list[str]) -> int:
    parser = argparse.ArgumentParser(
        description="Migrate legacy OmaShard/OmaEvents bar entries to OmaSky with explicit user consent."
    )
    parser.add_argument(
        "path",
        nargs="?",
        default=None,
        help="Path to shell.json (defaults to ~/.config/omarchy/shell.json)",
    )
    parser.add_argument(
        "--check",
        action="store_true",
        help="Check whether migration is needed without modifying the file",
    )
    parser.add_argument(
        "-y",
        "--yes",
        "--consent",
        dest="consent",
        action="store_true",
        help="Explicitly grant user consent to migrate shell.json",
    )

    args = parser.parse_args(argv[1:])
    target_path = Path(args.path) if args.path else default_shell_json()

    consent = args.consent
    if not args.check and not consent and sys.stdin.isatty():
        preview = migrate(target_path, check_only=True)
        if preview.get("migration_needed"):
            try:
                response = input(
                    f"Legacy widgets found in {target_path}. Migrate them to {NEW_ID}? [y/N]: "
                )
                if response.strip().lower() in ("y", "yes"):
                    consent = True
            except (EOFError, KeyboardInterrupt):
                consent = False

    result = migrate(target_path, consent=consent, check_only=args.check)
    print(json.dumps(result))
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv))
