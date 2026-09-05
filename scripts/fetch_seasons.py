#!/usr/bin/env python3
"""Fetch and resolve Sky: Children of the Light seasons for the OmaSky widget.

Data source: the `skygame-data` npm package (Silverfeelin/SkyGame-Data), whose
published `assets/seasons.json` is fetched from its CDN mirror. That file is a
single object: {"items": [ ... ]} with one entry per season, chronologically:
{ "guid", "name", "shortName", "year", "date", "endDate", "draft", ... }.
Dates are YYYY-MM-DD calendar days in America/Los_Angeles (Sky's daily reset
timezone), so all season math happens on `date` objects — never instants —
which sidesteps DST entirely.

This script resolves the season that is *current* today (the item whose
date <= today <= endDate) and the *next* upcoming season, computing calendar-
day counts (days total/elapsed/remaining, progress 0..1). It is pure math on
top of the fetched data; the QML widget caches the script's output per LA game
day (see BarWidget.qml) so the network is hit at most once a day.

Usage:
    python3 fetch_seasons.py                        # live: today = LA date
    python3 fetch_seasons.py --date 2026-09-05      # compute for a fixed date
    python3 fetch_seasons.py --date 2026-09-05 --seasons-file seasons.json  # offline

Output is one compact JSON line:
    {"generated_at": ..., "today": "2026-09-05",
     "current": {"guid", "name", "shortName", "number", "year", "start",
                 "end", "days_total", "days_elapsed", "days_remaining",
                 "progress", "draft"} | null,
     "next": {"guid", "name", "shortName", "number", "year", "start",
              "days_until_start", "draft"} | null}
"""

from __future__ import annotations

import argparse
import json
import sys
from datetime import date, datetime
from typing import Any
from urllib.error import HTTPError, URLError
from urllib.request import Request, urlopen
from zoneinfo import ZoneInfo

SOURCE_URL = "https://cdn.jsdelivr.net/npm/skygame-data@1.3.10/assets/seasons.json"

SKY_TZ = ZoneInfo("America/Los_Angeles")


def parse_date(value: str) -> date:
    """Validate an ISO calendar date."""
    try:
        return date.fromisoformat(value)
    except (ValueError, TypeError) as error:
        raise argparse.ArgumentTypeError("date must use YYYY-MM-DD format") from error


def fetch_seasons_json() -> dict[str, Any]:
    """Download and validate the skygame-data seasons.json payload."""
    request = Request(SOURCE_URL, headers={"User-Agent": "omasky-seasons/1.0"})
    try:
        with urlopen(request, timeout=15) as response:
            payload = json.load(response)
    except HTTPError as error:
        raise RuntimeError(f"API returned HTTP {error.code}") from error
    except URLError as error:
        raise RuntimeError(f"could not reach API: {error.reason}") from error
    except TimeoutError as error:
        raise RuntimeError("API request timed out") from error
    except json.JSONDecodeError as error:
        raise RuntimeError("API returned invalid JSON") from error

    if not isinstance(payload, dict) or not isinstance(payload.get("items"), list):
        raise RuntimeError("API response does not contain an items array")
    return payload


def load_seasons_file(path: str) -> dict[str, Any]:
    """Read a raw seasons.json ({ "items": [...] }) from disk."""
    try:
        with open(path, "r", encoding="utf-8") as handle:
            payload = json.load(handle)
    except OSError as error:
        raise RuntimeError(f"could not read seasons file: {error}") from error
    except json.JSONDecodeError as error:
        raise RuntimeError(f"seasons file is not valid JSON: {error}") from error

    if not isinstance(payload, dict) or not isinstance(payload.get("items"), list):
        raise RuntimeError("seasons file does not contain an items array")
    return payload


def normalized_items(payload: dict[str, Any]) -> list[dict[str, Any]]:
    """Return valid, date-sorted season items.

    Items with a missing/unparseable date or endDate are dropped defensively;
    upstream is already sorted ascending, but sorting guards against drift.
    The 1-based season `number` is derived from this sorted order (the data
    file has no ordinal field).
    """
    items: list[dict[str, Any]] = []
    for raw in payload["items"]:
        if not isinstance(raw, dict):
            continue
        try:
            start = date.fromisoformat(str(raw.get("date", "")))
            end = date.fromisoformat(str(raw.get("endDate", "")))
        except ValueError:
            continue
        if end < start:
            continue
        items.append(
            {
                "guid": str(raw.get("guid", "")),
                "name": str(raw.get("name", "")),
                "shortName": str(raw.get("shortName", "")),
                "year": int(raw["year"]) if isinstance(raw.get("year"), (int, float)) else 0,
                "draft": bool(raw.get("draft", False)),
                "start": start,
                "end": end,
            }
        )
    items.sort(key=lambda item: item["start"])
    for number, item in enumerate(items, start=1):
        item["number"] = number
    return items


def _item_payload(item: dict[str, Any]) -> dict[str, Any]:
    """The stable JSON fields shared by current/next seasons."""
    return {
        "guid": item["guid"],
        "name": item["name"],
        "shortName": item["shortName"],
        "number": item["number"],
        "year": item["year"],
        "draft": item["draft"],
    }


def resolve_seasons(payload: dict[str, Any], today: date) -> dict[str, Any]:
    """Resolve the current and next season for `today` (a LA calendar date).

    Pure function — no IO — so tests can drive it with a fixture. The current
    season is the item whose date <= today <= endDate (endDate INCLUSIVE: the
    last day of a season is its too). During the off-season gap between
    seasons, current is None and next points at the upcoming season. Draft
    seasons are never filtered out: SkyGame-Data marks the currently live
    season as draft while its data is being finished.
    """
    items = normalized_items(payload)

    current = None
    for item in items:
        if item["start"] <= today <= item["end"]:
            current = item  # last matching (latest-starting) item wins

    next_item = None
    for item in items:
        if item["start"] > today:
            next_item = item
            break

    result: dict[str, Any] = {
        "generated_at": datetime.now().astimezone().isoformat(),
        "today": today.isoformat(),
        "current": None,
        "next": None,
    }

    if current is not None:
        days_total = (current["end"] - current["start"]).days + 1  # inclusive
        days_elapsed = max(1, min(days_total, (today - current["start"]).days + 1))
        days_remaining = (current["end"] - today).days
        result["current"] = {
            **_item_payload(current),
            "start": current["start"].isoformat(),
            "end": current["end"].isoformat(),
            "days_total": days_total,
            "days_elapsed": days_elapsed,
            "days_remaining": days_remaining,
            "progress": round(days_elapsed / days_total, 4),
        }

    if next_item is not None:
        result["next"] = {
            **_item_payload(next_item),
            "start": next_item["start"].isoformat(),
            "days_until_start": (next_item["start"] - today).days,
        }

    return result


def main() -> int:
    parser = argparse.ArgumentParser(description="Resolve the current Sky season for a date.")
    parser.add_argument(
        "--date",
        type=parse_date,
        help="the Sky calendar date to resolve for (default: today in America/Los_Angeles)",
    )
    parser.add_argument(
        "--seasons-file",
        type=str,
        help="read seasons.json from this file instead of the network (offline/tests)",
    )
    args = parser.parse_args()

    today = args.date if args.date is not None else datetime.now(SKY_TZ).date()

    try:
        if args.seasons_file:
            payload = load_seasons_file(args.seasons_file)
        else:
            payload = fetch_seasons_json()
    except RuntimeError as error:
        print(f"Error: {error}", file=sys.stderr)
        return 2

    result = resolve_seasons(payload, today)
    print(json.dumps(result, separators=(",", ":"), sort_keys=True))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())