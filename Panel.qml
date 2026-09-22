import QtQuick
import QtQuick.Layouts
import Quickshell
import qs.Commons
import qs.Ui
import "Subtitles.js" as Subtitles
import "tabs"

// The OmaSky popup: a header (logo + title + rotating subtitle), an
// Events/Shards tab bar, and the active tab's content, which auto-sizes the
// popup to whatever tab is shown. Owned by BarWidget.qml, which hands this
// panel the button to anchor against and keeps both data sources fresh.
//
// Tab switching: click the tab, press Tab/Backtab, 1/2, or ←/→. Esc closes,
// Enter/Space refreshes. Up/Down scroll the active tab.
Panel {
  id: root
  moduleName: "qdot.omasky"
  ipcTarget: "qdot.omasky"
  manageIpc: false

  property var anchorItem: null

  // The bar tracks the widget mounted in its slot — BarWidget.qml — not this
  // nested panel. Everything the bar identifies a panel by has to be that
  // widget (popout coordinator, open-panel underline, switchPanelFrom).
  property var hostWidget: null
  readonly property var barIdentity: hostWidget || root

  property int tabIndex: 0

  // --- Data shared with the host widget -----------------------------------
  property var events: hostWidget ? hostWidget.events : []
  property var dailyReset: hostWidget ? hostWidget.dailyReset : null
  property string eventError: hostWidget ? hostWidget.eventError : ""
  property bool eventsLoading: hostWidget ? hostWidget.eventsLoading : true
  property string nowSkyLabel: hostWidget ? hostWidget.nowSkyLabel : ""
  property string nowLocalLabel: hostWidget ? hostWidget.nowLocalLabel : ""
  readonly property double nowMs: hostWidget ? hostWidget.nowMs : 0

  property var days: hostWidget ? hostWidget.days : []
  property var todayShard: hostWidget ? hostWidget.todayShard : null
  property string shardError: hostWidget ? hostWidget.shardError : ""
  property bool shardsLoading: hostWidget ? hostWidget.shardsLoading : true
  readonly property real displayTzOffset: hostWidget ? hostWidget.displayTzOffset : 0
  readonly property string tzLabel: hostWidget ? hostWidget.tzLabel : "Local"

  // --- Season data -----------------------------------------------------------
  property var season: hostWidget ? hostWidget.season : null
  property var nextSeason: hostWidget ? hostWidget.nextSeason : null
  property string seasonError: hostWidget ? hostWidget.seasonError : ""
  property bool seasonsLoading: hostWidget ? hostWidget.seasonsLoading : true
  property string seasonToday: hostWidget ? hostWidget.seasonToday : ""

  property bool migrationAvailable: hostWidget ? hostWidget.migrationAvailable : false
  property bool migrationDismissed: false

  readonly property bool showDailyReset: setting("showDailyReset", true) !== false
  readonly property int upcomingCount: Math.max(1, Math.min(7, Number(setting("upcomingDays", 3)) || 3))


  // Common tab content, set once from Settings for the whole panel. The tab
  // widgets only style text with these, so they stay in sync with the theme.
  // GUARDED so the panel renders before the bar is injected.
  readonly property color contentForeground: bar ? bar.foreground : Color.foreground
  readonly property string contentFontFamily: bar ? bar.fontFamily : Style.font.family
  readonly property color accentColor: Color.accent

  // A subtitle is picked when the panel opens or the day changes.
  property string subtitle: Subtitles.getRandomSubtitle()

  function setTab(tab) {
    var t = Number(tab)
    root.tabIndex = Math.max(0, Math.min(2, t))
  }

  // Debounce keyboard auto-repeat (Enter/Space at ~30Hz) so holding the
  // key can't spawn dozens of python procs per second (H3). BarWidget
  // also debounces fetchData, this is the first line of defence.
  Timer {
    id: refreshDebounce
    interval: 1000
    repeat: false
  }

  function open() {
    refresh()
    root.controller.show()
    Qt.callLater(function() {
      if (root.opened) setCenterHoverRevealSuppressed(true)
    })
  }

  function close() {
    setCenterHoverRevealSuppressed(false)
    root.controller.hide()
    // Flush a migration rescan that BarWidget deferred while we were open.
    if (hostWidget && hostWidget.rescanPending && hostWidget.close) {
      // hostWidget.close() flushes rescanPending without reopening us.
      // Call via callLater so KeyboardPanel focus release settles first.
      Qt.callLater(function() {
        if (!root.opened && hostWidget && hostWidget.rescanPending) {
          hostWidget.close()
        }
      })
    }
  }

  Component.onDestruction: {
    // If rescan destroys us mid-open, never leave the bar's hover-reveal
    // suppressed or the shell feels input-stuck (H6).
    setCenterHoverRevealSuppressed(false)
  }

  function toggle() {
    if (root.opened) root.close()
    else root.open()
  }

  function switchPanel(direction) {
    if (root.bar && typeof root.bar.switchPanelFrom === "function")
      return root.bar.switchPanelFrom(root.barIdentity, direction)
    return false
  }

  function setCenterHoverRevealSuppressed(value) {
    if (root.bar && typeof root.bar.setCenterHoverRevealSuppressed === "function")
      root.bar.setCenterHoverRevealSuppressed(value)
    else if (root.bar && "centerHoverRevealSuppressed" in root.bar)
      root.bar.centerHoverRevealSuppressed = value
  }

  // Called by the host whenever a fetch settles; forwarded properties are
  // bound to the host directly, so this is mostly a refresh beat for the
  // keyboard "activate" path.
  function onDataChanged() {}

  // Layout introspection for diagnosing popup sizing issues:
  // reports every link in the card-height chain as JSON.
  function debugLayout() {
    function r(v) { return Math.round(Number(v) * 10) / 10 }
    return JSON.stringify({
      contentWidth: panel.contentWidth,
      contentHeight: panel.contentHeight,
      availableW: r(panel.availableCardWidth),
      availableH: r(panel.availableCardHeight),
      inset: r(panel.verticalContentInset),
      tabColumnW: r(tabColumn.width),
      tabColumnH: r(tabColumn.height),
      tabColumnImplicit: r(tabColumn.implicitHeight),
      titleCardH: r(titleCard.height),
      titleRowImplicit: r(titleRow.implicitHeight),
      titleRowH: r(titleRow.height),
      tabBarH: r(tabBarRect.height),
      migrationVisible: migrationCard.visible,
      migrationH: r(migrationCard.height),
      tabHeight: r(tabStack.tabHeight),
      activeImplicit: r(tabStack.activeImplicit),
      headerH: r(tabStack.headerH),
      maxTabH: r(tabStack.maxTabH),
      eventsImplicit: r(eventsTab.implicitHeight),
      eventsH: r(eventsTab.height),
      eventsW: r(eventsTab.width),
      shardsImplicit: r(shardsTab.implicitHeight),
      seasonImplicit: r(seasonTab.implicitHeight)
    })
  }

  function refresh(force) {
    if (force === true) {
      refreshDebounce.restart()
      if (hostWidget && hostWidget.fetchData) hostWidget.fetchData(true)
      return
    }
    if (refreshDebounce.running) return
    refreshDebounce.restart()
    if (hostWidget && hostWidget.fetchData) hostWidget.fetchData()
  }

  // Scroll the active tab's flickable by a row.
  function scrollCurrentTab(dy) {
    var tab = root.tabIndex === 0 ? eventsTab : (root.tabIndex === 1 ? shardsTab : seasonTab)
    if (tab && tab.contentHeight > tab.height && typeof tab.flick === "function")
      tab.flick(0, dy * Style.space(24))
  }

  function cycleTabs(direction) {
    root.tabIndex = (root.tabIndex + (direction >= 0 ? 1 : -1) + 3) % 3
  }

  SystemClock {
    id: clock
    precision: SystemClock.Minutes
    onDateChanged: {
      if (hostWidget && hostWidget.fetchData) hostWidget.fetchData()
      root.subtitle = Subtitles.getRandomSubtitle()
    }
  }

  KeyboardPanel {
    id: panel
    anchorItem: root.anchorItem
    owner: root.barIdentity
    bar: root.bar
    open: root.opened
    centerOnBar: false
    focusTarget: keyCatcher
    contentWidth: panel.fittedContentWidth(Style.space(380))
    // Cap like first-party panels (audio/network/monitor use 560): without
    // a cap every 1s countdown text change re-evaluates tabColumn height →
    // fittedContentHeight while open (H4 layout thrash).
    contentHeight: panel.fittedContentHeight(tabColumn.implicitHeight, Style.space(560))

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent

      onCloseRequested: root.close()
      onTabRequested: function(direction) { root.cycleTabs(direction) }
      onMoveRequested: function(dx, dy) {
        if (dx !== 0) root.cycleTabs(dx)
        else if (dy !== 0) root.scrollCurrentTab(dy)
      }
      onActivateRequested: root.refresh()
      onTextKey: function(text) {
        var number = Number(text)
        if (number === 1) root.tabIndex = 0
        else if (number === 2) root.tabIndex = 1
        else if (number === 3) root.tabIndex = 2
      }

      Column {
        id: tabColumn
        anchors.fill: parent
        spacing: Style.space(10)

        // ---- Title card: logo + name + rotating subtitle -----------------
        Rectangle {
          id: titleCard
          width: parent.width
          height: titleRow.implicitHeight + Style.space(16)
          radius: Style.cornerRadius > 0 ? Style.cornerRadius * 1.5 : 0
          color: Qt.rgba(Color.accent.r, Color.accent.g, Color.accent.b, 0.12)
          border.width: Style.spacing.hairline
          border.color: Qt.rgba(Color.accent.r, Color.accent.g, Color.accent.b, 0.35)

          Row {
            id: titleRow
            x: Style.space(14)
            y: Style.space(8)
            width: parent.width - Style.space(28)
            spacing: Style.space(12)

            Image {
              anchors.verticalCenter: parent.verticalCenter
              source: Qt.resolvedUrl("assets/tgc-logo.png")
              width: Math.round(Style.font.title * 1.4)
              height: Math.round(Style.font.title * 1.4)
              fillMode: Image.PreserveAspectFit
              smooth: true
              mipmap: true
              sourceSize.width: Math.round(Style.font.title * 2.8 * Screen.devicePixelRatio)
              sourceSize.height: Math.round(Style.font.title * 2.8 * Screen.devicePixelRatio)
            }

            Column {
              anchors.verticalCenter: parent.verticalCenter
              spacing: Style.space(1)

              Text {
                text: "✦ OmaSky"
                textFormat: Text.PlainText
                color: root.contentForeground
                font.family: root.contentFontFamily
                font.pixelSize: Style.font.title
                font.bold: true
              }

              Text {
                text: root.subtitle
                textFormat: Text.PlainText
                color: Qt.rgba(root.contentForeground.r, root.contentForeground.g, root.contentForeground.b, 0.72)
                font.family: root.contentFontFamily
                font.pixelSize: Style.font.bodySmall
                font.italic: true
              }
            }
          }
        }

        // ---- Migration notice card (requires user consent) ----------------
        Rectangle {
          id: migrationCard
          visible: root.migrationAvailable && !root.migrationDismissed
          width: parent.width
          height: visible ? migrationLayout.implicitHeight + Style.space(16) : 0
          radius: Style.cornerRadius > 0 ? Style.cornerRadius * 1.2 : 0
          color: Qt.rgba(root.accentColor.r, root.accentColor.g, root.accentColor.b, 0.12)
          border.width: Style.spacing.hairline
          border.color: Qt.rgba(root.accentColor.r, root.accentColor.g, root.accentColor.b, 0.35)

          Column {
            id: migrationLayout
            x: Style.space(14)
            y: Style.space(8)
            width: parent.width - Style.space(28)
            spacing: Style.space(8)

            Row {
              width: parent.width
              spacing: Style.space(10)

              Text {
                text: "✨"
                textFormat: Text.PlainText
                font.pixelSize: Style.font.title
                anchors.verticalCenter: parent.verticalCenter
              }

              Column {
                width: parent.width - Style.space(34)
                anchors.verticalCenter: parent.verticalCenter
                spacing: Style.space(2)

                Text {
                  text: "Legacy Layout Detected"
                  textFormat: Text.PlainText
                  color: root.contentForeground
                  font.family: root.contentFontFamily
                  font.pixelSize: Style.font.body
                  font.bold: true
                }

                Text {
                  text: "Merge separate OmaShard and OmaEvents widgets into OmaSky."
                  textFormat: Text.PlainText
                  color: Qt.rgba(root.contentForeground.r, root.contentForeground.g, root.contentForeground.b, 0.78)
                  font.family: root.contentFontFamily
                  font.pixelSize: Style.font.bodySmall
                  wrapMode: Text.WordWrap
                  width: parent.width
                }
              }
            }

            Row {
              spacing: Style.space(8)
              anchors.right: parent.right

              Rectangle {
                width: dismissText.implicitWidth + Style.space(16)
                height: Style.space(26)
                radius: Style.cornerRadius > 0 ? Style.cornerRadius * 0.75 : 0
                color: dismissArea.containsMouse ? Qt.rgba(root.contentForeground.r, root.contentForeground.g, root.contentForeground.b, 0.1) : "transparent"
                border.width: Style.spacing.hairline
                border.color: Qt.rgba(root.contentForeground.r, root.contentForeground.g, root.contentForeground.b, 0.2)

                Text {
                  id: dismissText
                  anchors.centerIn: parent
                  text: "Dismiss"
                  textFormat: Text.PlainText
                  color: root.contentForeground
                  font.family: root.contentFontFamily
                  font.pixelSize: Style.font.caption
                }

                MouseArea {
                  id: dismissArea
                  anchors.fill: parent
                  hoverEnabled: true
                  cursorShape: Qt.PointingHandCursor
                  onClicked: root.migrationDismissed = true
                }
              }

              Rectangle {
                width: migrateText.implicitWidth + Style.space(18)
                height: Style.space(26)
                radius: Style.cornerRadius > 0 ? Style.cornerRadius * 0.75 : 0
                color: migrateArea.containsMouse ? root.accentColor : Qt.rgba(root.accentColor.r, root.accentColor.g, root.accentColor.b, 0.85)

                Text {
                  id: migrateText
                  anchors.centerIn: parent
                  text: "Migrate Layout"
                  textFormat: Text.PlainText
                  color: root.contentForeground
                  font.family: root.contentFontFamily
                  font.pixelSize: Style.font.caption
                  font.bold: true
                }

                MouseArea {
                  id: migrateArea
                  anchors.fill: parent
                  hoverEnabled: true
                  cursorShape: Qt.PointingHandCursor
                  onClicked: {
                    if (root.hostWidget && typeof root.hostWidget.applyMigration === "function") {
                      root.hostWidget.applyMigration()
                    }
                  }
                }
              }
            }
          }
        }

        // ---- Tab bar -------------------------------------------------------
        Rectangle {
          id: tabBarRect
          width: parent.width
          height: Style.space(44)
          radius: Style.cornerRadius
          color: Qt.rgba(root.contentForeground.r, root.contentForeground.g, root.contentForeground.b, 0.03)
          border.width: Style.spacing.hairline
          border.color: Qt.rgba(root.contentForeground.r, root.contentForeground.g, root.contentForeground.b, 0.05)

          Row {
            anchors.fill: parent
            anchors.margins: Style.spacing.xxs
            spacing: Style.spacing.xxs

            NavTab {
              width: (parent.width - parent.spacing * 2) / 3
              height: parent.height
              icon: "🕐"
              label: "Events"
              selected: root.tabIndex === 0
              foreground: root.contentForeground
              accent: root.accentColor
              fontFamily: root.contentFontFamily
              onClicked: root.tabIndex = 0
            }

            NavTab {
              width: (parent.width - parent.spacing * 2) / 3
              height: parent.height
              icon: "🔮"
              label: "Shards"
              selected: root.tabIndex === 1
              foreground: root.contentForeground
              accent: root.accentColor
              fontFamily: root.contentFontFamily
              onClicked: root.tabIndex = 1
            }

            NavTab {
              width: (parent.width - parent.spacing * 2) / 3
              height: parent.height
              icon: "🌸"
              label: "Season"
              selected: root.tabIndex === 2
              foreground: root.contentForeground
              accent: root.accentColor
              fontFamily: root.contentFontFamily
              onClicked: root.tabIndex = 2
            }
          }
        }

        // ---- Active tab -------------------------------------------------------
        // The tab area hugs the active tab's content but is capped to what
        // fits INSIDE the clamped card: header + tab + inset must stay <=
        // min(available, 560), otherwise the StackLayout overflows the card
        // and the panel looks cut short. Height is set explicitly because
        // Column lays children out from implicit sizes.
        StackLayout {
          id: tabStack
          width: parent.width
          currentIndex: root.tabIndex
          // Every link hardened: a single NaN anywhere in this chain used to
          // collapse the whole popup (NaN propagates through Math.min/max,
          // height NaN renders as 0, and the card shrank to its inset).
          property real activeImplicitRaw: root.tabIndex === 0 ? eventsTab.implicitHeight : (root.tabIndex === 1 ? shardsTab.implicitHeight : seasonTab.implicitHeight)
          property real activeImplicit: {
            var h = Number(activeImplicitRaw)
            return isFinite(h) && h > 0 ? h : 320
          }
          // Everything above the stack plus the gaps before it.
          property int aboveCount: migrationCard.visible ? 3 : 2
          property real headerHRaw: titleCard.height + (migrationCard.visible ? migrationCard.height : 0) + tabBarRect.height + tabColumn.spacing * aboveCount
          property real headerH: {
            var h = Number(headerHRaw)
            return isFinite(h) && h > 0 ? h : 140
          }
          property real maxTabHRaw: Math.min(panel.availableCardHeight, Style.space(560)) - panel.verticalContentInset - headerH
          property real maxTabH: {
            var m = Math.max(Style.space(200), maxTabHRaw)
            return isFinite(m) && m > 0 ? m : 320
          }
          // Rounded: fractional heights put every anchored Text on half
          // pixels and the whole panel reads blurry.
          property real tabHeight: {
            var t = Math.round(Math.min(activeImplicit, maxTabH))
            return isFinite(t) && t > 0 ? t : 320
          }
          implicitHeight: tabHeight
          height: tabHeight

          EventsTab {
            id: eventsTab
            events: root.events
            dailyReset: root.dailyReset
            nowMs: root.nowMs
            nowSkyLabel: root.nowSkyLabel
            nowLocalLabel: root.nowLocalLabel
            showDailyReset: root.showDailyReset
            fetchError: root.eventError
            loading: root.eventsLoading
            contentForeground: root.contentForeground
            accentColor: root.accentColor
            contentFontFamily: root.contentFontFamily
          }

          ShardsTab {
            id: shardsTab
            days: root.days
            todayShard: root.todayShard
            displayTzOffset: root.displayTzOffset
            tzLabel: root.tzLabel
            upcomingCount: root.upcomingCount
            fetchError: root.shardError
            loading: root.shardsLoading
            contentForeground: root.contentForeground
            accentColor: root.accentColor
            contentFontFamily: root.contentFontFamily
          }

          SeasonTab {
            id: seasonTab
            season: root.season
            nextSeason: root.nextSeason
            seasonToday: root.seasonToday
            fetchError: root.seasonError
            loading: root.seasonsLoading
            contentForeground: root.contentForeground
            accentColor: root.accentColor
            contentFontFamily: root.contentFontFamily
          }
        }
      }
    }
  }
}