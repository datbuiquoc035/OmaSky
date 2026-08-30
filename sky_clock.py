#!/usr/bin/env python3
"""
Sky Clock - Event Tracker for Sky: Children of the Light
Calculates Geyser, Grandma, and Turtle event times based on sky-clock.netlify.app.

Modes:
  (no args)        print the human-readable table
  --live  / -l     live auto-refreshing countdown table
  --json [COUNT]   print machine-readable JSON for the next COUNT occurrences
                   per event (default 2), plus the next Daily Reset. Used by
                   the OmaEvents omarchy widget.
"""

from __future__ import annotations

import json
import sys
import time
from datetime import datetime, timedelta
from typing import Any
from zoneinfo import ZoneInfo

# Sky Mean Time uses US Pacific Time (handles PST/PDT automatically)
SKY_TZ = ZoneInfo("America/Los_Angeles")

# Defined events: (Name, key, start minute past even hour, duration in minutes)
EVENTS = [
    {"name": "Polluted Geyser", "key": "geyser", "minute": 5, "duration": 10},
    {"name": "Grandma's Dinner", "key": "grandma", "minute": 35, "duration": 10},
    {"name": "Sanctuary Turtle", "key": "turtle", "minute": 50, "duration": 10},
]

# The local system timezone (whatever the machine is set to).
LOCAL_TZ = datetime.now().astimezone().tzinfo  # type: ignore[return-value]


def format_duration(td: timedelta, include_seconds: bool = False) -> str:
    """Format a timedelta into 'Xh Ym' or 'Xh Ym Zs'."""
    total_seconds = int(td.total_seconds())
    hours, remainder = divmod(total_seconds, 3600)
    minutes, seconds = divmod(remainder, 60)

    if include_seconds:
        return f"{hours}h {minutes:02d}m {seconds:02d}s"
    return f"{hours}h {minutes}m"


def get_event_status(now_sky: datetime, event_minute: int, duration_minutes: int):
    """Calculate the next event occurrence, countdown, and active status."""
    # Find the current 2-hour block (even hour: 00, 02, 04, ..., 22)
    even_hour = now_sky.hour - (now_sky.hour % 2)
    block_start = now_sky.replace(
        hour=even_hour, minute=0, second=0, microsecond=0
    )

    current_event_start = block_start + timedelta(minutes=event_minute)
    current_event_end = current_event_start + timedelta(
        minutes=duration_minutes
    )

    if now_sky < current_event_start:
        # Event is upcoming within current 2-hour block
        is_active = False
        next_event_time = current_event_start
        time_to_next = current_event_start - now_sky
        time_left = None
    elif now_sky < current_event_end:
        # Event is currently active
        is_active = True
        next_event_time = current_event_start + timedelta(hours=2)
        time_to_next = next_event_time - now_sky
        time_left = current_event_end - now_sky
    else:
        # Event in current block has ended; next is in the following 2-hour block
        is_active = False
        next_event_time = current_event_start + timedelta(hours=2)
        time_to_next = next_event_time - now_sky
        time_left = None

    return {
        "is_active": is_active,
        "next_sky": next_event_time,
        "time_to_next": time_to_next,
        "time_left": time_left,
    }


def next_occurrences(
    now_sky: datetime, event_minute: int, duration_minutes: int, count: int = 1
) -> list[tuple[datetime, datetime]]:
    """Return the next `count` (start, end) pairs for one event.

    Only occurrences that have not finished yet are returned; the block that
    holds `now` is tried first, so an event that already ran in the current
    2-hour window naturally rolls into the following block.
    """
    even_hour = now_sky.hour - (now_sky.hour % 2)
    block = now_sky.replace(hour=even_hour, minute=0, second=0, microsecond=0)

    results: list[tuple[datetime, datetime]] = []
    # The current block may already contain this event (in the past), so probe
    # a couple of extra blocks to always collect `count` future occurrences.
    for i in range(count + 2):
        start = block + timedelta(hours=2 * i, minutes=event_minute)
        end = start + timedelta(minutes=duration_minutes)
        if end <= now_sky:
            continue
        results.append((start, end))
        if len(results) >= count:
            break
    return results


def next_daily_reset(now_sky: datetime) -> datetime:
    """The next 00:00 Pacific, which is when candles/quests reset."""
    return (now_sky + timedelta(days=1)).replace(
        hour=0, minute=0, second=0, microsecond=0
    )


def to_epoch_ms(moment: datetime) -> int:
    """POSIX milliseconds for a tz-aware datetime."""
    return int(moment.timestamp() * 1000)


def label(moment: datetime) -> str:
    """HH:MM label in a given timezone."""
    return moment.strftime("%H:%M")


def occurrence_to_json(start: datetime, end: datetime) -> dict[str, Any]:
    """One occurrence with both Sky and local (system tz) representations."""
    start_local = start.astimezone(LOCAL_TZ)
    end_local = end.astimezone(LOCAL_TZ)
    return {
        "start_epoch_ms": to_epoch_ms(start),
        "end_epoch_ms": to_epoch_ms(end),
        "start_sky": start.isoformat(),
        "end_sky": end.isoformat(),
        "start_local": start_local.isoformat(),
        "end_local": end_local.isoformat(),
        "start_sky_label": label(start),
        "end_sky_label": label(end),
        "start_local_label": label(start_local),
        "end_local_label": label(end_local),
    }


def build_json(count: int = 2) -> dict[str, Any]:
    """Machine-readable snapshot for the OmaEvents widget."""
    now_local = datetime.now().astimezone()
    now_sky = datetime.now(SKY_TZ)

    events_payload = []
    candidates: list[dict[str, Any]] = []
    for ev in EVENTS:
        occs = next_occurrences(now_sky, ev["minute"], ev["duration"], count)
        status = get_event_status(now_sky, ev["minute"], ev["duration"])
        events_payload.append(
            {
                "key": ev["key"],
                "name": ev["name"],
                "minute": ev["minute"],
                "duration": ev["duration"],
                "is_active": status["is_active"],
                "active_until_epoch_ms": (
                    to_epoch_ms(now_sky + status["time_left"])
                    if status["is_active"] and status["time_left"]
                    else None
                ),
                "occurrences": [occurrence_to_json(s, e) for s, e in occs],
            }
        )
        if occs:
            candidates.append(
                {
                    "name": ev["name"],
                    "key": ev["key"],
                    "start": occs[0][0],
                    "end": occs[0][1],
                }
            )

    reset = next_daily_reset(now_sky)
    reset_local = reset.astimezone(LOCAL_TZ)

    candidates.append(
        {"name": "Daily Reset", "key": "daily-reset", "start": reset, "end": None}
    )

    def is_active_candidate(c: dict[str, Any]) -> bool:
        return bool(c["end"]) and c["start"] <= now_sky < c["end"]

    candidates.sort(
        key=lambda c: (
            0 if is_active_candidate(c) else 1,
            c["start"],
        )
    )
    nearest = candidates[0]
    nearest_active = is_active_candidate(nearest)

    return {
        "generated_at": now_local.isoformat(),
        "sky_tz": str(SKY_TZ),
        "now_sky": now_sky.isoformat(),
        "now_sky_label": label(now_sky),
        "now_local": now_local.isoformat(),
        "now_local_label": label(now_local),
        "events": events_payload,
        "daily_reset": {
            "start_epoch_ms": to_epoch_ms(reset),
            "start_sky": reset.isoformat(),
            "start_local": reset_local.isoformat(),
            "start_sky_label": label(reset),
            "start_local_label": label(reset_local),
            "day_offset": (reset.date() - now_sky.date()).days,
        },
        "nearest": {
            "name": nearest["name"],
            "key": nearest["key"],
            "is_active": nearest_active,
            "start_epoch_ms": to_epoch_ms(nearest["start"]),
            "active_until_epoch_ms": (
                to_epoch_ms(nearest["end"]) if nearest_active else None
            ),
        },
    }


def render_clock(live_mode: bool = False):
    """Fetch current times and print the formatted Sky Clock table."""
    now_local = datetime.now().astimezone()
    now_sky = datetime.now(SKY_TZ)

    # Header with clocks
    output = []
    output.append("=" * 68)
    output.append(
        f" Sky Mean Time: {now_sky.strftime('%H:%M:%S')} (PT)  |  Local Time: {now_local.strftime('%H:%M:%S')}"
    )
    output.append("=" * 68)
    output.append(
        f"{'Event Name':<20} | {'Next (Local)':<12} | {'Next (Sky)':<10} | {'Time to Next':<12} | {'Status'}"
    )
    output.append("-" * 68)

    for ev in EVENTS:
        status = get_event_status(now_sky, ev["minute"], ev["duration"])

        # Convert next start time to local time
        next_local = status["next_sky"].astimezone(now_local.tzinfo)

        next_local_str = next_local.strftime("%H:%M")
        next_sky_str = status["next_sky"].strftime("%H:%M")
        time_to_next_str = format_duration(
            status["time_to_next"], include_seconds=live_mode
        )

        if status["is_active"]:
            active_left_str = format_duration(
                status["time_left"], include_seconds=live_mode
            )
            state_str = f"ACTIVE (ends in {active_left_str})"
        else:
            state_str = "Upcoming"

        output.append(
            f"{ev['name']:<20} | {next_local_str:<12} | {next_sky_str:<10} | {time_to_next_str:<12} | {state_str}"
        )

    output.append("=" * 68)
    return "\n".join(output)


def main():
    # Pass --live or -l to run as a live auto-refreshing countdown
    args = sys.argv[1:]
    live_mode = "--live" in args or "-l" in args
    json_mode = "--json" in args

    if json_mode:
        try:
            json_index = args.index("--json")
            count_arg = args[json_index + 1] if json_index + 1 < len(args) else None
            count = max(1, min(10, int(count_arg))) if count_arg else 2
        except (ValueError, TypeError):
            count = 2
        print(json.dumps(build_json(count), sort_keys=True))
        return

    if live_mode:
        print("Starting live Sky Clock (Press Ctrl+C to stop)...\n")
        try:
            while True:
                # Clear terminal screen (ANSI escape)
                sys.stdout.write("\033[H\033[J")
                sys.stdout.write(render_clock(live_mode=True) + "\n")
                sys.stdout.flush()
                time.sleep(1)
        except KeyboardInterrupt:
            print("\nExited Sky Clock.")
    else:
        print(render_clock(live_mode=False))


if __name__ == "__main__":
    main()