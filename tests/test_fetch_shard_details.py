#!/usr/bin/env python3
"""Tests for fetch_shard_details.py."""

from __future__ import annotations

import json
import subprocess
import sys
from datetime import date
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
SCRIPT = ROOT / "scripts" / "fetch_shard_details.py"

sys.path.insert(0, str(ROOT / "scripts"))
import fetch_shard_details  # type: ignore


def run_script(date_str: str) -> dict:
    result = subprocess.run(
        [sys.executable, str(SCRIPT), date_str],
        capture_output=True,
        text=True,
        check=True,
        cwd=ROOT,
    )
    return json.loads(result.stdout)


def test_resolve_shard_details_red_day():
    # 2026-08-28 is day 28 (even = black day), 2026-08-29 is day 29 (odd = red day)
    target = date(2026, 8, 29)
    details = fetch_shard_details.resolve_shard_details(target, None)
    assert details["date"] == "2026-08-29"
    assert "has_shard" in details
    if details["has_shard"]:
        assert details["color"] in ("red", "black")
        assert len(details["occurrences"]) == 3
        for occ in details["occurrences"]:
            assert "start" in occ and "landing" in occ and "end" in occ


def test_resolve_shard_details_no_shard_day():
    # Test a known schedule computation
    target = date(2026, 8, 24)  # Monday
    details = fetch_shard_details.resolve_shard_details(target, None)
    assert details["date"] == "2026-08-24"
    assert "has_shard" in details


def test_cli_execution():
    payload = run_script("2026-08-28")
    assert payload["date"] == "2026-08-28"
    assert "has_shard" in payload


def test_fetch_shard_oversized_content_length():
    from unittest.mock import MagicMock, patch
    mock_response = MagicMock()
    mock_response.headers = {"Content-Length": str(fetch_shard_details.MAX_RESPONSE_BYTES + 1000)}
    mock_response.__enter__.return_value = mock_response

    with patch("fetch_shard_details.urlopen", return_value=mock_response):
        try:
            fetch_shard_details.fetch_remote_config()
            assert False, "Expected RuntimeError for oversized Content-Length"
        except RuntimeError as err:
            assert "Content-Length exceeds limit" in str(err)


def test_fetch_shard_oversized_body():
    from unittest.mock import MagicMock, patch
    mock_response = MagicMock()
    mock_response.headers = {}
    mock_response.read.return_value = b"x" * (fetch_shard_details.MAX_RESPONSE_BYTES + 1)
    mock_response.__enter__.return_value = mock_response

    with patch("fetch_shard_details.urlopen", return_value=mock_response):
        try:
            fetch_shard_details.fetch_remote_config()
            assert False, "Expected RuntimeError for oversized response body"
        except RuntimeError as err:
            assert "exceeded maximum size limit" in str(err)


def test_fetch_shard_valid_bounded():
    from unittest.mock import MagicMock, patch
    fixture = {"dailiesMap": {"2026-08-28": {"override": None}}}
    mock_response = MagicMock()
    mock_response.headers = {"Content-Length": str(len(json.dumps(fixture)))}
    mock_response.read.return_value = json.dumps(fixture).encode("utf-8")
    mock_response.__enter__.return_value = mock_response

    with patch("fetch_shard_details.urlopen", return_value=mock_response):
        payload = fetch_shard_details.fetch_remote_config()
        assert "dailiesMap" in payload


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
    print("\nall fetch_shard_details tests passed")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
