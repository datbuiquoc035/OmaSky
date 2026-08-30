// Pure shard schedule math for the Sky Shards widget. Ported from the
// sky-shards website (sky-shards.pages.dev) client-side schedule logic.
// All functions here are Qt- and IO-free so they can be reasoned about
// independently; the QML owns fetching and display formatting.

// America/Los_Angeles rules (no tz database in pure JS): DST starts the
// second Sunday in March at 2:00 and ends the first Sunday in November
// at 2:00. Offset is UTC-7 during DST and UTC-8 otherwise.
function laOffsetMinutes(year, month, day, hour, minute) {
  var dstStart = secondSundayUtc(year, 2, 2, 0)
  var dstEnd = firstSundayUtc(year, 10, 2, 0)
  var time = Date.UTC(year, month, day, hour, minute)
  return time >= dstStart && time < dstEnd ? -7 * 60 : -8 * 60
}

function daysFromMonthStart(year, month, firstDay) {
  var first = new Date(Date.UTC(year, month, 1))
  var dow = first.getUTCDay()
  return firstDay + ((7 - dow) % 7) - 1
}

function secondSundayUtc(year, month, hour, minute) {
  var monthStart = new Date(Date.UTC(year, month, 1))
  var dow = monthStart.getUTCDay()
  var day = 8 + ((7 - dow) % 7)
  return Date.UTC(year, month, day, hour, minute)
}

function firstSundayUtc(year, month, hour, minute) {
  var monthStart = new Date(Date.UTC(year, month, 1))
  var dow = monthStart.getUTCDay()
  var day = 1 + ((7 - dow) % 7)
  return Date.UTC(year, month, day, hour, minute)
}

// Convert LA wall-clock components to a UTC Date (epoch ms).
function laWallToUtc(year, month, day, hour, minute) {
  var offset = laOffsetMinutes(year, month, day, hour, minute)
  return Date.UTC(year, month, day, hour, minute) - offset * 60000
}

// Realms in rotation order (0..4). The realm for a given day-of-month is
// (dayOfMonth - 1) % 5.
var REALMS = [
  "Daylight Prairie",
  "Hidden Forest",
  "Valley of Triumph",
  "Golden Wasteland",
  "Vault of Knowledge",
]
var REALM_KEYS = ["prairie", "forest", "valley", "wasteland", "vault"]

var REALM_MAP_NAMES = {
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

// Maps per schedule group (one per realm index 0..4). Group is derived
// from day-of-month, keyed by group index 0..4.
var GROUP_MAPS = {
  0: ["prairie.butterfly", "forest.brook", "valley.rink", "wasteland.temple", "vault.starlight"],
  1: ["prairie.village", "forest.boneyard", "valley.rink", "wasteland.battlefield", "vault.starlight"],
  2: ["prairie.cave", "forest.end", "valley.dreams", "wasteland.graveyard", "vault.jelly"],
  3: ["prairie.bird", "forest.tree", "valley.dreams", "wasteland.crab", "vault.jelly"],
  4: ["prairie.island", "forest.sunny", "valley.hermit", "wasteland.ark", "vault.jelly"],
}

// Schedule templates, keyed by group index (from the site's `tl`).
// noShardDays: ISO weekday numbers (1=Mon .. 7=Sun) with no shard eruption.
// intervalH and offsetMin are in LA-local wall-clock time.
var SCHEDULE_TEMPLATES = [
  { noShardDays: [6, 7], intervalH: 8, offsetMin: 1 * 60 + 50, defaultRewardAc: null },
  { noShardDays: [7, 1], intervalH: 8, offsetMin: 2 * 60 + 10, defaultRewardAc: null },
  { noShardDays: [1, 2], intervalH: 6, offsetMin: 7 * 60 + 40, defaultRewardAc: 2 },
  { noShardDays: [2, 3], intervalH: 6, offsetMin: 2 * 60 + 20, defaultRewardAc: 2.5 },
  { noShardDays: [3, 4], intervalH: 6, offsetMin: 3 * 60 + 30, defaultRewardAc: 3.5 },
]

// land = start + 8min40s ; end = start + 4h
var LAND_DELTA_MINUTES = 8 + 40 / 60
var END_DELTA_HOURS = 4

// Base shard AC rewards per map
var BASE_REWARDS = {
  "prairie.butterfly": 3, "prairie.village": 3, "prairie.bird": 2, "prairie.island": 3,
  "forest.brook": 2, "forest.end": 2, "forest.tree": 3, "forest.sunny": 1,
  "valley.rink": 3, "valley.dreams": 2, "valley.hermit": 1,
  "wasteland.temple": 3, "wasteland.battlefield": 3, "wasteland.graveyard": 2,
  "wasteland.crab": 2, "wasteland.ark": 4,
  "vault.starlight": 3, "vault.jelly": 2,
}

// Red shard extra AC (per map)
var RED_REWARDS = {
  "forest.end": 2.5, "valley.dreams": 2.5, "forest.tree": 3.5, "vault.jelly": 3.5,
}

// Shard variant count per map
var VARIANTS = {
  "prairie.butterfly": 3, "prairie.village": 3, "prairie.bird": 2, "prairie.island": 3,
  "forest.brook": 2, "forest.end": 2, "forest.tree": 3, "forest.sunny": 1,
  "valley.rink": 3, "valley.dreams": 2, "valley.hermit": 1,
  "wasteland.temple": 3, "wasteland.battlefield": 3, "wasteland.graveyard": 2,
  "wasteland.crab": 2, "wasteland.ark": 4,
  "vault.starlight": 3, "vault.jelly": 2,
}

// ---- Day-of-month math. Mirrors the site's JS: `l = day%2===1 ?
//       ((day-1)/2%3)+2 : (day/2)%2`, `o = (day-1)%5`, `a = day%2===1`.
function groupIndexForDay(day) {
  return day % 2 === 1 ? (((day - 1) / 2) % 3) + 2 : (day / 2) % 2
}

function realmIndexForDay(day) {
  return (day - 1) % 5
}

function isRedDay(day) {
  return day % 2 === 1
}

// Compute occurrence times for a target date. Returns an array of
// { start, land, end } UTC Date objects, three eruptions per shard day.
function computeOccurrences(target, group) {
  var tmpl = SCHEDULE_TEMPLATES[group]
  var intervalH = tmpl.intervalH
  var offsetMin = tmpl.offsetMin

  var year = target.getUTCFullYear()
  var month = target.getUTCMonth()
  var day = target.getUTCDate()
  var isoWeekday = target.getUTCDay()
  if (isoWeekday === 0) isoWeekday = 7

  // First start = LA midnight of the target date + offset.
  var firstStart = laWallToUtc(year, month, day, 0, 0) + offsetMin * 60000

  // Sunday DST correction (the site's `n.isInDST !== x.isInDST`): when the
  // midnight DST state differs from the offset time's state, fold the
  // difference hour in so the first start lands on the right wall clock.
  var midnightOffset = laOffsetMinutes(year, month, day, 0, 0)
  var firstOffset = laOffsetMinutes(year, month, day, 0, offsetMin)
  if (midnightOffset === -7 && firstOffset === -8) {
    firstStart += 3600000
  }

  var occurrences = []
  for (var i = 0; i < 3; i++) {
    var start = new Date(firstStart + (intervalH * 3600000) * i)
    var land = new Date(start.getTime() + Math.round(LAND_DELTA_MINUTES * 60000))
    var end = new Date(start.getTime() + Math.round(END_DELTA_HOURS * 3600000))
    occurrences.push({ start: start, land: land, end: end })
  }
  return occurrences
}

// Format a Date in the display timezone as "HH:MM". The display tz is
// given as a fixed UTC offset in hours (e.g. 0 for UTC, -5 for EST).
function formatTime(date, tzOffsetHours) {
  if (!date) return "--:--"
  var t = new Date(date.getTime() + (tzOffsetHours || 0) * 3600000)
  return pad2(t.getUTCHours()) + ":" + pad2(t.getUTCMinutes())
}

function pad2(value) {
  return (value < 10 ? "0" : "") + value
}

// yyyy-MM-dd stable identity for a Date ({ UTC date }).
function keyForDate(date) {
  return date.getUTCFullYear() + "-" + pad2(date.getUTCMonth() + 1) + "-" + pad2(date.getUTCDate())
}

// Compute the shard schedule for a single Date. Uses the date only (its
// time-of-day and timezone are ignored — the schedule is keyed to the
// calendar date). Returns null when there is no shard that day.
function computeScheduleForDate(target, dailiesMap) {
  var utcDate = new Date(Date.UTC(target.getFullYear(), target.getMonth(), target.getDate()))

  var day = utcDate.getUTCDate()
  var group = groupIndexForDay(day)
  var realmIdx = realmIndexForDay(day)
  var isRed = isRedDay(day)
  var tmpl = SCHEDULE_TEMPLATES[group]
  var isoWeekday = utcDate.getUTCDay()
  if (isoWeekday === 0) isoWeekday = 7

  var dateKey = keyForDate(utcDate)
  var dailyData = dailiesMap ? (dailiesMap[dateKey] || {}) : {}
  var override = dailyData.override

  var hasShard = tmpl.noShardDays.indexOf(isoWeekday) === -1
  if (override !== undefined && override !== null) {
    if (override.hasShard !== undefined) hasShard = override.hasShard
    if (override.realm !== undefined) realmIdx = override.realm
    if (override.isRed !== undefined) isRed = override.isRed
  }

  if (!hasShard) return null

  var realmKey = REALM_KEYS[realmIdx]
  var realmName = REALMS[realmIdx]
  var mapKey = GROUP_MAPS[group][realmIdx]
  var mapName = REALM_MAP_NAMES[mapKey] || mapKey

  var defaultReward = tmpl.defaultRewardAc
  var rewardAc
  if (isRed) {
    rewardAc = RED_REWARDS[mapKey] !== undefined ? RED_REWARDS[mapKey] : defaultReward
  } else {
    rewardAc = BASE_REWARDS[mapKey] !== undefined ? BASE_REWARDS[mapKey] : null
  }

  return {
    date: dateKey,
    isToday: false,
    realm: realmName,
    realmKey: realmKey,
    map: mapName,
    mapKey: mapKey,
    shardColor: isRed ? "Red" : "Black",
    isRed: isRed,
    rewardAc: rewardAc,
    variant: VARIANTS[mapKey] !== undefined ? VARIANTS[mapKey] : 1,
    occurrences: computeOccurrences(utcDate, group),
    group: group,
  }
}

// Schedules for the next `count` calendar days starting today, as an array
// (null entries mark no-shard days).
function computeDays(count, dailiesMap) {
  var now = new Date()
  var days = []
  for (var i = 0; i < count; i++) {
    var target = new Date(now.getFullYear(), now.getMonth(), now.getDate() + i)
    var info = computeScheduleForDate(target, dailiesMap)
    if (info) info.isToday = i === 0
    days.push(info)
  }
  return days
}

// The first shard at or after today (null when none in range).
function firstShard(days) {
  for (var i = 0; i < days.length; i++)
    if (days[i] !== null) return days[i]
  return null
}

// Short label for the era window. Reused by both the bar label and panel.
function labelFor(shard, tzOffsetHours) {
  if (!shard) return "No shards today"
  return shard.map + " · " + shard.realm
}

if (typeof module !== "undefined") {
  module.exports = {
    REALMS: REALMS,
    REALM_KEYS: REALM_KEYS,
    REALM_MAP_NAMES: REALM_MAP_NAMES,
    GROUP_MAPS: GROUP_MAPS,
    SCHEDULE_TEMPLATES: SCHEDULE_TEMPLATES,
    BASE_REWARDS: BASE_REWARDS,
    RED_REWARDS: RED_REWARDS,
    VARIANTS: VARIANTS,
    laOffsetMinutes: laOffsetMinutes,
    secondSundayUtc: secondSundayUtc,
    firstSundayUtc: firstSundayUtc,
    groupIndexForDay: groupIndexForDay,
    realmIndexForDay: realmIndexForDay,
    isRedDay: isRedDay,
    computeOccurrences: computeOccurrences,
    computeScheduleForDate: computeScheduleForDate,
    computeDays: computeDays,
    firstShard: firstShard,
    labelFor: labelFor,
    formatTime: formatTime,
    keyForDate: keyForDate,
  }
}