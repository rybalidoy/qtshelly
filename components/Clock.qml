import QtQuick
import Quickshell

Item {
  id: root
  
  property string format: "HH:mm"
  property color foreground: "#e6e6e6"
  property int horizontalPadding: 12

  readonly property date currentDate: clock.date

  width: implicitWidth
  height: implicitHeight
  implicitWidth: label.implicitWidth + horizontalPadding * 2
  implicitHeight: 30

  SystemClock {
    id: clock
    precision: SystemClock.Minutes
  }

  Text {
    id: label
    anchors.centerIn: parent
    text: Qt.formatDateTime(root.currentDate, root.format)
    color: root.foreground
    font.family: "monospace"
    font.pixelSize: 14
    font.bold: true
    horizontalAlignment: Text.AlignHCenter
    verticalAlignment: Text.AlignVCenter
  }

}
