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
        res = migrate_old_widgets.migrate(non_file, consent=True)
        assert res == {"swapped": False, "migration_needed": False}


def test_migrate_directory():
    with tempfile.TemporaryDirectory() as tmp_dir:
        res = migrate_old_widgets.migrate(Path(tmp_dir), consent=True)
        assert res == {"swapped": False, "migration_needed": False}


def test_migrate_oversized_file():
    with tempfile.TemporaryDirectory() as tmp_dir:
        large_file = Path(tmp_dir) / "shell.json"
        # Write 1 MiB + 10 bytes
        large_file.write_bytes(b"x" * (migrate_old_widgets.MAX_CONFIG_BYTES + 10))
        res = migrate_old_widgets.migrate(large_file, consent=True)
        assert res == {"swapped": False, "migration_needed": False}


def test_migrate_invalid_json():
    with tempfile.TemporaryDirectory() as tmp_dir:
        bad_file = Path(tmp_dir) / "shell.json"
        bad_file.write_text("{ not valid json", encoding="utf-8")
        res = migrate_old_widgets.migrate(bad_file, consent=True)
        assert res == {"swapped": False, "migration_needed": False}


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
        res = migrate_old_widgets.migrate(cfg_file, consent=True)
        assert res == {"swapped": False, "migration_needed": False}
        # Ensure no backup file was created
        backups = list(Path(tmp_dir).glob("shell.json.bak.*"))
        assert len(backups) == 0


def test_migrate_check_only():
    with tempfile.TemporaryDirectory() as tmp_dir:
        cfg_file = Path(tmp_dir) / "shell.json"
        content = {
            "bar": {
                "layout": {
                    "left": [{"id": "qdot.omashard"}],
                    "center": [],
                    "right": [],
                }
            }
        }
        cfg_file.write_text(json.dumps(content), encoding="utf-8")
        res = migrate_old_widgets.migrate(cfg_file, check_only=True)
        assert res == {"swapped": False, "migration_needed": True}
        # File must not be modified and no backup created
        backups = list(Path(tmp_dir).glob("shell.json.bak.*"))
        assert len(backups) == 0
        assert json.loads(cfg_file.read_text(encoding="utf-8")) == content


def test_migrate_requires_consent():
    with tempfile.TemporaryDirectory() as tmp_dir:
        cfg_file = Path(tmp_dir) / "shell.json"
        content = {
            "bar": {
                "layout": {
                    "left": [{"id": "qdot.omashard"}],
                    "center": [],
                    "right": [],
                }
            }
        }
        cfg_file.write_text(json.dumps(content), encoding="utf-8")
        # Calling migrate without consent must refuse to swap
        res = migrate_old_widgets.migrate(cfg_file, consent=False)
        assert res == {"swapped": False, "migration_needed": True, "consent_required": True}
        backups = list(Path(tmp_dir).glob("shell.json.bak.*"))
        assert len(backups) == 0
        assert json.loads(cfg_file.read_text(encoding="utf-8")) == content


def test_migrate_rejects_symlink():
    with tempfile.TemporaryDirectory() as tmp_dir:
        real_file = Path(tmp_dir) / "real_shell.json"
        symlink_file = Path(tmp_dir) / "shell_symlink.json"
        content = {
            "bar": {
                "layout": {
                    "left": [{"id": "qdot.omashard"}],
                    "center": [],
                    "right": [],
                }
            }
        }
        real_file.write_text(json.dumps(content), encoding="utf-8")
        symlink_file.symlink_to(real_file)

        # Must reject operating through symlink
        res = migrate_old_widgets.migrate(symlink_file, consent=True)
        assert res == {"swapped": False, "migration_needed": False}
        assert symlink_file.is_symlink()
        # Ensure real file was not modified and no backups created
        assert json.loads(real_file.read_text(encoding="utf-8")) == content
        backups = list(Path(tmp_dir).glob("*.bak.*"))
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
        os.chmod(cfg_file, 0o600)

        # Run migration with explicit consent
        res = migrate_old_widgets.migrate(cfg_file, consent=True)
        assert res == {"swapped": True, "migration_needed": False}

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

        # Check file mode preserved (0o600)
        file_mode = stat.S_IMODE(cfg_file.stat().st_mode)
        assert file_mode == 0o600

        # Idempotent: running a second time returns False
        res2 = migrate_old_widgets.migrate(cfg_file, consent=True)
        assert res2 == {"swapped": False, "migration_needed": False}


def test_cli_execution_check_flag():
    with tempfile.TemporaryDirectory() as tmp_dir:
        cfg_file = Path(tmp_dir) / "shell.json"
        original_content = {
            "layout": {
                "left": [{"id": "qdot.omashard"}],
            }
        }
        cfg_file.write_text(json.dumps(original_content), encoding="utf-8")

        result = subprocess.run(
            [sys.executable, str(SCRIPT), "--check", str(cfg_file)],
            capture_output=True,
            text=True,
            check=True,
            cwd=ROOT,
            stdin=subprocess.DEVNULL,
        )
        parsed = json.loads(result.stdout.strip())
        assert parsed == {"swapped": False, "migration_needed": True}
        # File unchanged
        assert json.loads(cfg_file.read_text(encoding="utf-8")) == original_content


def test_cli_execution_no_consent_non_interactive():
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
            stdin=subprocess.DEVNULL,
        )
        parsed = json.loads(result.stdout.strip())
        assert parsed == {"swapped": False, "migration_needed": True, "consent_required": True}
        assert json.loads(cfg_file.read_text(encoding="utf-8")) == original_content


def test_cli_execution_yes_flag():
    with tempfile.TemporaryDirectory() as tmp_dir:
        cfg_file = Path(tmp_dir) / "shell.json"
        original_content = {
            "layout": {
                "left": [{"id": "qdot.omashard"}],
            }
        }
        cfg_file.write_text(json.dumps(original_content), encoding="utf-8")

        result = subprocess.run(
            [sys.executable, str(SCRIPT), "--yes", str(cfg_file)],
            capture_output=True,
            text=True,
            check=True,
            cwd=ROOT,
            stdin=subprocess.DEVNULL,
        )
        parsed = json.loads(result.stdout.strip())
        assert parsed == {"swapped": True, "migration_needed": False}
        updated = json.loads(cfg_file.read_text(encoding="utf-8"))
        assert updated["layout"]["left"][0]["id"] == "qdot.omasky"


def test_interactive_prompt_accepted():
    from unittest.mock import patch
    import io

    with tempfile.TemporaryDirectory() as tmp_dir:
        cfg_file = Path(tmp_dir) / "shell.json"
        original_content = {
            "layout": {
                "left": [{"id": "qdot.omashard"}],
            }
        }
        cfg_file.write_text(json.dumps(original_content), encoding="utf-8")

        with patch("sys.stdin.isatty", return_value=True), \
             patch("builtins.input", return_value="y"), \
             patch("sys.stdout", new=io.StringIO()) as fake_out:
            ret = migrate_old_widgets.main([str(SCRIPT), str(cfg_file)])
            assert ret == 0
            parsed = json.loads(fake_out.getvalue().strip())
            assert parsed == {"swapped": True, "migration_needed": False}
        updated = json.loads(cfg_file.read_text(encoding="utf-8"))
        assert updated["layout"]["left"][0]["id"] == "qdot.omasky"


def test_interactive_prompt_declined():
    from unittest.mock import patch
    import io

    with tempfile.TemporaryDirectory() as tmp_dir:
        cfg_file = Path(tmp_dir) / "shell.json"
        original_content = {
            "layout": {
                "left": [{"id": "qdot.omashard"}],
            }
        }
        cfg_file.write_text(json.dumps(original_content), encoding="utf-8")

        with patch("sys.stdin.isatty", return_value=True), \
             patch("builtins.input", return_value="n"), \
             patch("sys.stdout", new=io.StringIO()) as fake_out:
            ret = migrate_old_widgets.main([str(SCRIPT), str(cfg_file)])
            assert ret == 0
            parsed = json.loads(fake_out.getvalue().strip())
            assert parsed == {"swapped": False, "migration_needed": True, "consent_required": True}
        assert json.loads(cfg_file.read_text(encoding="utf-8")) == original_content


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
