#!/usr/bin/env python3
"""Tests for the OmaEvents schedule JSON (sky_clock.py --json)."""

from __future__ import annotations

import json
import subprocess
import sys
from datetime import datetime
from pathlib import Path
from zoneinfo import ZoneInfo

ROOT = Path(__file__).resolve().parent.parent
SCRIPT = ROOT / "sky_clock.py"

SKY_TZ = ZoneInfo("America/Los_Angeles")


def run_json(count: int = 2) -> dict:
    result = subprocess.run(
        [sys.executable, str(SCRIPT), "--json", str(count)],
        capture_output=True,
        text=True,
        check=True,
        cwd=ROOT,
    )
    return json.loads(result.stdout)


def test_payload_shape():
    payload = run_json(3)
    assert set(["events", "daily_reset", "nearest", "now_sky_label", "now_local_label"]) <= set(payload)
    assert len(payload["events"]) == 3
    for ev in payload["events"]:
        assert "occurrences" in ev and len(ev["occurrences"]) == 3
        occ = ev["occurrences"][0]
        for key in ("start_epoch_ms", "end_epoch_ms", "start_local_label", "start_sky_label"):
            assert key in occ, key
        # Local labels must exist (system timezone) and sky labels must exist (PT).
        assert len(occ["start_sky_label"]) == 5 and ":" in occ["start_sky_label"]
        assert len(occ["start_local_label"]) == 5 and ":" in occ["start_local_label"]
    reset = payload["daily_reset"]
    assert reset["start_epoch_ms"] > 0
    assert reset["day_offset"] >= 1
    assert reset["start_sky_label"] == "00:00"


def test_geyser_slots_are_minute_5():
    payload = run_json(2)
    geyser = next(e for e in payload["events"] if e["key"] == "geyser")
    for occ in geyser["occurrences"]:
        sky = datetime.fromisoformat(occ["start_sky"])
        assert sky.minute == 5
        assert sky.hour % 2 == 0
    turtle = next(e for e in payload["events"] if e["key"] == "turtle")
    for occ in turtle["occurrences"]:
        sky = datetime.fromisoformat(occ["start_sky"])
        assert sky.minute == 50
        assert sky.hour % 2 == 0


def test_occurrence_epochs_match_labels():
    payload = run_json(2)
    for ev in payload["events"]:
        for occ in ev["occurrences"]:
            impl = datetime.fromisoformat(occ["start_sky"]).astimezone(SKY_TZ)
            assert impl.strftime("%H:%M") == occ["start_sky_label"]
            assert int(impl.timestamp() * 1000) == occ["start_epoch_ms"]


def test_daily_reset_is_tomorrow_00_00_pt():
    payload = run_json(2)
    reset = payload["daily_reset"]
    now_sky = datetime.fromisoformat(payload["now_sky"]).astimezone(SKY_TZ)
    reset_dt = datetime.fromtimestamp(reset["start_epoch_ms"] / 1000, SKY_TZ)
    assert reset_dt.hour == 0 and reset_dt.minute == 0
    delta = (reset_dt.date() - now_sky.date()).days
    assert delta in (0, 1)


def test_nearest_field_shape():
    payload = run_json(2)
    nearest = payload["nearest"]
    assert "name" in nearest and "start_epoch_ms" in nearest
    assert isinstance(nearest["is_active"], bool)


def main() -> int:
    failures = 0
    for name, fn in sorted(globals().items()):
        if name.startswith("test_") and callable(fn):
            try:
                fn()
                print(f"PASS {name}")
            except Exception as exc:  # noqa: BLE001
                failures += 1
                print(f"FAIL {name}: {exc}")
    if failures:
        print(f"\n{failures} test(s) failed")
        return 1
    print("\nall tests passed")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())