const assert = require("assert");
const Guards = require("../PayloadGuards.js");

// capArray: returns same ref when under cap (no Repeater churn), slices over.
{
  const small = [1, 2, 3];
  assert.strictEqual(Guards.capArray(small, 10), small, "under-cap must not allocate");
  const big = Array.from({ length: 20000 }, (_, i) => i);
  const capped = Guards.capArray(big, 3);
  assert.strictEqual(capped.length, 3, "over-cap must slice");
  assert.deepStrictEqual(Guards.capArray(null, 3), []);
  console.log("PASS test_cap_array");
}

// sanitizeEventsPayload: caps events + occurrences, rejects malformed.
{
  const evil = {
    events: Array.from({ length: 500 }, (_, i) => ({
      name: "E" + i, key: "e" + i,
      occurrences: Array.from({ length: 100 }, () => ({ start_epoch_ms: 1, end_epoch_ms: 2 })),
    })),
  };
  const clean = Guards.sanitizeEventsPayload(evil);
  assert(clean !== null);
  assert(clean.events.length <= Guards.MAX_EVENTS, "events capped to " + Guards.MAX_EVENTS);
  assert(clean.events.every((e) => e.occurrences.length <= Guards.MAX_EVENT_OCCURRENCES));
  assert.strictEqual(Guards.sanitizeEventsPayload(null), null);
  assert.strictEqual(Guards.sanitizeEventsPayload({}), null);
  assert.strictEqual(Guards.sanitizeEventsPayload({ events: "nope" }), null);
  console.log("PASS test_sanitize_events");
}

// sanitizeShardPayload: the panel-freeze case — 20k occurrences -> 3.
{
  const evil = {
    has_shard: true,
    realm: { id: "prairie", name: "Daylight Prairie" },
    location: { id: "prairie.butterfly", name: "Butterfly Fields" },
    color: "red",
    occurrences: Array.from({ length: 20000 }, () => ({
      start: new Date().toISOString(), landing: new Date().toISOString(), end: new Date().toISOString(),
    })),
  };
  const clean = Guards.sanitizeShardPayload(evil);
  assert(clean !== null);
  assert.strictEqual(clean.occurrences.length, Guards.MAX_SHARD_OCCURRENCES);
  assert.strictEqual(Guards.sanitizeShardPayload({ has_shard: false }).has_shard, false);
  assert.strictEqual(Guards.sanitizeShardPayload(null), null);
  assert.strictEqual(Guards.sanitizeShardPayload({ has_shard: true }), null);
  assert.strictEqual(Guards.sanitizeShardPayload({ has_shard: "yes" }), null);
  console.log("PASS test_sanitize_shard_freeze_case");
}

// sanitizeSeasonPayload
{
  assert.strictEqual(Guards.sanitizeSeasonPayload(null), null);
  assert.strictEqual(Guards.sanitizeSeasonPayload({}), null);
  const ok = { today: "2026-09-09", current: null, next: null };
  assert.strictEqual(Guards.sanitizeSeasonPayload(ok), ok);
  console.log("PASS test_sanitize_season");
}

// parseCacheEnvelope: rejects oversized before JSON.parse, validates date.
{
  const big = "x".repeat(Guards.MAX_RAW_BYTES + 1);
  const tooLarge = Guards.parseCacheEnvelope(big, "2026-09-09");
  assert(tooLarge && tooLarge.tooLarge === true, "oversized cache must short-circuit");
  assert.strictEqual(Guards.parseCacheEnvelope("", "2026-09-09"), null);
  assert.strictEqual(Guards.parseCacheEnvelope("not json", "2026-09-09"), null);
  const wrongDate = JSON.stringify({ date: "2026-01-01", payload: { has_shard: false } });
  assert.strictEqual(Guards.parseCacheEnvelope(wrongDate, "2026-09-09"), null);
  const good = JSON.stringify({ date: "2026-09-09", payload: { has_shard: false } });
  const parsed = Guards.parseCacheEnvelope(good, "2026-09-09");
  assert(parsed && parsed.payload.has_shard === false);
  console.log("PASS test_cache_envelope");
}

// shouldSkipFetch: debounce — rapid double open collapses to one batch.
{
  const now = 1000000;
  assert.strictEqual(Guards.shouldSkipFetch(0, now, false), false, "first fetch runs");
  assert.strictEqual(Guards.shouldSkipFetch(now - 500, now, false), true, "500ms later skips");
  assert.strictEqual(Guards.shouldSkipFetch(now - 500, now, true), false, "forceLive bypasses");
  assert.strictEqual(Guards.shouldSkipFetch(now - 5000, now, false), false, "after gap runs");
  console.log("PASS test_debounce");
}

// upcomingShards: pure, capped, skips nulls.
{
  const days = [null, { date: "d1" }, null, { date: "d3" }, { date: "d4" }, { date: "d5" }];
  const out = Guards.upcomingShards(days, 2);
  assert.strictEqual(out.length, 2);
  assert.strictEqual(out[0].date, "d1");
  assert.deepStrictEqual(Guards.upcomingShards(null, 3), []);
  const many = [null].concat(Array.from({ length: 20 }, (_, i) => ({ date: "d" + i })));
  assert(Guards.upcomingShards(many, 7).length <= 7);
  console.log("PASS test_upcoming_shards");
}

console.log("\nall guard tests passed");
