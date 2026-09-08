#!/usr/bin/env python3
"""Tests for migrate_old_widgets.py."""

from __future__ import annotations

import json
import os
import stat
import subprocess
import sys
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
SCRIPT = ROOT / "scripts" / "migrate_old_widgets.py"

sys.path.insert(0, str(ROOT / "scripts"))
import migrate_old_widgets  # type: ignore


def test_default_shell_json():
    orig_xdg = os.environ.get("XDG_CONFIG_HOME")
    try:
        if "XDG_CONFIG_HOME" in os.environ:
            del os.environ["XDG_CONFIG_HOME"]
        expected = Path.home() / ".config" / "omarchy" / "shell.json"
        assert migrate_old_widgets.default_shell_json() == expected

        os.environ["XDG_CONFIG_HOME"] = "/tmp/custom_config"
        assert migrate_old_widgets.default_shell_json() == Path("/tmp/custom_config/omarchy/shell.json")
    finally:
        if orig_xdg is not None:
            os.environ["XDG_CONFIG_HOME"] = orig_xdg
        elif "XDG_CONFIG_HOME" in os.environ:
            del os.environ["XDG_CONFIG_HOME"]


def test_migrate_nonexistent_file():
    with tempfile.TemporaryDirectory() as tmp_dir:
        non_file = Path(tmp_dir) / "does_not_exist.json"
        assert migrate_old_widgets.migrate(non_file) is False


def test_migrate_directory():
    with tempfile.TemporaryDirectory() as tmp_dir:
        assert migrate_old_widgets.migrate(Path(tmp_dir)) is False


def test_migrate_oversized_file():
    with tempfile.TemporaryDirectory() as tmp_dir:
        large_file = Path(tmp_dir) / "shell.json"
        # Write 1 MiB + 10 bytes
        large_file.write_bytes(b"x" * (migrate_old_widgets.MAX_CONFIG_BYTES + 10))
        assert migrate_old_widgets.migrate(large_file) is False


def test_migrate_invalid_json():
    with tempfile.TemporaryDirectory() as tmp_dir:
        bad_file = Path(tmp_dir) / "shell.json"
        bad_file.write_text("{ not valid json", encoding="utf-8")
        assert migrate_old_widgets.migrate(bad_file) is False


def test_migrate_no_old_entries():
    with tempfile.TemporaryDirectory() as tmp_dir:
        cfg_file = Path(tmp_dir) / "shell.json"
        content = {
            "bar": {
                "layout": {
                    "left": [{"id": "omarchy.clock"}],
                    "center": [],
                    "right": [{"id": "qdot.omasky"}],
                }
            }
        }
        cfg_file.write_text(json.dumps(content), encoding="utf-8")
        assert migrate_old_widgets.migrate(cfg_file) is False
        # Ensure no backup file was created
        backups = list(Path(tmp_dir).glob("shell.json.bak.*"))
        assert len(backups) == 0


def test_migrate_successful_atomic_swap():
    with tempfile.TemporaryDirectory() as tmp_dir:
        cfg_file = Path(tmp_dir) / "shell.json"
        original_content = {
            "bar": {
                "layout": {
                    "left": [
                        {"id": "omarchy.workspaces"},
                        {"id": "qdot.omashard", "format": "map", "timeZone": "UTC+9"},
                    ],
                    "center": [],
                    "right": [
                        {"id": "qdot.omaevents", "format": "events", "refreshSeconds": 30},
                        {"id": "omarchy.tray"},
                    ],
                }
            }
        }
        cfg_file.write_text(json.dumps(original_content, indent=2), encoding="utf-8")
        os.chmod(cfg_file, 0o644)

        # Run migration
        assert migrate_old_widgets.migrate(cfg_file) is True

        # Check backup exists and has original content
        backups = list(Path(tmp_dir).glob("shell.json.bak.*"))
        assert len(backups) == 1
        backup_data = json.loads(backups[0].read_text(encoding="utf-8"))
        assert backup_data == original_content

        # Check new shell.json content
        updated_data = json.loads(cfg_file.read_text(encoding="utf-8"))
        left = updated_data["bar"]["layout"]["left"]
        right = updated_data["bar"]["layout"]["right"]

        # First old entry (qdot.omashard in left) replaced with qdot.omasky
        assert left[0]["id"] == "omarchy.workspaces"
        assert left[1]["id"] == "qdot.omasky"
        # Non-format settings preserved and merged
        assert left[1]["timeZone"] == "UTC+9"
        assert left[1]["refreshSeconds"] == 30
        assert "format" not in left[1]

        # Second old entry (qdot.omaevents in right) removed
        assert len(right) == 1
        assert right[0]["id"] == "omarchy.tray"

        # Check file mode preserved
        file_mode = stat.S_IMODE(cfg_file.stat().st_mode)
        assert file_mode == 0o644

        # Idempotent: running a second time returns False
        assert migrate_old_widgets.migrate(cfg_file) is False


def test_cli_execution():
    with tempfile.TemporaryDirectory() as tmp_dir:
        cfg_file = Path(tmp_dir) / "shell.json"
        original_content = {
            "layout": {
                "left": [{"id": "qdot.omashard"}],
            }
        }
        cfg_file.write_text(json.dumps(original_content), encoding="utf-8")

        result = subprocess.run(
            [sys.executable, str(SCRIPT), str(cfg_file)],
            capture_output=True,
            text=True,
            check=True,
            cwd=ROOT,
        )
        parsed = json.loads(result.stdout.strip())
        assert parsed == {"swapped": True}


def main() -> int:
    failures = 0
    for name, fn in sorted(globals().items()):
        if name.startswith("test_") and callable(fn):
            try:
                fn()
                print(f"PASS {name}")
            except Exception as exc:
                failures += 1
                print(f"FAIL {name}: {exc}")
    if failures:
        print(f"\n{failures} test(s) failed")
        return 1
    print("\nall migrate_old_widgets tests passed")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
