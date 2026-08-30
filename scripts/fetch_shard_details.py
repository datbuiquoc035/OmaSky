#!/usr/bin/env python3
"""Fetch and resolve Sky Shards details for one calendar date.

Usage:
    python3 fetch_shard_details.py 2026-08-28

Times are reported in the local system timezone. The remote API
(https://sky-shardfig.plutoy.top/all.json) is the sole data source;
the schedule math is bundled directly — no external API call is needed
beyond fetching the daily overrides.
"""

from __future__ import annotations

import argparse
import json
import sys
from datetime import UTC, date, datetime, timedelta
from typing import Any
from urllib.error import HTTPError, URLError
from urllib.request import Request, urlopen
from zoneinfo import ZoneInfo


REMOTE_CONFIG_URL = "https://sky-shardfig.plutoy.top/all.json"


def get_local_tz() -> ZoneInfo:
    """Return the system's local timezone from the current datetime."""
    return datetime.now().astimezone().tzinfo  # type: ignore[return-value]
REALMS = ["prairie", "forest", "valley", "wasteland", "vault"]
REALM_NAMES = {
    "prairie": "Daylight Prairie",
    "forest": "Hidden Forest",
    "valley": "Valley of Triumph",
    "wasteland": "Golden Wasteland",
    "vault": "Vault of Knowledge",
}
MAP_NAMES = {
    "prairie.butterfly": "Butterfly Fields",
    "prairie.village": "Village Islands",
    "prairie.cave": "Cave",
    "prairie.bird": "Bird Nest",
    "prairie.island": "Sanctuary Island",
    "forest.brook": "Brook",
    "forest.boneyard": "Boneyard",
    "forest.end": "Forest Garden",
    "forest.tree": "Treehouse",
    "forest.sunny": "Elevated Clearing",
    "valley.rink": "Ice Rink",
    "valley.dreams": "Village of Dreams",
    "valley.hermit": "Hermit Valley",
    "wasteland.temple": "Broken Temple",
    "wasteland.battlefield": "Battlefield",
    "wasteland.graveyard": "Graveyard",
    "wasteland.crab": "Crab Field",
    "wasteland.ark": "Forgotten Ark",
    "vault.starlight": "Starlight Desert",
    "vault.jelly": "Jellyfish Cove",
}
SCHEDULES = [
    {"no_shard_weekdays": [6, 7], "interval_hours": 8, "offset": (1, 50), "maps": ["prairie.butterfly", "forest.brook", "valley.rink", "wasteland.temple", "vault.starlight"]},
    {"no_shard_weekdays": [7, 1], "interval_hours": 8, "offset": (2, 10), "maps": ["prairie.village", "forest.boneyard", "valley.rink", "wasteland.battlefield", "vault.starlight"]},
    {"no_shard_weekdays": [1, 2], "interval_hours": 6, "offset": (7, 40), "maps": ["prairie.cave", "forest.end", "valley.dreams", "wasteland.graveyard", "vault.jelly"], "def_reward_ac": 2},
    {"no_shard_weekdays": [2, 3], "interval_hours": 6, "offset": (2, 20), "maps": ["prairie.bird", "forest.tree", "valley.dreams", "wasteland.crab", "vault.jelly"], "def_reward_ac": 2.5},
    {"no_shard_weekdays": [3, 4], "interval_hours": 6, "offset": (3, 30), "maps": ["prairie.island", "forest.sunny", "valley.hermit", "wasteland.ark", "vault.jelly"], "def_reward_ac": 3.5},
]

BASE_REWARDS = {
    "prairie.butterfly": 3, "prairie.village": 3, "prairie.bird": 2, "prairie.island": 3,
    "forest.brook": 2, "forest.end": 2, "forest.tree": 3, "forest.sunny": 1,
    "valley.rink": 3, "valley.dreams": 2, "valley.hermit": 1,
    "wasteland.temple": 3, "wasteland.battlefield": 3, "wasteland.graveyard": 2,
    "wasteland.crab": 2, "wasteland.ark": 4,
    "vault.starlight": 3, "vault.jelly": 2,
}
RED_REWARDS = {
    "forest.end": 2.5, "valley.dreams": 2.5, "forest.tree": 3.5, "vault.jelly": 3.5,
}
VARIANTS = {
    "prairie.butterfly": 3, "prairie.village": 3, "prairie.bird": 2, "prairie.island": 3,
    "forest.brook": 2, "forest.end": 2, "forest.tree": 3, "forest.sunny": 1,
    "valley.rink": 3, "valley.dreams": 2, "valley.hermit": 1,
    "wasteland.temple": 3, "wasteland.battlefield": 3, "wasteland.graveyard": 2,
    "wasteland.crab": 2, "wasteland.ark": 4,
    "vault.starlight": 3, "vault.jelly": 2,
}


def parse_date(value: str) -> date:
    """Validate an ISO calendar date."""
    try:
        return date.fromisoformat(value)
    except ValueError as error:
        raise argparse.ArgumentTypeError("date must use YYYY-MM-DD format") from error


def fetch_remote_config() -> dict[str, Any]:
    """Download and validate the full remote configuration response."""
    request = Request(REMOTE_CONFIG_URL, headers={"User-Agent": "sky-shards-config-fetcher/1.0"})
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

    if not isinstance(payload, dict) or not isinstance(payload.get("dailiesMap"), dict):
        raise RuntimeError("API response does not contain a dailiesMap object")
    return payload


def add_elapsed(moment: datetime, duration: timedelta) -> datetime:
    """Add elapsed time, matching Luxon's hour-based duration behaviour across DST."""
    return (moment.astimezone(UTC) + duration).astimezone(get_local_tz())


def get_override_value(override: dict[str, Any], name: str, default: Any) -> Any:
    return override[name] if name in override and override[name] is not None else default


def resolve_shard_details(target_date: date, daily_config: dict[str, Any] | None) -> dict[str, Any]:
    """Reproduce the app's getShardInfo calculation with its remote override applied."""
    override = daily_config.get("override") if isinstance(daily_config, dict) else None
    override = override if isinstance(override, dict) else {}
    day_of_month = target_date.day
    weekday = target_date.isoweekday()
    is_red = get_override_value(override, "isRed", day_of_month % 2 == 1)
    realm_index = get_override_value(override, "realm", (day_of_month - 1) % 5)
    schedule_index = get_override_value(
        override,
        "group",
        ((day_of_month - 1) // 2) % 3 + 2 if day_of_month % 2 == 1 else (day_of_month // 2) % 2,
    )

    if not isinstance(realm_index, int) or not 0 <= realm_index < len(REALMS):
        raise RuntimeError("remote override contains an invalid realm index")
    if not isinstance(schedule_index, int) or not 0 <= schedule_index < len(SCHEDULES):
        raise RuntimeError("remote override contains an invalid group index")

    schedule = SCHEDULES[schedule_index]
    has_shard = get_override_value(override, "hasShard", weekday not in schedule["no_shard_weekdays"])
    map_id = get_override_value(override, "map", schedule["maps"][realm_index])
    realm_id = REALMS[realm_index]
    default_reward = schedule.get("def_reward_ac")
    if is_red:
        reward_ac = RED_REWARDS.get(map_id, default_reward)
    else:
        reward_ac = BASE_REWARDS.get(map_id)
    result: dict[str, Any] = {
        "date": target_date.isoformat(),
        "timezone": str(get_local_tz()),
        "has_shard": bool(has_shard),
        "remote_config_applied": bool(override),
    }

    if not has_shard:
        result["message"] = "No shard eruption is scheduled for this date."
        return result

    la_tz = ZoneInfo("America/Los_Angeles")
    local_tz = get_local_tz()
    midnight_la = datetime.combine(target_date, datetime.min.time(), tzinfo=la_tz)
    offset_hours, offset_minutes = schedule["offset"]
    first_start_la = midnight_la + timedelta(hours=offset_hours, minutes=offset_minutes)
    if weekday == 7 and midnight_la.dst() != first_start_la.dst():
        first_start_la += timedelta(hours=-1 if first_start_la.dst() else 1)

    occurrences = []
    for number in range(3):
        start_la = first_start_la + timedelta(hours=schedule["interval_hours"] * number)
        landing_la = start_la + timedelta(minutes=8, seconds=40)
        end_la = start_la + timedelta(hours=4)
        occurrences.append(
            {
                "number": number + 1,
                "start": start_la.astimezone(local_tz).isoformat(),
                "landing": landing_la.astimezone(local_tz).isoformat(),
                "end": end_la.astimezone(local_tz).isoformat(),
            }
        )

    result.update(
        {
            "color": "red" if is_red else "black",
            "realm": {"id": realm_id, "name": REALM_NAMES[realm_id]},
            "location": {"id": map_id, "name": MAP_NAMES.get(map_id, map_id)},
            "rewardAC": reward_ac,
            "variant": VARIANTS.get(map_id, 1),
            "occurrences": occurrences,
        }
    )
    return result


def main() -> int:
    parser = argparse.ArgumentParser(description="Fetch and resolve Sky Shards details for a date.")
    parser.add_argument("date", type=parse_date, help="date to look up, in YYYY-MM-DD format")
    args = parser.parse_args()

    try:
        config = fetch_remote_config()
        daily_config = config["dailiesMap"].get(args.date.isoformat())
        details = resolve_shard_details(args.date, daily_config)
    except RuntimeError as error:
        print(f"Error: {error}", file=sys.stderr)
        return 2

    print(json.dumps(details, indent=2, sort_keys=True))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
