import QtQuick
import Quickshell

PanelWindow {
  id: window

  readonly property int pillWidth: 128
  readonly property int pillHeight: 32
  readonly property int floatMargin: 10

  // left+right anchors force the surface to full screen width, so implicitWidth
  // is ignored (Quickshell's constrainedSize() returns 0 for constrained axes).
  implicitWidth: 0
  // Must cover the float gap + the pill, because Auto derives the exclusive
  // zone from implicitHeight. If the pill bled above y=0 this would be wrong.
  implicitHeight: pillHeight + floatMargin

  color: "transparent"
  aboveWindows: true
  focusable: false

  // Auto (not Normal) is what computes the zone from implicitHeight.
  // Normal just passes through `exclusiveZone`, which defaults to 0.
  // Auto only works with 1 or 3 anchors: exclusionEdge() needs a vertical XOR
  // edge AND no horizontal XOR edge, so adding `left` alone would zero it out.
  exclusionMode: ExclusionMode.Auto

  anchors {
    top: true
    left: true
    right: true
  }

  Rectangle {
    id: pill

    anchors.top: parent.top
    anchors.topMargin: window.floatMargin
    anchors.horizontalCenter: parent.horizontalCenter
    width: window.pillWidth
    height: window.pillHeight
    radius: height / 2
    color: "#000000"
  }

  Text {
    anchors.centerIn: pill

    text: Qt.formatDateTime(clock.date, "HH:mm")
    color: "#ffffff"
    font.pixelSize: 16
    font.weight: Font.Bold
  }

  SystemClock {
    id: clock

    precision: SystemClock.Minutes
  }

  mask: Region {
    item: pill
    topLeftRadius: pill.radius
    topRightRadius: pill.radius
    bottomLeftRadius: pill.radius
    bottomRightRadius: pill.radius
  }
}
