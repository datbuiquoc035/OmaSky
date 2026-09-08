// Pure display helpers for the OmaEvents widget. No IO, no Qt state — the
// QML owns fetching and holds the epoch timestamps that these functions
// consume, so every helper is timezone-agnostic (epoch ms == absolute time).

function pad2(n) {
  return (n < 10 ? "0" : "") + n
}

// Current system-local wall time as "HH:MM:SS".
function localTime(ms) {
  var d = ms ? new Date(ms) : new Date()
  return pad2(d.getHours()) + ":" + pad2(d.getMinutes()) + ":" + pad2(d.getSeconds())
}

// System-local wall time as "HH:MM".
function localShort(ms) {
  var d = new Date(ms)
  return pad2(d.getHours()) + ":" + pad2(d.getMinutes())
}

// True when `nowMs` falls inside an occurrence window (start <= now < end).
function isActive(occ, nowMs) {
  return !!occ && occ.start_epoch_ms <= nowMs && nowMs < occ.end_epoch_ms
}

// Human countdown from a millisecond span. alwaysSeconds forces seconds to
// show even when the hours/minutes would do.
function formatCountdown(ms, alwaysSeconds) {
  if (ms === null || ms === undefined || ms < 0) return ""
  var total = Math.floor(ms / 1000)
  var hours = Math.floor(total / 3600)
  var minutes = Math.floor((total % 3600) / 60)
  var seconds = total % 60
  if (hours > 0) return "" + hours + "h " + minutes + "m"
  if (minutes > 0) {
    if (alwaysSeconds) return "" + minutes + "m " + pad2(seconds) + "s"
    return "" + minutes + "m"
  }
  return "" + seconds + "s"
}

// Pick the single most relevant occurrence right now: an event that is
// currently running wins; otherwise the soonest future start wins. The
// Daily Reset is treated as an instant (no active window). Returns
// { name, key, startMs, endMs, active } or null.
function nearestNow(events, reset, nowMs) {
  var active = null
  var upcoming = null

  function consider(name, key, startMs, endMs) {
    var isActiveNow = startMs <= nowMs && endMs !== null && endMs !== undefined && nowMs < endMs
    if (isActiveNow) {
      var takes = !active
        || (endMs !== null && (active.endMs === null || active.endMs === undefined))
        || (endMs !== null && active.endMs !== null && endMs < active.endMs)
      if (takes) active = { name: name, key: key, startMs: startMs, endMs: endMs, active: true }
    } else if (!upcoming || startMs < upcoming.startMs) {
      upcoming = { name: name, key: key, startMs: startMs, endMs: null, active: false }
    }
  }

  if (events) {
    for (var i = 0; i < events.length; i++) {
      var ev = events[i]
      if (!ev || !ev.occurrences || ev.occurrences.length === 0) continue
      var occ = ev.occurrences[0]
      consider(ev.name, ev.key, occ.start_epoch_ms, occ.end_epoch_ms)
    }
  }
  if (reset) consider(reset.name || "Daily Reset", "daily-reset", reset.start_epoch_ms, null)

  return active || upcoming || null
}

// The next occurrence for a specific event (index into events[]), or null.
function nextOccurrence(ev) {
  if (!ev || !ev.occurrences || ev.occurrences.length === 0) return null
  return ev.occurrences[0]
}

// "Today" / "Tomorrow" / "In Nd" relative label for an epoch start, judged
// against the current system-local day.
function dayQualifier(ms, nowMs) {
  var start = new Date(ms)
  var now = new Date(nowMs)
  var sDay = new Date(start.getFullYear(), start.getMonth(), start.getDate())
  var nDay = new Date(now.getFullYear(), now.getMonth(), now.getDate())
  var diff = Math.round((sDay.getTime() - nDay.getTime()) / 86400000)
  if (diff <= 0) return "Today"
  if (diff === 1) return "Tomorrow"
  return "In " + diff + "d"
}

if (typeof module !== "undefined" && module.exports) {
  module.exports = {
    pad2: pad2,
    localTime: localTime,
    localShort: localShort,
    isActive: isActive,
    formatCountdown: formatCountdown,
    nearestNow: nearestNow,
    nextOccurrence: nextOccurrence,
    dayQualifier: dayQualifier,
  }
}