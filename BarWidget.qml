import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui
import "EventsModel.js" as EventsModel
import "ShardModel.js" as ShardModel
import "PayloadGuards.js" as Guards

// Bar label for Sky: Children of the Light — a logo with a single line that
// shows both the next world event (with a live countdown) and today's shard
// (color emoji + map). Hosts the tabbed OmaSky panel.
//
// Two independent data sources:
//   * sky_clock.py       — deterministic schedule for Geyser / Grandma / Turtle
//                          plus the daily reset (America/Los_Angeles), fetched
//                          over direct process call every refreshSeconds.
//   * fetch_shard_details.py — live-realm overrides + bundled schedule math for
//                              today's eruption, over the network, cached on
//                              disk per LA game day, refreshed every
//                              shardRefreshSeconds.
//
// Between event fetches a 1s ticker drives countdowns from absolute epoch
// timestamps, so the label/panel always track the system clock.
//
// Left click reveals the panel; right click cycles the label format
// (both / events / shard); middle click force-refreshes everything.
BarWidget {
  id: root
  moduleName: "qdot.omasky"

  // ---- Events state ------------------------------------------------------
  property var events: []              // parsed events[] from sky_clock.py
  property var dailyReset: null        // parsed daily_reset object
  property var nearest: root.computeNearest()
  property string eventError: ""
  property bool eventsLoading: true
  property string nowSkyLabel: ""      // HH:MM game time (America/Los_Angeles)
  property string nowLocalLabel: ""    // HH:MM system local time

  // ---- Shards state ------------------------------------------------------
  property var days: []           // computeDays() output for the next few days
  property var todayShard: null   // today's entry (null if none / loading)
  property string shardError: ""
  property bool shardsLoading: true

  // ---- Season state ------------------------------------------------------
  // Season (payload.current) and the next upcoming season (payload.next), as
  // computed by scripts/fetch_seasons.py. current is null during the
  // off-season gap; next may be null when nothing is announced yet.
  property var season: null
  property var nextSeason: null
  property string seasonError: ""
  property bool seasonsLoading: true
  property string seasonToday: ""   // LA calendar date the script resolved for

  // Tick source for all live countdown/clock rendering. Re-assigned every
  // second by clockTimer, which re-evaluates every binding that reads it.
  // Must be a double: epoch milliseconds (~1.79e12) overflow QML's 32-bit int.
  property double nowMs: new Date().getTime()

  readonly property bool vertical: bar ? bar.vertical : false

  // Display timezone as a UTC offset in hours for the shard eruption times.
  // The schedule math happens on absolute instants, so the label/panel just
  // shift by this. The setting accepts "UTC+n" / "UTC-n", the timezone
  // database name, or a plain numeric offset; empty falls back to the
  // system's own offset.
  readonly property real displayTzOffset: parseTzOffset(setting("timeZone", ""), -new Date().getTimezoneOffset() / 60)

  function parseTzOffset(raw, fallback) {
    var value = String(raw === undefined || raw === null ? "" : raw).trim()
    if (value === "") return fallback
    if (/^UTC\s*[+-]?\d+$/i.test(value)) {
      var numeric = parseFloat(value.replace(/^UTC\s*/i, ""))
      return clampOffset(numeric)
    }
    var parsed = parseFloat(value)
    if (isFinite(parsed)) return clampOffset(parsed)
    return fallback
  }

  function clampOffset(value) {
    if (!isFinite(value)) return 0
    if (value < -14) return -14
    if (value > 14) return 14
    return Math.round(value * 2) / 2
  }

  readonly property string tzLabel: {
    var raw = String(setting("timeZone", "")).trim()
    if (raw === "") return "Local"
    if (/^UTC\s*[+-]?\d+$/i.test(raw)) return raw.toUpperCase()
    var parsed = parseFloat(raw)
    if (isFinite(parsed)) return "UTC" + (parsed >= 0 ? "+" : "") + String(parsed)
    return raw
  }

  // Bar label format: "both" (default), "events", or "shard". Right-click
  // cycles. Inside shard mode, a second format key ("map"/"realm"/"full")
  // picks how granular the shard piece is.
  readonly property string labelMode: setting("format", "both")
  readonly property string shardFormat: setting("shardFormat", "map")
  readonly property string nextLabelMode: {
    var modes = ["both", "events", "shard"]
    return modes[(modes.indexOf(labelMode) + 1) % modes.length]
  }

  readonly property int upcomingDays: Math.max(1, Math.min(7, Number(setting("upcomingDays", 3)) || 3))

  // ---- Combined label ----------------------------------------------------
  function shardLabelPart() {
    if (!root.todayShard) return null
    var value = root.todayShard.shardColor === "Red" ? "🔴" : "⚫"
    if (root.shardFormat === "realm") return value + " " + root.todayShard.realm
    if (root.shardFormat === "full") return value + " " + root.todayShard.map + " · " + root.todayShard.realm
    return value + " " + root.todayShard.map
  }

  function eventLabelPart() {
    var n = root.nearest
    if (!n) return null
    if (n.active) {
      return n.name + " · " + EventsModel.formatCountdown(n.endMs - root.nowMs) + " left"
    }
    return n.name + " in " + EventsModel.formatCountdown(n.startMs - root.nowMs)
  }

  function barLabelText() {
    var shardPart = root.shardLabelPart()
    var eventPart = root.eventLabelPart()
    if (root.labelMode === "events") return eventPart !== null ? eventPart : (root.eventsLoading ? "…" : "No events")
    if (root.labelMode === "shard") return shardPart !== null ? shardPart : (root.shardsLoading ? "…" : "No shard today")
    if (eventPart !== null && shardPart !== null) return shardPart + " · " + eventPart
    if (eventPart !== null) return eventPart
    if (shardPart !== null) return shardPart
    return root.eventsLoading && root.shardsLoading ? "…" : "No events · no shard"
  }

  readonly property bool anyActive: root.nearest ? root.nearest.active === true : false

  readonly property bool showingEventsInLabel: root.labelMode !== "shard" && root.nearest !== null
  readonly property color liveForeground:
    root.showingEventsInLabel && root.anyActive
      ? Color.accent
      : (root.bar ? root.bar.foreground : Color.foreground)

  readonly property string displayText: root.barLabelText()
  readonly property string tooltipSummary: root.tooltipText()

  function resolveNow() {
    var reset = root.setting("showDailyReset", true) === false ? null : root.dailyReset
    return EventsModel.nearestNow(root.events, reset, root.nowMs)
  }

  function computeNearest() {
    return root.resolveNow()
  }

  // ---- Fetching: events --------------------------------------------------
  // NOTE: Math.max operates in seconds here — the *1000 converts to ms.
  // (A previous revision compared seconds against 15000ms, pinning the timer
  // to ~4h and leaving stale events to panel-open only.)
  readonly property int fetchIntervalMs: Math.max(15, Number(setting("refreshSeconds", 60)) || 60) * 1000

  // Debounce + single-flight guards: panel open fires fetchData() twice
  // (BarWidget.open + Panel.open.refresh) within ms, and Enter/Space
  // auto-repeats refresh() at ~30Hz. Without these the widget kill-restarts
  // 6 python procs per open and can stall the compositor.
  property double lastFetchMs: 0
  readonly property int minFetchGapMs: Guards.MIN_FETCH_GAP_MS
  readonly property int procTimeoutMs: Guards.PROCESS_TIMEOUT_MS
  property bool migrateBusy: false
  property bool rescanPending: false

  readonly property string pluginDir: {
    var url = Qt.resolvedUrl(".")
    var p = url.toString().replace(/^file:\/\//, "")
    if (p.length === 0 || p.charAt(p.length - 1) !== "/") p += "/"
    return p
  }
  readonly property string scriptPath: pluginDir + "sky_clock.py"

  function runEventsScript() {
    // Single-flight: never kill-restart an in-flight fetch. The second half
    // of a double-fetch (open storm) simply skips while the first runs.
    if (eventsProc.running === true) return
    root.eventsLoading = true
    eventsProc.workingDirectory = root.pluginDir
    eventsProc.command = ["python3", root.scriptPath, "--json", "3"]
    eventsProc.running = true
    eventsTimeout.restart()
  }

  function fetchEvents() {
    root.runEventsScript()
  }

  function settleEvents(payload) {
    var clean = Guards.sanitizeEventsPayload(payload)
    if (!clean) {
      if (!root.eventError) root.eventError = "Malformed event response"
      return
    }
    root.eventError = ""
    root.events = clean.events
    root.dailyReset = clean.daily_reset ? clean.daily_reset : null
    root.nowSkyLabel = clean.now_sky_label ? String(clean.now_sky_label) : ""
    root.nowLocalLabel = clean.now_local_label ? String(clean.now_local_label) : ""
    root.eventsLoading = false
    root.notifyPanel()
  }

  function failEvents(message) {
    if (root.events.length === 0) root.eventError = message
    root.eventsLoading = false
    root.notifyPanel()
  }

  // ---- Fetching: shards ---------------------------------------------------
  readonly property int shardFetchIntervalMs: Math.max(60, Number(setting("shardRefreshSeconds", 1800)) || 1800) * 1000

  // Season data only changes when a season starts/ends (~monthly) or the
  // dataset is updated, so a 6h default is plenty; the per-LA-day cache
  // prevents needless refetches between rolls.
  readonly property int seasonFetchIntervalMs: Math.max(3600, Number(setting("seasonRefreshSeconds", 21600)) || 21600) * 1000

  function todayDateKey() {
    var now = new Date()
    return now.getFullYear() + "-" + String(now.getMonth() + 1).padStart(2, "0") + "-" + String(now.getDate()).padStart(2, "0")
  }

  // Calendar date in the game's home timezone (America/Los_Angeles). The
  // shard schedule resets at midnight LA, so the cache is keyed to that date
  // rather than the local date: the cache stays valid until LA midnight,
  // which is what actually starts a new game day.
  function laDateKey() {
    var now = new Date()
    var tzMinutes = ShardModel.laOffsetMinutes(
      now.getFullYear(), now.getMonth(), now.getDate(),
      now.getHours(), now.getMinutes()
    )
    var laUtc = new Date(now.getTime() + tzMinutes * 60000)
    return laUtc.getUTCFullYear() + "-" +
      String(laUtc.getUTCMonth() + 1).padStart(2, "0") + "-" +
      String(laUtc.getUTCDate()).padStart(2, "0")
  }

  readonly property string shardScriptPath: pluginDir + "scripts/fetch_shard_details.py"

  function runShardScript() {
    if (shardProc.running === true) return
    root.shardsLoading = true
    shardProc.workingDirectory = root.pluginDir
    shardProc.command = ["python3", root.shardScriptPath, root.laDateKey()]
    shardProc.running = true
    shardTimeout.restart()
  }

  // Fetch today's data. When forceLive is false, a valid in-memory cache for
  // the current game day (midnight LA) short-circuits the network fetch.
  function fetchShards(forceLive) {
    if (forceLive !== true && root.shardCacheState &&
        root.cachedLaDate === root.laDateKey() && root.cachedPayload) {
      root.settleSchedule(root.cachedPayload)
      return
    }
    root.runShardScript()
  }

  function fetchData(forceLive) {
    var now = new Date().getTime()
    if (Guards.shouldSkipFetch(root.lastFetchMs, now, forceLive === true, root.minFetchGapMs)) return
    root.lastFetchMs = now
    root.runEventsScript()
    root.fetchShards(forceLive === true)
    root.fetchSeasons(forceLive === true)
  }

  function shardFromScript(payload) {
    var clean = Guards.sanitizeShardPayload(payload)
    if (!clean || clean.has_shard !== true) return null
    if (!clean.realm || !clean.location || !Array.isArray(clean.occurrences)) return null
    return {
      date: clean.date,
      isToday: true,
      realm: clean.realm.name,
      realmKey: clean.realm.id,
      map: clean.location.name,
      mapKey: clean.location.id,
      shardColor: clean.color === "red" ? "Red" : "Black",
      isRed: clean.color === "red",
      rewardAc: clean.rewardAC ? Number(clean.rewardAC) : null,
      variant: Number(clean.variant) || 1,
      // Capped to 3 by sanitizeShardPayload — the schedule never yields more,
      // and an uncapped Repeater would freeze the shell on open (H1).
      occurrences: clean.occurrences.map(function(occurrence) {
        return {
          start: new Date(occurrence.start),
          land: new Date(occurrence.landing),
          end: new Date(occurrence.end),
        }
      }),
    }
  }

  function settleSchedule(payload) {
    var clean = Guards.sanitizeShardPayload(payload)
    // Null payload with no fallback means "no shard today", not an error:
    // keep the computed week so UPCOMING still renders.
    if (payload && !clean) {
      if (!root.shardError) root.shardError = "Malformed shard details response"
    }
    root.days = Guards.capArray(ShardModel.computeDays(root.upcomingDays, {}), Guards.MAX_DAYS)
    root.todayShard = clean ? root.shardFromScript(clean) : null
    if (root.days.length > 0) root.days[0] = root.todayShard
    root.shardsLoading = false
    root.notifyPanel()
  }

  // settleSchedule wrapper that falls back to the last-known-good cached
  // payload when a fetch fails, so the label/panel never blank out.
  function settleWithFallback(payload) {
    if (!payload && root.shardCacheState &&
        root.cachedLaDate === root.laDateKey() && root.cachedPayload) {
      payload = root.cachedPayload
    }
    root.settleSchedule(payload)
  }

  function notifyPanel() {
    if (panelLoader.item && panelLoader.item.onDataChanged) panelLoader.item.onDataChanged()
  }

  // ---- Fetching: seasons --------------------------------------------------
readonly property string seasonScriptPath: pluginDir + "scripts/fetch_seasons.py"

function runSeasonScript() {
    if (seasonProc.running === true) return
    root.seasonsLoading = true
    seasonProc.workingDirectory = root.pluginDir
    seasonProc.command = ["python3", root.seasonScriptPath]
    seasonProc.running = true
    seasonTimeout.restart()
  }

  function fetchSeasons(forceLive) {
    if (forceLive !== true && root.seasonCacheState &&
        root.seasonCacheDate === root.laDateKey() && root.seasonCachedPayload) {
      root.settleSeasons(root.seasonCachedPayload)
      return
    }
    root.runSeasonScript()
  }

  function settleSeasons(payload) {
    var clean = Guards.sanitizeSeasonPayload(payload)
    if (!clean) {
      if (!root.seasonError) root.seasonError = "Malformed season response"
      return
    }
    payload = clean
    root.seasonError = ""
    root.season = payload.current ? payload.current : null
    root.nextSeason = payload.next ? payload.next : null
    root.seasonToday = payload.today
    root.seasonsLoading = false
    root.notifyPanel()
  }

  function failSeasons(message) {
    if (!root.seasonError) root.seasonError = message
    root.seasonsLoading = false
    root.notifyPanel()
  }

  // settleSeasons wrapper that falls back to the last-known-good cached
  // payload when a fetch fails, so the tab never blanks out.
  function settleWithSeasonFallback(payload) {
    if (!payload && root.seasonCacheState &&
        root.seasonCacheDate === root.laDateKey() && root.seasonCachedPayload) {
      payload = root.seasonCachedPayload
    }
    root.settleSeasons(payload)
  }

  // ---- Daily on-disk shard cache -------------------------------------------
  // Persist today's (LA game day) payload so the network is hit at most once
  // per day, across shell restarts. Keyed to midnight America/Los_Angeles,
  // which is when the game day actually resets. Read back with a FileView,
  // written through a python Process (the FileView atomic write was observed
  // to silently fail to persist for this kind of payload).
  readonly property string home: Quickshell.env("HOME")
  readonly property string cacheDir: home + "/.local/state/omarchy/qdot.omasky"
  readonly property string cachePath: root.cacheDir + "/shards.json"

  function loadCache(raw) {
    if (root.cacheDecided) return
    root.cacheDecided = true
    var parsed = Guards.parseCacheEnvelope(raw, root.laDateKey())
    if (parsed && parsed.tooLarge === true) {
      root.shardError = "Shard cache too large — refetching"
      root.quarantineCache(cacheWriteProc, root.cachePath)
      root.fetchShards(true)
      return
    }
    if (parsed && parsed.payload) {
      var clean = Guards.sanitizeShardPayload(parsed.payload)
      if (clean) {
        root.cachedLaDate = parsed.date
        root.cachedPayload = clean
        root.shardCacheState = true
        root.settleSchedule(clean)
        return
      }
      // Corrupt but right-sized: quarantine so every open doesn't re-freeze.
      root.quarantineCache(cacheWriteProc, root.cachePath)
    }
    root.fetchShards()
  }

  property bool cacheDecided: false
  property bool shardCacheState: false
  property string cachedLaDate: ""
  property var cachedPayload: null
  property var pendingPayload: null

  function persistCache(payload) {
    root.pendingPayload = payload
    cacheSaveTimer.restart()
  }

  function flushCache() {
    if (root.pendingPayload === null) return
    if (cacheWriteProc.running === true) {
      cacheSaveTimer.restart()
      return
    }
    root.ensureDir()
    cacheWriteProc.command = [
      "python3", "-c",
      "import sys, json, os; p=sys.argv[1]; os.makedirs(os.path.dirname(p), exist_ok=True); open(p, 'w').write(json.dumps(json.loads(sys.argv[2])))",
      root.cachePath,
      JSON.stringify({ date: root.laDateKey(), payload: root.pendingPayload })
    ]
    cacheWriteProc.running = true
  }

  function ensureDir() {
    if (ensureDirsProc.running === true) return
    ensureDirsProc.running = true
  }

  // The season cache is intentionally separate from the shard cache (own
  // Process/timer/FileView): both fetches settle within milliseconds of each
  // other on fetchData(), and sharing one python-write Process would let the
  // second .command overwrite the first before it ran.
  readonly property string seasonCachePath: root.cacheDir + "/seasons.json"

  property bool seasonCacheDecided: false
  property bool seasonCacheState: false
  property string seasonCacheDate: ""
  property var seasonCachedPayload: null
  property var pendingSeasonPayload: null

  function loadSeasonCache(raw) {
    if (root.seasonCacheDecided) return
    root.seasonCacheDecided = true
    var parsed = Guards.parseCacheEnvelope(raw, root.laDateKey())
    if (parsed && parsed.tooLarge === true) {
      root.seasonError = "Season cache too large — refetching"
      root.quarantineCache(seasonCacheWriteProc, root.seasonCachePath)
      root.fetchSeasons(true)
      return
    }
    if (parsed && parsed.payload) {
      var clean = Guards.sanitizeSeasonPayload(parsed.payload)
      if (clean) {
        root.seasonCacheDate = parsed.date
        root.seasonCachedPayload = clean
        root.seasonCacheState = true
        root.settleSeasons(clean)
        return
      }
      root.quarantineCache(seasonCacheWriteProc, root.seasonCachePath)
    }
    root.fetchSeasons()
  }

  // Overwrite a poisoned cache with an empty envelope via the dedicated
  // writer proc so the next open can't re-freeze on the same bytes.
  // Each cache has its own writer proc — never share one, or a second
  // .command overwrites the first before it runs (see note below).
  function quarantineCache(writerProc, path) {
    if (!writerProc || writerProc.running === true) return
    root.ensureDir()
    writerProc.command = [
      "python3", "-c",
      "import sys, os; p=sys.argv[1]; os.makedirs(os.path.dirname(p), exist_ok=True); open(p, 'w').write('{\"date\":\"\",\"payload\":null}')",
      path
    ]
    writerProc.running = false
    writerProc.running = true
  }

  function persistSeasonCache(payload) {
    root.pendingSeasonPayload = payload
    seasonCacheSaveTimer.restart()
  }

  function flushSeasonCache() {
    if (root.pendingSeasonPayload === null) return
    if (seasonCacheWriteProc.running === true) {
      seasonCacheSaveTimer.restart()
      return
    }
    root.ensureDir()
    seasonCacheWriteProc.command = [
      "python3", "-c",
      "import sys, json, os; p=sys.argv[1]; os.makedirs(os.path.dirname(p), exist_ok=True); open(p, 'w').write(json.dumps(json.loads(sys.argv[2])))",
      root.seasonCachePath,
      JSON.stringify({ date: root.pendingSeasonPayload.today, payload: root.pendingSeasonPayload })
    ]
    seasonCacheWriteProc.running = true
  }

  // ---- Countdown/clock ticker ----------------------------------------------
  Timer {
    id: clockTimer
    interval: 1000
    repeat: true
    running: true
    onTriggered: root.nowMs = new Date().getTime()
  }

  // ---- Hung-process watchdogs (H5) -----------------------------------------
  // Python already has timeout=15, but QML never killed a stuck proc: DNS
  // stalls, loader hangs, etc. pinned *Loading=true forever and disabled the
  // retry timers (which require !loading). Each watchdog kills its proc once
  // and settles with the last-known-good cache so the panel never blanks.
  Timer {
    id: eventsTimeout
    interval: root.procTimeoutMs
    repeat: false
    onTriggered: {
      if (eventsProc.running === true) {
        eventsProc.running = false
        root.failEvents("sky_clock.py timed out")
      }
    }
  }

  Timer {
    id: shardTimeout
    interval: root.procTimeoutMs
    repeat: false
    onTriggered: {
      if (shardProc.running === true) {
        shardProc.running = false
        if (!root.shardError) root.shardError = "Shard fetch timed out"
        root.settleWithFallback(null)
      }
    }
  }

  Timer {
    id: seasonTimeout
    interval: root.procTimeoutMs
    repeat: false
    onTriggered: {
      if (seasonProc.running === true) {
        seasonProc.running = false
        root.failSeasons("Season fetch timed out")
        root.settleWithSeasonFallback(null)
      }
    }
  }

  // ---- Panel hosting. Same contract as the omarchy first-party bar plugins:
  //      open/close/opened on the widget root -> routed by Bar.findPanelWidget.
  readonly property bool opened: panelLoader.item ? panelLoader.item.opened === true : false


  // ---- Legacy widget migration ---------------------------------------------
  // qdot.omashard + qdot.omaevents were merged into this plugin. Omarchy never
  // runs plugin code at install time, so the shell.json swap happens here on
  // first load: the script is a no-op when no legacy entries exist, backs up
  // shell.json before rewriting, and prints {"swapped": true} when it changed
  // the layout (then we ask the shell to rescan).
  readonly property string shellJsonPath: {
    var xdg = Quickshell.env("XDG_CONFIG_HOME")
    return (xdg && String(xdg).trim() !== "" ? String(xdg).trim() : (home + "/.config")) + "/omarchy/shell.json"
  }
  property bool migrationAvailable: false
  readonly property string migrateScriptPath: pluginDir + "scripts/migrate_old_widgets.py"

  function migrateOldWidgets(applyConsent) {
    if (migrateProc.running === true) return
    if (applyConsent === true) {
      if (root.migrateBusy) return
      root.migrateBusy = true
    }
    migrateProc.workingDirectory = root.pluginDir
    if (applyConsent === true) {
      migrateProc.command = ["python3", root.migrateScriptPath, "--yes", root.shellJsonPath]
    } else {
      migrateProc.command = ["python3", root.migrateScriptPath, "--check", root.shellJsonPath]
    }
    migrateProc.running = true
  }

  function applyMigration() {
    // Never rescan mid-open: destroying the popup while KeyboardPanel holds
    // focus/suppress flags leaves the shell input-stuck (H6). The rescan is
    // deferred until the panel is closed (see migrateProc handler).
    if (migrateProc.running === true || root.migrateBusy) return
    root.migrateOldWidgets(true)
  }

  function requestRescan() {
    if (root.rescanPending) return
    if (rescanProc.running === true) return
    // Defer while the panel is open; flush on close instead.
    if (root.opened) {
      root.rescanPending = true
      return
    }
    rescanProc.running = true
  }

  Process {
    id: migrateProc
    command: []
    running: false
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var raw = String(text || "").trim()
        if (!raw) {
          root.migrateBusy = false
          return
        }
        try {
          var parsed = JSON.parse(raw)
          if (parsed) {
            if (parsed.migration_needed === true) {
              root.migrationAvailable = true
              root.notifyPanel()
            } else if (parsed.swapped === true) {
              root.migrationAvailable = false
              root.notifyPanel()
              root.requestRescan()
            } else if (parsed.migration_needed === false) {
              root.migrationAvailable = false
              root.notifyPanel()
            }
          }
        } catch (error) {
          // migration is best-effort; the widget works without it
        }
        root.migrateBusy = false
      }
    }
    onExited: root.migrateBusy = false
  }

  Process {
    id: rescanProc
    command: ["omarchy-shell", "shell", "rescanPlugins"]
    running: false
    onExited: root.rescanPending = false
  }

  function open() {
    // No fetchData() here on purpose: Panel.open() refreshes (debounced via
    // fetchData's min-gap + per-proc single-flight), so a previous double
    // batch of 6 python procs collapses to one. See H2.
    if (panelLoader.item) panelLoader.item.open()
  }

  function close() {
    if (panelLoader.item) panelLoader.item.close()
    // Flush a migration rescan that was deferred while the panel was open.
    if (root.rescanPending) {
      root.rescanPending = false
      if (rescanProc.running !== true) rescanProc.running = true
    }
  }

  function togglePanel() {
    if (panelLoader.item) panelLoader.item.toggle()
  }

  readonly property real openPanelIndicatorWidth: root.vertical ? root.iconSize : Math.max(Style.space(12), barTextLabel.implicitWidth + root.iconSize + Style.spaceReal(6))
  readonly property real openPanelIndicatorHeight: Math.max(Style.space(10), Math.round(Style.bar.iconSlot * 0.55))

  readonly property bool popoutSwitchClosing: panelLoader.item ? panelLoader.item.popoutSwitchClosing === true : false

  function closeForPopoutSwitch() {
    if (panelLoader.item) panelLoader.item.closeForPopoutSwitch()
  }

  function injectPanel() {
    var target = panelLoader.item
    if (!target) return
    if ("bar" in target) target.bar = root.bar
    if ("settings" in target) target.settings = root.settings
    if ("anchorItem" in target) target.anchorItem = button
    if ("hostWidget" in target) target.hostWidget = root
  }

  function cycleLabelMode() {
    var entry = { id: root.moduleName }
    for (var key in root.settings) if (key !== "id") entry[key] = root.settings[key]
    entry["format"] = root.nextLabelMode
    root.settings = entry
    if (root.bar && root.bar.shell && typeof root.bar.shell.updateEntryInline === "function")
      root.bar.shell.updateEntryInline(root.moduleName, entry)
  }

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  onBarChanged: injectPanel()
  onSettingsChanged: injectPanel()

  // Logo size suited to the bar: smaller of the bar height and a comfortable
  // body-text cap, so it never overruns a horizontal bar's slot.
  readonly property real iconSize: Math.round(
    Math.min(root.vertical ? (bar ? bar.barSize : 0) : 100, Style.font.body * 1.6)
  )

  Loader {
    id: panelLoader
    active: true
    source: Qt.resolvedUrl("Panel.qml")
    visible: false
    onLoaded: {
      root.injectPanel()
      Qt.callLater(root.injectPanel)
    }
  }

  IpcHandler {
    target: "qdot.omasky"

    function refresh(): void { root.fetchData(true) }
    function cycleFormat(): void { root.cycleLabelMode() }
    function switchTab(tab: int): void {
      if (panelLoader.item && panelLoader.item.setTab) panelLoader.item.setTab(tab)
    }
    function open(): void { root.open() }
    function close(): void { root.close() }
    function show(): void { root.open() }
    function hide(): void { root.close() }
    function toggle(): void { root.togglePanel() }
    function migrateLayout(): void { root.applyMigration() }
    function debug(): string { return root.debugReport() }
    function debugLayout(): string {
      if (panelLoader.item && panelLoader.item.debugLayout) return panelLoader.item.debugLayout()
      return "{}"
    }
  }

  function debugReport() {
    var n = root.nearest
    return JSON.stringify({
      display: root.displayText,
      format: root.labelMode,
      shardFormat: root.shardFormat,
      migrationAvailable: root.migrationAvailable,
      eventsLoading: root.eventsLoading,
      shardsLoading: root.shardsLoading,
      seasonsLoading: root.seasonsLoading,
      eventError: root.eventError,
      shardError: root.shardError,
      seasonError: root.seasonError,
      events: root.events.length,
      dailyReset: root.dailyReset !== null,
      showDailyReset: root.setting("showDailyReset", true) !== false,
      nearest: n ? { name: n.name, active: n.active } : null,
      todayShard: root.todayShard
        ? { color: root.todayShard.shardColor, map: root.todayShard.map, realm: root.todayShard.realm }
        : null,
      season: root.season
        ? { name: root.season.name, number: root.season.number, progress: root.season.progress, days_remaining: root.season.days_remaining }
        : null,
      nextSeason: root.nextSeason
        ? { name: root.nextSeason.name, number: root.nextSeason.number, days_until_start: root.nextSeason.days_until_start }
        : null,
      seasonToday: root.seasonToday,
      nowSkyLabel: root.nowSkyLabel,
      nowLocalLabel: root.nowLocalLabel,
      nowMs: root.nowMs
    })
  }

  // Off-screen twin of the bar label so the laid-out width can be measured
  // before the button's contents exist (an anchored child does not contribute
  // to implicit size).
  Text {
    id: measureText
    visible: false
    text: root.displayText
    textFormat: Text.PlainText
    font.family: bar ? bar.fontFamily : Style.font.family
    font.pixelSize: Style.font.body
  }

  WidgetButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: ""
    labelVisible: false
    hasVisualContent: true
    fixedWidth: root.vertical ? root.barSize : Math.ceil(root.iconSize + Style.spaceReal(6) + measureText.implicitWidth)
    fixedHeight: root.vertical ? root.barSize : -1
    horizontalMargin: 8.75
    verticalPadding: 8.75
    tooltipText: root.tooltipSummary

    onPressed: function(b) {
      if (b === Qt.RightButton) root.cycleLabelMode()
      else if (b === Qt.MiddleButton) root.fetchData(true)
      else root.togglePanel()
    }

    Row {
      visible: !root.vertical
      anchors.centerIn: parent
      spacing: Style.spaceReal(6)

      Image {
        id: barIcon
        anchors.verticalCenter: parent.verticalCenter
        source: Qt.resolvedUrl("assets/tgc-logo.png")
        width: root.iconSize
        height: root.iconSize
        fillMode: Image.PreserveAspectFit
        smooth: true
        mipmap: true
        sourceSize.width: Math.round(root.iconSize * Screen.devicePixelRatio)
        sourceSize.height: Math.round(root.iconSize * Screen.devicePixelRatio)
        opacity: (root.eventsLoading && root.shardsLoading) ? 0.6 : 1.0
      }

      Text {
        id: barTextLabel
        text: root.displayText
        textFormat: Text.PlainText
        color: root.liveForeground
        font.family: button.fontFamily
        font.pixelSize: button.fontSize
        renderType: Text.NativeRendering
        opacity: (root.nearest !== null || root.todayShard !== null) ? 1.0 : 0.6
      }
    }

    Column {
      visible: root.vertical
      anchors.centerIn: parent

      Image {
        source: Qt.resolvedUrl("assets/tgc-logo.png")
        width: root.iconSize
        height: root.iconSize
        fillMode: Image.PreserveAspectFit
        smooth: true
        mipmap: true
        sourceSize.width: Math.round(root.iconSize * Screen.devicePixelRatio)
        sourceSize.height: Math.round(root.iconSize * Screen.devicePixelRatio)
        opacity: (root.eventsLoading && root.shardsLoading) ? 0.6 : 1.0
      }

      Text {
        anchors.horizontalCenter: parent.horizontalCenter
        text: root.labelMode === "shard"
          ? (root.todayShard ? (root.todayShard.shardColor === "Red" ? "🔴" : "⚫") : "")
          : (root.nearest ? EventsModel.formatCountdown(
              (root.nearest.active ? root.nearest.endMs : root.nearest.startMs) - root.nowMs) : "")
        textFormat: Text.PlainText
        color: root.liveForeground
        font.pixelSize: Style.font.caption
      }
    }
  }

  // ---- Events fetch lifecycle ----------------------------------------------
  property string lastEventsStderr: ""

  Process {
    id: eventsProc
    command: ["python3", root.scriptPath, "--json", "3"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        eventsTimeout.stop()
        var raw = String(text || "").trim()
        if (!raw) {
          root.failEvents(root.lastEventsStderr ? root.lastEventsStderr : "Empty response from sky_clock.py")
          return
        }
        if (raw.length > Guards.MAX_RAW_BYTES) {
          root.failEvents("Event response too large")
          return
        }
        var payload = null
        try {
          payload = JSON.parse(raw)
        } catch (error) {
          root.failEvents("Malformed event response")
          return
        }
        var clean = Guards.sanitizeEventsPayload(payload)
        if (!clean) {
          root.failEvents("Malformed event response")
          return
        }
        root.settleEvents(clean)
      }
    }
    stderr: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var rawErr = String(text || "").trim()
        if (rawErr) {
          var match = rawErr.match(/Error:\s*(.*)/i)
          root.lastEventsStderr = match ? match[1] : rawErr
        } else {
          root.lastEventsStderr = ""
        }
      }
    }
    onExited: function(exitCode) {
      eventsTimeout.stop()
      if (exitCode !== 0 && root.events.length === 0) {
        root.eventError = root.lastEventsStderr ? root.lastEventsStderr : "sky_clock.py failed"
        root.eventsLoading = false
        root.notifyPanel()
        return
      }
      root.eventsLoading = false
    }
  }

  Timer {
    id: eventsRefreshTimer
    interval: root.fetchIntervalMs
    repeat: true
    running: true
    onTriggered: root.runEventsScript()
  }

  Timer {
    id: eventsRetryTimer
    interval: 30000
    repeat: true
    running: root.eventError !== "" && !root.eventsLoading
    onTriggered: root.runEventsScript()
  }

  // ---- Shards fetch lifecycle ----------------------------------------------
  property string lastShardStderr: ""

  Process {
    id: shardProc
    command: ["python3", root.shardScriptPath, root.todayDateKey()]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        shardTimeout.stop()
        var raw = String(text || "").trim()
        if (!raw) {
          if (!root.shardError) root.shardError = root.lastShardStderr ? root.lastShardStderr : "Empty response from shard details script"
          root.settleWithFallback(null)
          return
        }
        if (raw.length > Guards.MAX_RAW_BYTES) {
          root.shardError = "Shard response too large"
          root.settleWithFallback(null)
          return
        }
        var payload = null
        try {
          payload = JSON.parse(raw)
        } catch (error) {
          root.shardError = "Malformed shard details response"
          root.settleWithFallback(null)
          return
        }
        var clean = Guards.sanitizeShardPayload(payload)
        if (!clean) {
          root.shardError = "Malformed shard details response"
          root.settleWithFallback(null)
          return
        }
        root.shardError = ""
        root.cachedLaDate = root.laDateKey()
        root.cachedPayload = clean
        root.shardCacheState = true
        root.persistCache(clean)
        root.settleSchedule(clean)
      }
    }
    stderr: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var rawErr = String(text || "").trim()
        if (rawErr) {
          var match = rawErr.match(/Error:\s*(.*)/i)
          root.lastShardStderr = match ? match[1] : rawErr
        } else {
          root.lastShardStderr = ""
        }
      }
    }
    onExited: function(exitCode) {
      shardTimeout.stop()
      if (exitCode !== 0) {
        if (!root.shardError) {
          root.shardError = root.lastShardStderr ? root.lastShardStderr : "Shard details script failed"
        }
        root.settleWithFallback(null)
      }
    }
  }

  // ---- Season fetch lifecycle ----------------------------------------------
  property string lastSeasonStderr: ""

  Process {
    id: seasonProc
    command: ["python3", root.seasonScriptPath]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        seasonTimeout.stop()
        var raw = String(text || "").trim()
        if (!raw) {
          root.failSeasons(root.lastSeasonStderr ? root.lastSeasonStderr : "Empty response from season script")
          root.settleWithSeasonFallback(null)
          return
        }
        if (raw.length > Guards.MAX_RAW_BYTES) {
          root.failSeasons("Season response too large")
          root.settleWithSeasonFallback(null)
          return
        }
        var payload = null
        try {
          payload = JSON.parse(raw)
        } catch (error) {
          root.failSeasons("Malformed season response")
          root.settleWithSeasonFallback(null)
          return
        }
        var clean = Guards.sanitizeSeasonPayload(payload)
        if (!clean) {
          root.failSeasons("Malformed season response")
          root.settleWithSeasonFallback(null)
          return
        }
        root.seasonError = ""
        root.seasonCacheDate = clean.today
        root.seasonCachedPayload = clean
        root.seasonCacheState = true
        root.persistSeasonCache(clean)
        root.settleSeasons(clean)
      }
    }
    stderr: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var rawErr = String(text || "").trim()
        if (rawErr) {
          var match = rawErr.match(/Error:\s*(.*)/i)
          root.lastSeasonStderr = match ? match[1] : rawErr
        } else {
          root.lastSeasonStderr = ""
        }
      }
    }
    onExited: function(exitCode) {
      seasonTimeout.stop()
      if (exitCode !== 0) {
        if (!root.seasonError) {
          root.seasonError = root.lastSeasonStderr ? root.lastSeasonStderr : "Season script failed"
        }
        root.settleWithSeasonFallback(null)
      } else {
        root.seasonsLoading = false
      }
    }
  }

  Process {
    id: ensureDirsProc
    command: ["mkdir", "-p", root.cacheDir]
    running: false
  }

  Process {
    id: cacheWriteProc
    command: []
    running: false
  }

  Process {
    id: seasonCacheWriteProc
    command: []
    running: false
  }

  FileView {
    id: cacheFile
    path: root.cachePath
    watchChanges: false
    atomicWrites: true
    printErrors: false
    onLoaded: root.loadCache(text())
    onLoadFailed: root.loadCache("")
  }

  FileView {
    id: seasonCacheFile
    path: root.seasonCachePath
    watchChanges: false
    atomicWrites: true
    printErrors: false
    onLoaded: root.loadSeasonCache(text())
    onLoadFailed: root.loadSeasonCache("")
  }

  Timer {
    id: cacheSaveTimer
    interval: 200
    repeat: false
    onTriggered: root.flushCache()
  }

  Timer {
    id: seasonCacheSaveTimer
    interval: 200
    repeat: false
    onTriggered: root.flushSeasonCache()
  }

  Timer {
    id: shardsRefreshTimer
    interval: root.shardFetchIntervalMs
    repeat: true
    running: root.cacheDecided
    onTriggered: root.fetchShards()
  }

  Timer {
    id: seasonRefreshTimer
    interval: root.seasonFetchIntervalMs
    repeat: true
    running: root.seasonCacheDecided
    onTriggered: root.fetchSeasons()
  }

  // When the script fails, retry every minute until it answers; the moment a
  // fetch succeeds the error clears and this stops. Retries force a live
  // fetch so a stale-but-valid cache doesn't swallow the retry.
  Timer {
    id: shardsRetryTimer
    interval: 60000
    repeat: true
    running: root.shardError !== "" && !root.shardsLoading
    onTriggered: root.fetchShards(true)
  }

  Timer {
    id: seasonRetryTimer
    interval: 60000
    repeat: true
    running: root.seasonError !== "" && !root.seasonsLoading
    onTriggered: root.fetchSeasons(true)
  }

  // Roll over at midnight: label and panel should follow the calendar date
  // even if a fetch is slow.
  SystemClock {
    id: clock
    precision: SystemClock.Hours
    onDateChanged: {
      root.fetchShards()
      root.fetchSeasons()
    }
  }

  Component.onCompleted: {
    root.ensureDir()
    cacheFile.reload()
    seasonCacheFile.reload()
    root.runEventsScript()
    root.migrateOldWidgets(false)
    root.notifyPanel()
  }

  // ---- Tooltip --------------------------------------------------------------
  function tooltipText() {
    var lines = []
    lines.push("OmaSky — Sky events & shards")
    lines.push("")
    if (root.todayShard) {
      lines.push(root.todayShard.shardColor + " shard · " + root.todayShard.map + " (" + root.todayShard.realm + ")")
      if (root.todayShard.rewardAc) lines.push("  " + String(root.todayShard.rewardAc) + " AC")
    } else if (!root.shardsLoading) {
      lines.push("No shard lands today")
    }
    if (root.events.length === 0) {
      if (root.eventsLoading) lines.push("Events loading…")
    } else {
      var capped = Guards.capArray(root.events, Guards.MAX_EVENTS)
      for (var i = 0; i < capped.length; i++) {
        var ev = capped[i]
        var occ = EventsModel.nextOccurrence(ev)
        if (!occ) continue
        lines.push(
          ev.name + " · " + occ.start_local_label
          + (ev.is_active ? " · ACTIVE" : "")
        )
      }
      if (root.dailyReset && root.setting("showDailyReset", true) !== false) {
        lines.push(
          "Daily Reset · " + root.dailyReset.start_local_label
          + " (" + root.dailyReset.day_offset + "d)"
        )
      }
    }
    if (root.eventError) lines.push("EVENTS OFFLINE: " + root.eventError)
    if (root.shardError) lines.push("SHARDS OFFLINE: " + root.shardError)
    return lines.join("\n")
  }
}