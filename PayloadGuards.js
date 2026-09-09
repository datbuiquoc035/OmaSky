// Pure payload guards for the OmaSky widget — no IO, no Qt state.
//
// Why this exists: the panel used to freeze the whole shell on open when a
// network payload (or a poisoned on-disk cache) contained an unbounded array.
// QML Repeater instantiates every delegate synchronously on the UI thread, so
// a 10-20k `occurrences` array = instant freeze that survives reboot via the
// cache. These helpers cap/validate everything before it reaches a Repeater,
// and are unit-tested with node (tests/test_guards.js).

var MAX_EVENTS = 10
var MAX_EVENT_OCCURRENCES = 10
var MAX_SHARD_OCCURRENCES = 3
var MAX_DAYS = 7
var MAX_RAW_BYTES = 65536 // 64 KiB — normal caches are <2 KiB
var MIN_FETCH_GAP_MS = 2000
var PROCESS_TIMEOUT_MS = 20000

function capArray(arr, max) {
  if (!Array.isArray(arr)) return []
  if (arr.length <= max) return arr
  return arr.slice(0, max)
}

function isObject(value) {
  return !!value && typeof value === "object" && !Array.isArray(value)
}

// Events payload from sky_clock.py --json. Returns a sanitized copy or null.
function sanitizeEventsPayload(payload) {
  if (!isObject(payload) || !Array.isArray(payload.events)) return null
  var events = capArray(payload.events, MAX_EVENTS).map(function(ev) {
    if (!isObject(ev)) return null
    var occs = Array.isArray(ev.occurrences)
      ? capArray(ev.occurrences, MAX_EVENT_OCCURRENCES)
      : []
    var out = {}
    for (var key in ev) out[key] = ev[key]
    out.occurrences = occs
    return out
  }).filter(function(ev) { return ev !== null })
  var out = {}
  for (var key in payload) out[key] = payload[key]
  out.events = events
  return out
}

// Shard payload from fetch_shard_details.py. Returns a sanitized copy or
// null when the shape is unusable. Occurrences are capped to 3 — the schedule
// never produces more (3 eruptions per shard day).
function sanitizeShardPayload(payload) {
  if (!isObject(payload) || typeof payload.has_shard !== "boolean") return null
  if (payload.has_shard !== true) return payload
  if (!isObject(payload.realm) || !isObject(payload.location)) return null
  if (!Array.isArray(payload.occurrences)) return null
  var out = {}
  for (var key in payload) out[key] = payload[key]
  out.occurrences = capArray(payload.occurrences, MAX_SHARD_OCCURRENCES)
  return out
}

// Season payload from fetch_seasons.py. Returns payload as-is when the shape
// is usable, otherwise null.
function sanitizeSeasonPayload(payload) {
  if (!isObject(payload) || typeof payload.today !== "string") return null
  return payload
}

// On-disk cache envelope: { date, payload }. Rejects oversized raw text
// before JSON.parse so a 1 MiB poisoned file never reaches the UI thread as
// 20k delegates.
function parseCacheEnvelope(raw, expectedDate) {
  var text = String(raw || "").trim()
  if (!text) return null
  if (text.length > MAX_RAW_BYTES) return { tooLarge: true }
  var parsed = null
  try {
    parsed = JSON.parse(text)
  } catch (error) {
    return null
  }
  if (!isObject(parsed)) return null
  if (parsed.date !== expectedDate || !isObject(parsed.payload)) return null
  return parsed
}

// Debounce helper: true when a fetch should be skipped because the last one
// was too recent (unless forceLive).
function shouldSkipFetch(lastMs, nowMs, forceLive, minGapMs) {
  if (forceLive === true) return false
  var gap = minGapMs !== undefined ? minGapMs : MIN_FETCH_GAP_MS
  if (!lastMs) return false
  return (nowMs - lastMs) < gap
}

// Pure version of the ShardsTab upcoming-list logic: non-null shards after
// today, in order, capped at upcomingCount (1..7) and MAX_DAYS.
function upcomingShards(days, upcomingCount) {
  var out = []
  if (!Array.isArray(days)) return out
  var cap = Math.max(1, Math.min(MAX_DAYS, Number(upcomingCount) || 3))
  for (var i = 1; i < days.length && i <= MAX_DAYS; i++) {
    if (!days[i]) continue
    out.push(days[i])
    if (out.length >= cap) break
  }
  return out
}

if (typeof module !== "undefined" && module.exports) {
  module.exports = {
    MAX_EVENTS: MAX_EVENTS,
    MAX_EVENT_OCCURRENCES: MAX_EVENT_OCCURRENCES,
    MAX_SHARD_OCCURRENCES: MAX_SHARD_OCCURRENCES,
    MAX_DAYS: MAX_DAYS,
    MAX_RAW_BYTES: MAX_RAW_BYTES,
    MIN_FETCH_GAP_MS: MIN_FETCH_GAP_MS,
    PROCESS_TIMEOUT_MS: PROCESS_TIMEOUT_MS,
    capArray: capArray,
    sanitizeEventsPayload: sanitizeEventsPayload,
    sanitizeShardPayload: sanitizeShardPayload,
    sanitizeSeasonPayload: sanitizeSeasonPayload,
    parseCacheEnvelope: parseCacheEnvelope,
    shouldSkipFetch: shouldSkipFetch,
    upcomingShards: upcomingShards,
  }
}
