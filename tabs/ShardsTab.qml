import QtQuick
import qs.Commons
import qs.Ui
import "."
import "../ShardModel.js" as ShardModel

// The OmaSky "Shards" tab: today's shard at a glance (color dot, realm, map,
// reward, variant), the eruption windows for the day, and the shard days
// coming up over the next few calendar days. A self-contained Flickable
// exposing its implicit content height so the hosting panel can size itself
// to whatever tab is active. All data arrives as plain properties from
// Panel.qml; times are rendered in the configured display timezone.
Flickable {
  id: root

  property var days: []
  property var todayShard: null
  property real displayTzOffset: 0
  property string tzLabel: "Local"
  property int upcomingCount: 3
  property string fetchError: ""
  property bool loading: true

  property color contentForeground: Color.foreground
  property color accentColor: Color.accent
  property string contentFontFamily: Style.font.family

  readonly property color redColor: root.accentColor
  readonly property color blackColor: root.contentForeground

  implicitHeight: contentColumn.implicitHeight
  contentWidth: width
  contentHeight: contentColumn.implicitHeight
  clip: true
  boundsBehavior: Flickable.StopAtBounds
  interactive: contentHeight > height || contentWidth > width

  function colorDot(color) {
    return color === "Red" ? "🔴" : "⚫"
  }

  function occurrenceSummary(occ) {
    if (!occ) return ""
    return ShardModel.formatTime(occ.start, root.displayTzOffset)
      + " → " + ShardModel.formatTime(occ.land, root.displayTzOffset)
      + " → " + ShardModel.formatTime(occ.end, root.displayTzOffset)
  }

  // Weekday label for a yyyy-MM-dd date key, or "TOMORROW" for the next day.
  function dayLabel(dateKey, isNext) {
    if (isNext) return "TOMORROW"
    var parts = String(dateKey).split("-")
    if (parts.length !== 3) return dateKey
    var d = new Date(Number(parts[0]), Number(parts[1]) - 1, Number(parts[2]))
    var names = ["SUN", "MON", "TUE", "WED", "THU", "FRI", "SAT"]
    return names[d.getDay()]
  }

  // Non-null shards after today, in order, capped at upcomingCount.
  // NOTE: callers must use `upcomingList`, not this function. Each call
  // returns a NEW array, so `model: upcomingShards()` rebuilt the Repeater
  // on every layout pass. The readonly property below memoizes per
  // (days, upcomingCount) change instead.
  function upcomingShards() {
    var out = []
    var cap = Math.max(1, Math.min(7, Number(root.upcomingCount) || 3))
    var days = Array.isArray(root.days) ? root.days : []
    for (var i = 1; i < days.length && i <= 7; i++) {
      if (!days[i]) continue
      out.push(days[i])
      if (out.length >= cap) break
    }
    return out
  }

  readonly property var upcomingList: upcomingShards()
  readonly property var nextShard: upcomingList.length > 0 ? upcomingList[0] : null

  Column {
    id: contentColumn
    width: parent ? parent.width : 0
    spacing: Style.space(8)

    // ---- Today's shard ------------------------------------------------------
    Text {
      text: root.fetchError && !root.todayShard ? "OFFLINE — " + root.fetchError.toUpperCase() : "TODAY'S SHARD"
      color: root.fetchError && !root.todayShard ? root.redColor : Qt.darker(root.contentForeground, 1.5)
      font.family: root.contentFontFamily
      font.pixelSize: Style.font.bodySmall
      font.letterSpacing: 1
      font.bold: true
    }

    Item {
      width: parent.width
      height: root.todayShard ? todayRow.implicitHeight : noShardRow.implicitHeight

      Row {
        id: todayRow
        visible: root.todayShard !== null
        width: parent.width
        spacing: Style.space(14)

        Text {
          anchors.verticalCenter: parent.verticalCenter
          text: root.todayShard ? root.colorDot(root.todayShard.shardColor) : ""
          font.pixelSize: Style.font.display
        }

        Column {
          anchors.verticalCenter: parent.verticalCenter
          spacing: Style.space(2)

          Text {
            text: root.todayShard ? root.todayShard.realm : ""
            color: root.contentForeground
            font.family: root.contentFontFamily
            font.pixelSize: Style.font.body
            font.bold: true
          }

          Text {
            text: root.todayShard
              ? (root.todayShard.map + (root.todayShard.rewardAc ? "  ·  " + String(root.todayShard.rewardAc) + " AC" : ""))
              : ""
            color: Qt.darker(root.contentForeground, 1.35)
            font.family: root.contentFontFamily
            font.pixelSize: Style.font.bodySmall
          }

          Text {
            text: root.todayShard
              ? (root.todayShard.shardColor + " shard" + (root.todayShard.variant > 1 ? " · " + root.todayShard.variant + " variants" : ""))
              : ""
            color: root.todayShard && root.todayShard.shardColor === "Red"
              ? root.redColor
              : (root.todayShard && root.todayShard.shardColor === "Black"
                ? Qt.darker(root.contentForeground, 1.6)
                : root.contentForeground)
            font.family: root.contentFontFamily
            font.pixelSize: Style.font.caption
            font.letterSpacing: 1
          }
        }
      }

      Row {
        id: noShardRow
        visible: root.todayShard === null
        width: parent.width
        spacing: Style.space(10)

        Text {
          anchors.verticalCenter: parent.verticalCenter
          text: "🌤"
          font.pixelSize: Style.font.body
        }

        Column {
          anchors.verticalCenter: parent.verticalCenter
          spacing: Style.space(2)

          Text {
            text: root.loading ? "Checking the skies…" : "No shard lands today"
            color: Qt.darker(root.contentForeground, 1.2)
            font.family: root.contentFontFamily
            font.pixelSize: Style.font.body
          }

          Text {
            text: root.fetchError ? root.fetchError : "The realms rest peacefully"
            visible: !root.loading
            color: Qt.darker(root.contentForeground, 1.6)
            font.family: root.contentFontFamily
            font.pixelSize: Style.font.caption
          }
        }
      }
    }

    // ---- Eruption windows ---------------------------------------------------
    Text {
      text: "ERUPTION TIMES · " + root.tzLabel.toUpperCase()
      color: Qt.darker(root.contentForeground, 1.5)
      font.family: root.contentFontFamily
      font.pixelSize: Style.font.bodySmall
      font.letterSpacing: 1
      font.bold: true
    }

    Column {
      id: timesColumn
      width: parent.width
      spacing: Style.space(6)
      visible: root.todayShard !== null && root.todayShard.occurrences && root.todayShard.occurrences.length > 0

      Repeater {
        // Capped to 3 without per-frame churn: slice() only allocates when
        // a poisoned payload actually exceeds the cap (H1). BarWidget
        // already sanitizes, this is defence-in-depth at the render site.
        model: root.todayShard && root.todayShard.occurrences
          ? (root.todayShard.occurrences.length > 3 ? root.todayShard.occurrences.slice(0, 3) : root.todayShard.occurrences)
          : []

        Rectangle {
          required property var modelData
          width: parent ? parent.width : 0
          height: Style.space(26)
          radius: Style.cornerRadius
          color: Qt.rgba(root.contentForeground.r, root.contentForeground.g, root.contentForeground.b, 0.06)

          Row {
            anchors.centerIn: parent
            spacing: Style.space(6)

            Text {
              text: root.occurrenceSummary(modelData)
              color: root.contentForeground
              font.family: root.contentFontFamily
              font.pixelSize: Style.font.bodySmall
            }
          }
        }
      }

      Text {
        text: "start → land → end"
        color: Qt.darker(root.contentForeground, 1.8)
        font.family: root.contentFontFamily
        font.pixelSize: Style.font.caption
        horizontalAlignment: Text.AlignHCenter
        anchors.horizontalCenter: parent.horizontalCenter
      }
    }

    // ---- Upcoming ------------------------------------------------------------
    Text {
      visible: upcomingList.length > 0
      text: "UPCOMING"
      color: Qt.darker(root.contentForeground, 1.5)
      font.family: root.contentFontFamily
      font.pixelSize: Style.font.bodySmall
      font.letterSpacing: 1
      font.bold: true
    }

    Column {
      width: parent.width
      spacing: Style.space(6)
      visible: upcomingList.length > 0

      Repeater {
        model: upcomingList

        Rectangle {
          required property var modelData
          width: parent ? parent.width : 0
          height: Style.space(30)
          radius: Style.cornerRadius
          color: Qt.rgba(root.contentForeground.r, root.contentForeground.g, root.contentForeground.b, 0.04)

          Row {
            anchors.left: parent.left
            anchors.leftMargin: Style.space(12)
            anchors.verticalCenter: parent.verticalCenter
            spacing: Style.space(10)

            Text {
              text: root.dayLabel(modelData.date, modelData === root.nextShard)
              width: Style.space(52)
              color: Qt.darker(root.contentForeground, 1.5)
              font.family: root.contentFontFamily
              font.pixelSize: Style.font.caption
              font.letterSpacing: 1
              font.bold: true
            }

            Text {
              text: root.colorDot(modelData.shardColor)
              color: root.contentForeground
              font.pixelSize: Style.font.bodySmall
            }

            Text {
              text: modelData.map + " — " + modelData.realm
              color: root.contentForeground
              font.family: root.contentFontFamily
              font.pixelSize: Style.font.bodySmall
            }

            Text {
              text: modelData.rewardAc ? String(modelData.rewardAc) + " AC" : ""
              color: Qt.darker(root.contentForeground, 1.6)
              font.family: root.contentFontFamily
              font.pixelSize: Style.font.caption
            }
          }
        }
      }
    }

    // ---- Footer ---------------------------------------------------------------
    Text {
      visible: root.fetchError !== "" && root.todayShard === null
      text: "Live data unavailable — showing computed schedule"
      color: Qt.darker(root.contentForeground, 1.8)
      font.family: root.contentFontFamily
      font.pixelSize: Style.font.caption
    }
  }
}