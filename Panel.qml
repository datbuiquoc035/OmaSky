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

  readonly property bool showDailyReset: setting("showDailyReset", true) !== false
  readonly property int upcomingCount: Math.max(1, Math.min(7, Number(setting("upcomingDays", 3)) || 3))

  // Whether the standalone OmaEvents / OmaShard plugins are installed. A tab
  // whose backing plugin is missing shows an install prompt linking to the
  // plugin's GitHub page instead of its data.
  property bool eventsInstalled: hostWidget ? hostWidget.eventsPluginInstalled : false
  property bool shardsInstalled: hostWidget ? hostWidget.shardsPluginInstalled : false
  readonly property string eventsGithubUrl: "https://github.com/datbuiquoc035/omaevents"
  readonly property string shardsGithubUrl: "https://github.com/datbuiquoc035/omashard"

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
    root.tabIndex = (t === 1 || t === 2) ? 1 : 0
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
    if (root.bar && "centerHoverRevealSuppressed" in root.bar)
      root.bar.centerHoverRevealSuppressed = value
  }

  // Called by the host whenever a fetch settles; forwarded properties are
  // bound to the host directly, so this is mostly a refresh beat for the
  // keyboard "activate" path.
  function onDataChanged() {}

  function refresh() {
    if (hostWidget && hostWidget.fetchData) hostWidget.fetchData()
  }

  // Scroll the active tab's flickable by a row.
  function scrollCurrentTab(dy) {
    var tab = root.tabIndex === 0 ? eventsTab : shardsTab
    if (tab && tab.contentHeight > tab.height && typeof tab.flick === "function")
      tab.flick(0, dy * Style.space(24))
  }

  function cycleTabs(direction) {
    root.tabIndex = (root.tabIndex + (direction >= 0 ? 1 : -1) + 2) % 2
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
    contentHeight: panel.fittedContentHeight(tabColumn.implicitHeight)

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
                color: root.contentForeground
                font.family: root.contentFontFamily
                font.pixelSize: Style.font.title
                font.bold: true
              }

              Text {
                text: root.subtitle
                color: Qt.rgba(root.contentForeground.r, root.contentForeground.g, root.contentForeground.b, 0.72)
                font.family: root.contentFontFamily
                font.pixelSize: Style.font.bodySmall
                font.italic: true
              }
            }
          }
        }

        // ---- Tab bar -------------------------------------------------------
        Rectangle {
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
              width: (parent.width - parent.spacing) / 2
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
              width: (parent.width - parent.spacing) / 2
              height: parent.height
              icon: "🔮"
              label: "Shards"
              selected: root.tabIndex === 1
              foreground: root.contentForeground
              accent: root.accentColor
              fontFamily: root.contentFontFamily
              onClicked: root.tabIndex = 1
            }
          }
        }

        // ---- Active tab -------------------------------------------------------
        // The tab area hugs the active tab's content but caps at whatever will
        // fit on screen (panel available height minus the header + tab bar), so
        // a very tall tab scrolls instead of overflowing the popup. Height is
        // set explicitly because Column lays children out from implicit sizes.
        StackLayout {
          id: tabStack
          width: parent.width
          currentIndex: root.tabIndex
          property real tabHeight: Math.min(
            root.tabIndex === 0 ? eventsTab.implicitHeight : shardsTab.implicitHeight,
            Math.max(Style.space(300), panel.availableCardHeight - panel.verticalContentInset - Style.space(80))
          )
          implicitHeight: tabHeight
          height: tabHeight

          EventsTab {
            id: eventsTab
            installed: root.eventsInstalled
            githubUrl: root.eventsGithubUrl
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
            installed: root.shardsInstalled
            githubUrl: root.shardsGithubUrl
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
        }
      }
    }
  }
}