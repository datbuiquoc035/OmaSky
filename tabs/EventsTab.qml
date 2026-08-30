import QtQuick
import qs.Commons
import qs.Ui
import "."
import "../EventsModel.js" as EventsModel

// The OmaSky "Events" tab: current Sky/local clocks (local time is the
// primary, live read), the next event with a big countdown, every daily event
// with its next local & Sky times plus live countdowns, and the daily reset.
// A self-contained Flickable exposing its implicit content height so the
// hosting panel can size itself to whatever tab is active. All data comes in
// plain, ready-to-render properties from Panel.qml; time strings marked
// "local" are always the system timezone.
Flickable {
  id: root

  property var events: []
  property var dailyReset: null
  property double nowMs: 0
  property string nowSkyLabel: ""
  property string nowLocalLabel: ""
  property bool showDailyReset: true
  property string fetchError: ""
  property bool loading: true

  property color contentForeground: Color.foreground
  property color accentColor: Color.accent
  property string contentFontFamily: Style.font.family

  // When the standalone OmaEvents plugin is not installed, the tab shows an
  // install prompt instead of the live schedule.
  property bool installed: true
  property string githubUrl: ""
  property string missingMessage: "Install the OmaEvents plugin to enable this tab's live event schedule, clocks, and countdowns."

  implicitHeight: root.installed ? contentColumn.implicitHeight : missing.implicitHeight
  contentWidth: width
  contentHeight: root.installed ? contentColumn.implicitHeight : missing.implicitHeight
  clip: true
  boundsBehavior: Flickable.StopAtBounds
  interactive: contentHeight > height || contentWidth > width

  readonly property color dimColor: Qt.darker(root.contentForeground, 1.4)
  readonly property color faintColor: Qt.darker(root.contentForeground, 1.75)

  NotInstalled {
    id: missing
    visible: !root.installed
    width: parent.width
    pluginName: "OmaEvents"
    message: root.missingMessage
    githubUrl: root.githubUrl
    contentForeground: root.contentForeground
    accentColor: root.accentColor
    contentFontFamily: root.contentFontFamily
  }

  Column {
    id: contentColumn
    visible: root.installed
    width: parent ? parent.width : 0
    spacing: Style.space(10)

    // ---- Clocks: local is the primary, live read --------------------------
    Rectangle {
      width: parent.width
      height: clocksRow.implicitHeight + Style.space(14)
      radius: Style.cornerRadius
      color: Qt.rgba(root.contentForeground.r, root.contentForeground.g, root.contentForeground.b, 0.05)

      Row {
        id: clocksRow
        anchors.centerIn: parent
        spacing: Style.space(22)

        Column {
          spacing: Style.space(1)

          Text {
            anchors.horizontalCenter: parent.horizontalCenter
            text: "LOCAL"
            color: root.faintColor
            font.family: root.contentFontFamily
            font.pixelSize: Style.font.caption
            font.letterSpacing: 2
            font.bold: true
          }

          Text {
            anchors.horizontalCenter: parent.horizontalCenter
            text: EventsModel.localTime(root.nowMs)
            color: root.accentColor
            font.family: root.contentFontFamily
            font.pixelSize: Style.font.display
            font.bold: true
          }
        }

        Column {
          spacing: Style.space(1)

          Text {
            anchors.horizontalCenter: parent.horizontalCenter
            text: "SKY (PT)"
            color: root.faintColor
            font.family: root.contentFontFamily
            font.pixelSize: Style.font.caption
            font.letterSpacing: 2
            font.bold: true
          }

          Text {
            anchors.horizontalCenter: parent.horizontalCenter
            text: root.nowSkyLabel ? root.nowSkyLabel : "--:--"
            color: root.dimColor
            font.family: root.contentFontFamily
            font.pixelSize: Style.font.display
          }
        }
      }
    }

    // ---- Next up hero ------------------------------------------------------
    Text {
      text: "NEXT UP"
      visible: root.nearest !== null
      color: root.faintColor
      font.family: root.contentFontFamily
      font.pixelSize: Style.font.bodySmall
      font.letterSpacing: 1
      font.bold: true
    }

    Rectangle {
      id: nextCard
      visible: root.nearest !== null
      width: parent.width
      height: nextContent.implicitHeight + Style.space(16)
      radius: Style.cornerRadius
      color: Qt.rgba(root.accentColor.r, root.accentColor.g, root.accentColor.b, 0.14)
      border.width: Style.spacing.hairline
      border.color: root.nearest && root.nearest.active
        ? root.accentColor
        : Qt.rgba(root.accentColor.r, root.accentColor.g, root.accentColor.b, 0.4)

      Column {
        id: nextContent
        anchors.left: parent.left
        anchors.leftMargin: Style.space(14)
        anchors.right: parent.right
        anchors.rightMargin: Style.space(14)
        anchors.verticalCenter: parent.verticalCenter
        spacing: Style.space(2)

        Item {
          width: parent.width
          height: Math.max(nextName.implicitHeight, nextCountdown.implicitHeight)

          Text {
            id: nextName
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
            text: root.nearest ? root.nearest.name : ""
            color: root.contentForeground
            font.family: root.contentFontFamily
            font.pixelSize: Style.font.body
            font.bold: true
          }

          Text {
            id: nextCountdown
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            text: root.nearest
              ? (root.nearest.active
                ? "ACTIVE — " + root.countdown(root.nearest.endMs - root.nowMs) + " left"
                : "in " + root.countdown(root.nearest.startMs - root.nowMs))
              : ""
            color: root.nearest && root.nearest.active
              ? root.accentColor
              : root.dimColor
            font.family: root.contentFontFamily
            font.pixelSize: Style.font.body
            font.bold: root.nearest ? root.nearest.active : false
          }
        }

        Item {
          width: parent.width
          height: Math.max(nextDay.implicitHeight, nextTime.implicitHeight)

          Text {
            id: nextDay
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
            text: root.nearest
              ? EventsModel.dayQualifier(root.nearest.startMs, root.nowMs).toUpperCase()
              : ""
            color: root.faintColor
            font.family: root.contentFontFamily
            font.pixelSize: Style.font.caption
            font.letterSpacing: 1
            font.bold: true
          }

          Text {
            id: nextTime
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            text: root.nearest
              ? EventsModel.localShort(root.nearest.startMs) + " (local)"
              : ""
            color: root.dimColor
            font.family: root.contentFontFamily
            font.pixelSize: Style.font.bodySmall
          }
        }
      }
    }

    // ---- Daily events -------------------------------------------------------
    Text {
      text: "DAILY EVENTS"
      color: root.faintColor
      font.family: root.contentFontFamily
      font.pixelSize: Style.font.bodySmall
      font.letterSpacing: 1
      font.bold: true
    }

    Column {
      width: parent.width
      spacing: Style.space(6)

      Repeater {
        model: root.events

        Rectangle {
          required property var modelData
          readonly property var ev: modelData
          readonly property var occ: EventsModel.nextOccurrence(ev)
          readonly property bool active: ev && occ ? EventsModel.isActive(occ, root.nowMs) : false

          width: parent ? parent.width : 0
          height: evContent.implicitHeight + Style.space(12)
          radius: Style.cornerRadius
          color: active
            ? Qt.rgba(root.accentColor.r, root.accentColor.g, root.accentColor.b, 0.12)
            : Qt.rgba(root.contentForeground.r, root.contentForeground.g, root.contentForeground.b, 0.05)

          Column {
            id: evContent
            anchors.left: parent.left
            anchors.leftMargin: Style.space(12)
            anchors.right: parent.right
            anchors.rightMargin: Style.space(12)
            anchors.verticalCenter: parent.verticalCenter
            spacing: Style.space(2)

            Item {
              width: parent.width
              height: Math.max(evName.implicitHeight, evOcc.implicitHeight)

              Text {
                id: evName
                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter
                text: (active ? "🔥 " : "") + (ev ? ev.name : "")
                color: root.contentForeground
                font.family: root.contentFontFamily
                font.pixelSize: Style.font.body
                font.bold: active
              }

              Text {
                id: evOcc
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                text: occ
                  ? occ.start_local_label + " (local) · " + occ.start_sky_label + " (PT)"
                  : ""
                color: root.dimColor
                font.family: root.contentFontFamily
                font.pixelSize: Style.font.caption
              }
            }

            Item {
              width: parent.width
              height: Math.max(evStatus.implicitHeight, evLater.implicitHeight)

              Text {
                id: evStatus
                anchors.left: parent.left
                anchors.leftMargin: Style.space(14)
                anchors.verticalCenter: parent.verticalCenter
                text: occ
                  ? (active
                    ? "ENDS " + EventsModel.localShort(occ.end_epoch_ms) + " · " + root.countdown(occ.end_epoch_ms - root.nowMs) + " left"
                    : "in " + root.countdown(occ.start_epoch_ms - root.nowMs))
                  : ""
                color: active ? root.accentColor : root.faintColor
                font.family: root.contentFontFamily
                font.pixelSize: Style.font.caption
              }

              Text {
                id: evLater
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                visible: root.laterTimes(ev) !== ""
                text: "then " + root.laterTimes(ev)
                color: root.faintColor
                font.family: root.contentFontFamily
                font.pixelSize: Style.font.caption
              }
            }
          }
        }
      }
    }

    // ---- Daily reset ---------------------------------------------------------
    Rectangle {
      visible: root.showDailyReset && root.dailyReset !== null
      width: parent.width
      height: resetContent.implicitHeight + Style.space(12)
      radius: Style.cornerRadius
      color: Qt.rgba(root.contentForeground.r, root.contentForeground.g, root.contentForeground.b, 0.04)

      Column {
        id: resetContent
        anchors.left: parent.left
        anchors.leftMargin: Style.space(12)
        anchors.right: parent.right
        anchors.rightMargin: Style.space(12)
        anchors.verticalCenter: parent.verticalCenter
        spacing: Style.space(2)

        Item {
          width: parent.width
          height: Math.max(resetName.implicitHeight, resetCount.implicitHeight)

          Text {
            id: resetName
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
            text: "➺ Daily Reset"
            color: root.contentForeground
            font.family: root.contentFontFamily
            font.pixelSize: Style.font.body
            font.bold: true
          }

          Text {
            id: resetCount
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            text: root.dailyReset ? "in " + root.resetCountdown() : ""
            color: root.dimColor
            font.family: root.contentFontFamily
            font.pixelSize: Style.font.caption
          }
        }

        Item {
          width: parent.width
          height: resetWhen.implicitHeight

          Text {
            id: resetWhen
            anchors.left: parent.left
            anchors.leftMargin: Style.space(14)
            text: root.dailyReset
              ? root.resetDayLabel() + " · " + root.dailyReset.start_local_label + " (local) · " + root.dailyReset.start_sky_label + " (PT)"
              : ""
            color: root.faintColor
            font.family: root.contentFontFamily
            font.pixelSize: Style.font.caption
          }
        }
      }
    }

    // ---- Footer -------------------------------------------------------------
    Text {
      visible: root.fetchError !== "" && root.events.length === 0
      text: "OFFLINE — " + root.fetchError.toUpperCase()
      color: root.accentColor
      font.family: root.contentFontFamily
      font.pixelSize: Style.font.caption
      font.bold: true
      wrapMode: Text.WordWrap
      width: parent.width
    }

    Text {
      visible: !root.loading && root.events.length === 0
      text: "No event data"
      color: root.faintColor
      font.family: root.contentFontFamily
      font.pixelSize: Style.font.body
    }
  }

  // ---- Helpers -----------------------------------------------------------
  function nearestNow() {
    return EventsModel.nearestNow(
      root.events,
      root.showDailyReset ? root.dailyReset : null,
      root.nowMs
    )
  }

  readonly property var nearest: root.nearestNow()

  function countdown(ms) {
    return EventsModel.formatCountdown(ms, true)
  }

  function laterTimes(ev) {
    if (!ev || !ev.occurrences || ev.occurrences.length < 2) return ""
    var labels = []
    for (var i = 1; i < ev.occurrences.length; i++) {
      labels.push(ev.occurrences[i].start_local_label)
    }
    return labels.join(" · ")
  }

  function resetCountdown() {
    if (!root.dailyReset) return ""
    return EventsModel.formatCountdown(root.dailyReset.start_epoch_ms - root.nowMs, true)
  }

  function resetDayLabel() {
    if (!root.dailyReset) return ""
    return root.dailyReset.day_offset >= 1 ? "TOMORROW" : "TODAY"
  }
}