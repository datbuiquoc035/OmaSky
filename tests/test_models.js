const assert = require("assert");
const EventsModel = require("../EventsModel.js");
const ShardModel = require("../ShardModel.js");
const Subtitles = require("../Subtitles.js");

// Test Subtitles
assert(Array.isArray(Subtitles.SUBTITLES));
assert(Subtitles.SUBTITLES.length > 0);
const sub = Subtitles.getRandomSubtitle();
assert(typeof sub === "string" && sub.length > 0);
console.log("PASS test_subtitles");

// Test EventsModel
const testDate = new Date(2026, 8, 8, 14, 5, 30);
assert.strictEqual(EventsModel.localTime(testDate.getTime()), "14:05:30");
assert.strictEqual(EventsModel.localShort(testDate.getTime()), "14:05");
assert.strictEqual(EventsModel.formatCountdown(65000), "1m");
assert.strictEqual(EventsModel.formatCountdown(65000, true), "1m 05s");
assert.strictEqual(EventsModel.formatCountdown(3665000), "1h 1m");
assert.strictEqual(EventsModel.formatCountdown(45000), "45s");

const sampleOcc = {
  start_epoch_ms: 1000,
  end_epoch_ms: 2000,
};
assert.strictEqual(EventsModel.isActive(sampleOcc, 999), false);
assert.strictEqual(EventsModel.isActive(sampleOcc, 1000), true);
assert.strictEqual(EventsModel.isActive(sampleOcc, 1500), true);
assert.strictEqual(EventsModel.isActive(sampleOcc, 2000), false);

const sampleEvent = {
  name: "Polluted Geyser",
  key: "geyser",
  occurrences: [sampleOcc],
};
assert.strictEqual(EventsModel.nextOccurrence(sampleEvent), sampleOcc);
assert.strictEqual(EventsModel.nextOccurrence(null), null);

const nearestActive = EventsModel.nearestNow([sampleEvent], null, 1500);
assert.strictEqual(nearestActive.name, "Polluted Geyser");
assert.strictEqual(nearestActive.active, true);

const nearestUpcoming = EventsModel.nearestNow([sampleEvent], null, 500);
assert.strictEqual(nearestUpcoming.name, "Polluted Geyser");
assert.strictEqual(nearestUpcoming.active, false);

console.log("PASS test_events_model");

// Test ShardModel groupIndexForDay and realmIndexForDay
assert.strictEqual(ShardModel.realmIndexForDay(1), 0);
assert.strictEqual(ShardModel.realmIndexForDay(6), 0);
assert.strictEqual(ShardModel.isRedDay(1), true);
assert.strictEqual(ShardModel.isRedDay(2), false);

// Test computeDays
const days = ShardModel.computeDays(7, {});
assert.strictEqual(days.length, 7);
const nonNullDay = days.find((d) => d !== null);
assert(nonNullDay !== undefined && nonNullDay.realm !== undefined);

// Test formatTime
const d = new Date(Date.UTC(2026, 7, 30, 12, 34));
assert.strictEqual(ShardModel.formatTime(d, 0), "12:34");
assert.strictEqual(ShardModel.formatTime(d, 2), "14:34");

console.log("PASS test_shard_model");
console.log("\nall JS model tests passed");
