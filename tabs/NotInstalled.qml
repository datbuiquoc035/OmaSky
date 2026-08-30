import QtQuick
import Quickshell.Io
import qs.Commons

// Full-tab placeholder shown when the standalone OmaEvents / OmaShard plugin
// that backs this tab is not installed on the machine. Explains what's
// missing and offers an install button that opens the plugin's GitHub page
// (via Qt.openUrlExternally, falling back to a detached xdg-open).
Item {
  id: root

  property string pluginName: ""
  property string message: ""
  property string githubUrl: ""
  property color contentForeground: Color.foreground
  property color accentColor: Color.accent
  property string contentFontFamily: Style.font.family

  width: parent ? parent.width : 0
  implicitHeight: content.implicitHeight

  function openUrl() {
    var u = String(root.githubUrl || "")
    if (!/^https?:\/\//.test(u)) return
    if (!Qt.openUrlExternally(u)) {
      fallbackProc.command = ["xdg-open", u]
      fallbackProc.running = true
    }
  }

  Column {
    id: content
    width: parent.width
    spacing: Style.space(10)

    Rectangle {
      width: parent.width
      height: noticeContent.implicitHeight + Style.space(18)
      radius: Style.cornerRadius
      color: Qt.rgba(root.accentColor.r, root.accentColor.g, root.accentColor.b, 0.08)
      border.width: Style.spacing.hairline
      border.color: Qt.rgba(root.accentColor.r, root.accentColor.g, root.accentColor.b, 0.3)

      Column {
        id: noticeContent
        anchors.left: parent.left
        anchors.leftMargin: Style.space(14)
        anchors.right: parent.right
        anchors.rightMargin: Style.space(14)
        anchors.verticalCenter: parent.verticalCenter
        spacing: Style.space(3)

        Text {
          width: parent.width
          text: "🛠  " + root.pluginName + " not installed"
          color: root.contentForeground
          font.family: root.contentFontFamily
          font.pixelSize: Style.font.body
          font.bold: true
          wrapMode: Text.WordWrap
        }

        Text {
          width: parent.width
          text: root.message
          color: Qt.rgba(root.contentForeground.r, root.contentForeground.g, root.contentForeground.b, 0.72)
          font.family: root.contentFontFamily
          font.pixelSize: Style.font.caption
          wrapMode: Text.WordWrap
        }
      }
    }

    Rectangle {
      id: installButton
      width: parent.width
      height: Style.space(34)
      radius: Style.cornerRadius
      color: Qt.rgba(root.accentColor.r, root.accentColor.g, root.accentColor.b, 0.16)
      border.width: Style.spacing.hairline
      border.color: Qt.rgba(root.accentColor.r, root.accentColor.g, root.accentColor.b, 0.35)

      Row {
        anchors.centerIn: parent
        spacing: Style.space(8)

        Text {
          anchors.verticalCenter: parent.verticalCenter
          text: "⬇"
          color: root.contentForeground
          font.pixelSize: Style.font.body
        }

        Text {
          anchors.verticalCenter: parent.verticalCenter
          text: "Install · GitHub"
          color: root.contentForeground
          font.family: root.contentFontFamily
          font.pixelSize: Style.font.bodySmall
          font.bold: true
        }
      }

      MouseArea {
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: root.openUrl()
      }
    }
  }

  Process {
    id: fallbackProc
    command: []
    running: false
  }
}