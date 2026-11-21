import QtQuick
import qs.Commons
import qs.Commons as Commons

Item {
  id: root
  property real fraction: 0
  property color foreground: Commons.Color.foreground
  property color urgent: Commons.Color.urgent
  property bool hovered: false
  readonly property int litSegments: Math.ceil(Math.max(0, Math.min(1, fraction)) * 8)
  readonly property color fillColor: fraction >= 0.9 ? urgent : foreground

  Repeater {
    model: 8
    Rectangle {
      required property int index
      readonly property int ringIndex: [0, 1, 2, 4, 7, 6, 5, 3][index]
      readonly property int column: index % 3
      readonly property int row: Math.floor(index / 3)
      x: column * root.width / 3 + root.width * 0.045
      y: row * root.height / 3 + root.height * 0.045
      width: root.width / 3 - root.width * 0.09
      height: root.height / 3 - root.height * 0.09
      radius: Math.max(1, width * 0.18)
      color: ringIndex < root.litSegments ? root.fillColor : "transparent"
      border.width: Math.max(1, root.width / 18)
      border.color: ringIndex < root.litSegments ? root.fillColor
        : Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, root.hovered ? 0.58 : 0.28)
    }
  }

  Rectangle {
    anchors.centerIn: parent
    width: root.width / 3 - root.width * 0.09
    height: width
    radius: Math.max(1, width * 0.18)
    color: root.litSegments >= 8 ? root.fillColor : "transparent"
    border.width: Math.max(1, root.width / 18)
    border.color: root.fillColor
    opacity: root.litSegments >= 8 ? 1 : 0.72
    rotation: 45
  }
}
