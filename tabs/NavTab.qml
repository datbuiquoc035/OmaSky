import QtQuick
import qs.Commons

// Tab button for the OmaSky panel's Events / Shards switcher. Selected state
// is an accent underline; unselected tabs show the icon and label muted.
Item {
  id: root

  property string icon: ""
  property string label: ""
  property bool selected: false
  property color foreground: Color.foreground
  property color accent: Color.accent
  property string fontFamily: Style.font.family
  signal clicked()

  implicitHeight: Style.space(38)

  Rectangle {
    anchors.fill: parent
    radius: Style.cornerRadius > 0 ? Style.cornerRadius * 1.2 : 0
    color: root.selected
      ? Qt.rgba(root.accent.r, root.accent.g, root.accent.b, 0.14)
      : "transparent"

    Rectangle {
      visible: root.selected
      anchors.horizontalCenter: parent.horizontalCenter
      anchors.bottom: parent.bottom
      width: Math.min(parent.width * 0.5, Style.space(42))
      height: Style.space(3)
      radius: Math.round(height / 2)
      color: root.accent
    }
  }

  Row {
    anchors.centerIn: parent
    spacing: Style.spacing.xs

    Text {
      text: root.icon
      textFormat: Text.PlainText
      color: root.selected ? root.foreground : Color.muted
      opacity: root.selected ? 1.0 : 0.6
      font.family: root.fontFamily
      font.pixelSize: Style.font.body
      anchors.verticalCenter: parent.verticalCenter
    }

    Text {
      text: root.label
      textFormat: Text.PlainText
      color: root.selected ? root.foreground : Color.muted
      opacity: root.selected ? 1.0 : 0.6
      font.family: root.fontFamily
      font.pixelSize: Style.font.bodySmall
      font.bold: root.selected
      anchors.verticalCenter: parent.verticalCenter
    }
  }

  MouseArea {
    anchors.fill: parent
    onClicked: root.clicked()
  }
}