import QtQuick
import Quickshell.Hyprland

Row {
  id: root
  spacing: Theme.barSpacing

  Repeater {
    model: Hyprland.workspaces.values.slice().sort((a, b) => a.id - b.id)
    delete: Rectangle {
      required property var modelData
      readonly property var activeWs: (Hyprland.focusedMonitor?.activeWorkspace?.id ?? -1)

      width: 16
      height: 24

      radius: Theme.radius
      color: "transparent"
      border.color: "transparent"
      border.width: 1

      Text {
        anchors.centerIn: parent
        text: (modelData.id === activeWs) ? "●" : modelData.id
        color: Theme.foreground
        font {
          bold: true
          pixelSize: Theme.fontSm
        }
      }

      MouseArea {
        anchors.fill: parent
        onClicked: parent.modelData.activate()
      }
    }
  }
}
