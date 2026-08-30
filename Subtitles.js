// Subtitle lines shown under the "Sky Shards" title in the panel.
// Edit this list freely — add, remove, or reorder lines as you like.
// One is picked at random each time the panel opens or the day changes.

var SUBTITLES = [
  "May your wings carry you far",
  "The clouds whisper secrets today",
  "Light awaits in the realms beyond",
  "Every shard tells a story",
  "INCOMINGGGGGG !!!!!!!",
  "That's La Peace, not La Shard !",
  "The sky remembers those who soar",
  "Gather your light, traveler",
  "The spirits sing among the stars",
  "Somewhere, a wind path calls",
  "Darkness falls, but dawn returns",
  "Chase the light where it lands"
]

function getRandomSubtitle() {
  var list = SUBTITLES.slice()
  if (list.length === 0) return ""
  return list[Math.floor(Math.random() * list.length)]
}

if (typeof module !== "undefined") {
  module.exports = {
    SUBTITLES: SUBTITLES,
    getRandomSubtitle: getRandomSubtitle,
  }
}