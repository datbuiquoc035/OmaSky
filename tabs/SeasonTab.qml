import QtQuick
import qs.Commons
import qs.Ui

// The OmaSky "Season" tab: tracks the current live Sky season (name, ordinal,
// calendar progress, days remaining) and upcoming season data from the
// skygame-data catalog. All date math is precomputed on Pacific calendar days
// by scripts/fetch_seasons.py.
Flickable {
  id: root

  property var season: null
  property var nextSeason: null
  property string seasonToday: ""
  property string fetchError: ""
  property bool loading: true

  property color contentForeground: Color.foreground
  property color accentColor: Color.accent
  property string contentFontFamily: Style.font.family

  implicitHeight: contentColumn.implicitHeight
  contentWidth: width
  contentHeight: contentColumn.implicitHeight
  clip: true
  boundsBehavior: Flickable.StopAtBounds
  interactive: contentHeight > height || contentWidth > width

  readonly property color dimColor: Qt.darker(root.contentForeground, 1.4)
  readonly property color faintColor: Qt.darker(root.contentForeground, 1.75)

  Column {
    id: contentColumn
    width: parent ? parent.width : 0
    spacing: Style.space(10)

    // ---- Current Season Header ----------------------------------------------
    Text {
      text: root.fetchError && !root.season
        ? "OFFLINE — " + root.fetchError.toUpperCase()
        : "CURRENT SEASON"
      color: root.fetchError && !root.season
        ? root.accentColor
        : root.faintColor
      font.family: root.contentFontFamily
      font.pixelSize: Style.font.bodySmall
      font.letterSpacing: 1
      font.bold: true
    }

    // ---- Active Season Hero Card --------------------------------------------
    Rectangle {
      id: seasonHeroCard
      visible: root.season !== null
      width: parent.width
      height: seasonHeroContent.implicitHeight + Style.space(16)
      radius: Style.cornerRadius
      color: Qt.rgba(root.accentColor.r, root.accentColor.g, root.accentColor.b, 0.12)
      border.width: Style.spacing.hairline
      border.color: Qt.rgba(root.accentColor.r, root.accentColor.g, root.accentColor.b, 0.4)

      Column {
        id: seasonHeroContent
        anchors.left: parent.left
        anchors.leftMargin: Style.space(14)
        anchors.right: parent.right
        anchors.rightMargin: Style.space(14)
        anchors.verticalCenter: parent.verticalCenter
        spacing: Style.space(8)

        // Season name
        Text {
          width: parent.width
          text: root.season ? root.season.name : ""
          color: root.contentForeground
          font.family: root.contentFontFamily
          font.pixelSize: Style.font.title
          font.bold: true
          elide: Text.ElideRight
        }

        // Season subtitle: Ordinal + Year
        Text {
          text: root.season
            ? "Season " + root.season.number + " · " + root.season.year
            : ""
          color: root.dimColor
          font.family: root.contentFontFamily
          font.pixelSize: Style.font.bodySmall
        }

        // Progress track + fill
        Item {
          id: progressTrack
          width: parent.width
          height: Style.space(8)

          Rectangle {
            anchors.fill: parent
            radius: height / 2
            color: Qt.rgba(root.contentForeground.r, root.contentForeground.g, root.contentForeground.b, 0.12)
          }

          Rectangle {
            id: progressFill
            height: parent.height
            radius: height / 2
            color: root.accentColor
            width: root.season
              ? Math.max(height, parent.width * Math.max(0, Math.min(1, root.season.progress || 0)))
              : 0
          }
        }

        // Days remaining + Days elapsed stats
        Item {
          width: parent.width
          height: Math.max(daysLeftText.implicitHeight, daysElapsedText.implicitHeight)

          Text {
            id: daysLeftText
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
            text: root.season
              ? (root.season.days_remaining === 0
                ? "LAST DAY"
                : (root.season.days_remaining === 1
                  ? "1 DAY LEFT"
                  : root.season.days_remaining + " DAYS LEFT"))
              : ""
            color: root.accentColor
            font.family: root.contentFontFamily
            font.pixelSize: Style.font.bodySmall
            font.letterSpacing: 1
            font.bold: true
          }

          Text {
            id: daysElapsedText
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            text: root.season
              ? root.season.days_elapsed + " / " + root.season.days_total + " days (" + Math.round((root.season.progress || 0) * 100) + "%)"
              : ""
            color: root.dimColor
            font.family: root.contentFontFamily
            font.pixelSize: Style.font.caption
          }
        }

        // Date range
        Item {
          width: parent.width
          height: dateRangeText.implicitHeight

          Text {
            id: dateRangeText
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
            text: root.season
              ? root.season.start + " → " + root.season.end
              : ""
            color: root.faintColor
            font.family: root.contentFontFamily
            font.pixelSize: Style.font.caption
          }
        }
      }
    }

    // ---- Off-Season / No Active Season ---------------------------------------
    Rectangle {
      visible: !root.loading && root.season === null
      width: parent.width
      height: offSeasonContent.implicitHeight + Style.space(16)
      radius: Style.cornerRadius
      color: Qt.rgba(root.contentForeground.r, root.contentForeground.g, root.contentForeground.b, 0.05)

      Column {
        id: offSeasonContent
        anchors.left: parent.left
        anchors.leftMargin: Style.space(14)
        anchors.right: parent.right
        anchors.rightMargin: Style.space(14)
        anchors.verticalCenter: parent.verticalCenter
        spacing: Style.space(4)

        Text {
          text: "No Season Active"
          color: root.contentForeground
          font.family: root.contentFontFamily
          font.pixelSize: Style.font.body
          font.bold: true
        }

        Text {
          text: root.nextSeason
            ? "The next season starts in " + root.nextSeason.days_until_start + " days."
            : "The next season has not been announced yet."
          color: root.dimColor
          font.family: root.contentFontFamily
          font.pixelSize: Style.font.bodySmall
        }
      }
    }

    // ---- Loading State -------------------------------------------------------
    Rectangle {
      visible: root.loading && root.season === null
      width: parent.width
      height: loadingContent.implicitHeight + Style.space(16)
      radius: Style.cornerRadius
      color: Qt.rgba(root.contentForeground.r, root.contentForeground.g, root.contentForeground.b, 0.05)

      Row {
        id: loadingContent
        anchors.centerIn: parent
        spacing: Style.space(10)

        Text {
          anchors.verticalCenter: parent.verticalCenter
          text: "🌸"
          font.pixelSize: Style.font.body
        }

        Text {
          anchors.verticalCenter: parent.verticalCenter
          text: "Loading season data…"
          color: root.dimColor
          font.family: root.contentFontFamily
          font.pixelSize: Style.font.bodySmall
        }
      }
    }

    // ---- Upcoming / Next Season ----------------------------------------------
    Text {
      visible: root.nextSeason !== null
      text: "UPCOMING SEASON"
      color: root.faintColor
      font.family: root.contentFontFamily
      font.pixelSize: Style.font.bodySmall
      font.letterSpacing: 1
      font.bold: true
    }

    Rectangle {
      id: nextSeasonCard
      visible: root.nextSeason !== null
      width: parent.width
      height: nextSeasonContent.implicitHeight + Style.space(14)
      radius: Style.cornerRadius
      color: Qt.rgba(root.contentForeground.r, root.contentForeground.g, root.contentForeground.b, 0.05)

      Column {
        id: nextSeasonContent
        anchors.left: parent.left
        anchors.leftMargin: Style.space(14)
        anchors.right: parent.right
        anchors.rightMargin: Style.space(14)
        anchors.verticalCenter: parent.verticalCenter
        spacing: Style.space(4)

        // Season name
        Text {
          width: parent.width
          text: root.nextSeason ? root.nextSeason.name : ""
          color: root.contentForeground
          font.family: root.contentFontFamily
          font.pixelSize: Style.font.body
          font.bold: true
          elide: Text.ElideRight
        }

        Item {
          width: parent.width
          height: Math.max(nextInfoText.implicitHeight, nextCountdownText.implicitHeight)

          Text {
            id: nextInfoText
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
            text: root.nextSeason
              ? "Season " + root.nextSeason.number + " · " + root.nextSeason.year + " · Starts " + root.nextSeason.start
              : ""
            color: root.dimColor
            font.family: root.contentFontFamily
            font.pixelSize: Style.font.caption
          }

          Text {
            id: nextCountdownText
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            text: root.nextSeason
              ? "in " + root.nextSeason.days_until_start + "d"
              : ""
            color: root.accentColor
            font.family: root.contentFontFamily
            font.pixelSize: Style.font.caption
            font.bold: true
          }
        }
      }
    }

    // ---- Footers -------------------------------------------------------------
    Text {
      visible: root.fetchError !== "" && root.season !== null
      text: "OFFLINE — " + root.fetchError.toUpperCase()
      color: root.accentColor
      font.family: root.contentFontFamily
      font.pixelSize: Style.font.caption
      font.bold: true
      wrapMode: Text.WordWrap
      width: parent.width
    }

    Text {
      text: "Season dates are calendar days in Pacific time"
      color: root.faintColor
      font.family: root.contentFontFamily
      font.pixelSize: Style.font.caption
      horizontalAlignment: Text.AlignHCenter
      anchors.horizontalCenter: parent.horizontalCenter
    }
  }
}
