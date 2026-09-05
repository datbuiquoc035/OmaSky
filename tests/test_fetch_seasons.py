#!/usr/bin/env python3
"""Offline unit tests for fetch_seasons.py."""

from __future__ import annotations

import json
import subprocess
import sys
import tempfile
from datetime import date
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
SCRIPT = ROOT / "scripts" / "fetch_seasons.py"

sys.path.insert(0, str(ROOT / "scripts"))
import fetch_seasons  # type: ignore

FIXTURE_PAYLOAD = {
    "items": [
        {
            "guid": "season-1-guid",
            "name": "Season of Gratitude",
            "shortName": "Gratitude",
            "year": 2019,
            "date": "2019-07-19",
            "endDate": "2019-09-02",
            "draft": False,
        },
        {
            "guid": "season-2-guid",
            "name": "Season of Lightseekers",
            "shortName": "Lightseekers",
            "year": 2019,
            "date": "2019-09-23",
            "endDate": "2019-11-10",
            "draft": False,
        },
        {
            "guid": "season-3-guid",
            "name": "Season of Belonging",
            "shortName": "Belonging",
            "year": 2019,
            "date": "2019-11-18",
            "endDate": "2020-01-12",
            "draft": True,
        },
    ]
}


def test_current_active():
    # Mid-season 2: 2019-10-01
    today = date(2019, 10, 1)
    result = fetch_seasons.resolve_seasons(FIXTURE_PAYLOAD, today)
    assert result["today"] == "2019-10-01"
    assert result["current"] is not None
    assert result["current"]["name"] == "Season of Lightseekers"
    assert result["current"]["number"] == 2
    assert result["current"]["start"] == "2019-09-23"
    assert result["current"]["end"] == "2019-11-10"
    assert result["current"]["days_total"] == 49
    assert result["current"]["days_elapsed"] == 9
    assert result["current"]["days_remaining"] == 40
    assert result["current"]["progress"] == round(9 / 49, 4)
    assert result["next"] is not None
    assert result["next"]["name"] == "Season of Belonging"
    assert result["next"]["number"] == 3
    assert result["next"]["days_until_start"] == (date(2019, 11, 18) - today).days


def test_start_date_inclusive():
    # First day of season 1
    today = date(2019, 7, 19)
    result = fetch_seasons.resolve_seasons(FIXTURE_PAYLOAD, today)
    assert result["current"] is not None
    assert result["current"]["name"] == "Season of Gratitude"
    assert result["current"]["number"] == 1
    assert result["current"]["days_elapsed"] == 1
    assert result["current"]["days_remaining"] == 45
    assert result["current"]["days_total"] == 46
    assert result["current"]["progress"] == round(1 / 46, 4)


def test_end_date_inclusive():
    # Last day of season 1 (2019-09-02)
    today = date(2019, 9, 2)
    result = fetch_seasons.resolve_seasons(FIXTURE_PAYLOAD, today)
    assert result["current"] is not None
    assert result["current"]["name"] == "Season of Gratitude"
    assert result["current"]["days_elapsed"] == 46
    assert result["current"]["days_remaining"] == 0
    assert result["current"]["days_total"] == 46
    assert result["current"]["progress"] == 1.0


def test_gap_off_season():
    # Off-season gap between Season 1 and Season 2: 2019-09-10
    today = date(2019, 9, 10)
    result = fetch_seasons.resolve_seasons(FIXTURE_PAYLOAD, today)
    assert result["current"] is None
    assert result["next"] is not None
    assert result["next"]["name"] == "Season of Lightseekers"
    assert result["next"]["number"] == 2
    assert result["next"]["days_until_start"] == 13


def test_before_all_seasons():
    # Date before all recorded seasons
    today = date(2019, 1, 1)
    result = fetch_seasons.resolve_seasons(FIXTURE_PAYLOAD, today)
    assert result["current"] is None
    assert result["next"] is not None
    assert result["next"]["name"] == "Season of Gratitude"
    assert result["next"]["number"] == 1


def test_after_all_seasons():
    # Date after all recorded seasons
    today = date(2025, 1, 1)
    result = fetch_seasons.resolve_seasons(FIXTURE_PAYLOAD, today)
    assert result["current"] is None
    assert result["next"] is None


def test_draft_current_is_selected():
    # Season 3 is marked draft: true
    today = date(2019, 12, 1)
    result = fetch_seasons.resolve_seasons(FIXTURE_PAYLOAD, today)
    assert result["current"] is not None
    assert result["current"]["name"] == "Season of Belonging"
    assert result["current"]["draft"] is True
    assert result["next"] is None


def test_unsorted_items():
    # Items presented out of order
    reversed_payload = {
        "items": list(reversed(FIXTURE_PAYLOAD["items"]))
    }
    today = date(2019, 10, 1)
    result = fetch_seasons.resolve_seasons(reversed_payload, today)
    assert result["current"] is not None
    assert result["current"]["name"] == "Season of Lightseekers"
    assert result["current"]["number"] == 2


def test_payload_shape():
    today = date(2019, 10, 1)
    result = fetch_seasons.resolve_seasons(FIXTURE_PAYLOAD, today)
    expected_top_keys = {"generated_at", "today", "current", "next"}
    assert set(result.keys()) == expected_top_keys

    expected_current_keys = {
        "guid",
        "name",
        "shortName",
        "number",
        "year",
        "draft",
        "start",
        "end",
        "days_total",
        "days_elapsed",
        "days_remaining",
        "progress",
    }
    assert set(result["current"].keys()) == expected_current_keys

    expected_next_keys = {
        "guid",
        "name",
        "shortName",
        "number",
        "year",
        "draft",
        "start",
        "days_until_start",
    }
    assert set(result["next"].keys()) == expected_next_keys


def test_cli_execution_offline():
    with tempfile.NamedTemporaryFile("w", suffix=".json", delete=False) as handle:
        json.dump(FIXTURE_PAYLOAD, handle)
        fixture_path = handle.name

    try:
        cmd = [
            sys.executable,
            str(SCRIPT),
            "--date",
            "2019-10-01",
            "--seasons-file",
            fixture_path,
        ]
        result = subprocess.run(cmd, capture_output=True, text=True, check=True)
        payload = json.loads(result.stdout)
        assert payload["today"] == "2019-10-01"
        assert payload["current"]["name"] == "Season of Lightseekers"
        assert payload["next"]["name"] == "Season of Belonging"
    finally:
        Path(fixture_path).unlink(missing_ok=True)


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
    print("\nall fetch_seasons tests passed")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
