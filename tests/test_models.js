const assert = require("assert");
const ShardModel = require("../ShardModel.js");
const Subtitles = require("../Subtitles.js");

// Test Subtitles
assert(Array.isArray(Subtitles.SUBTITLES));
assert(Subtitles.SUBTITLES.length > 0);
const sub = Subtitles.getRandomSubtitle();
assert(typeof sub === "string" && sub.length > 0);
console.log("PASS test_subtitles");

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
