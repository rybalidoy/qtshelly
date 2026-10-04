import QtQuick
import Quickshell
import Quickshell.Services.Pipewire
import Quickshell.Wayland
import "."

Item {
  id: root

  property int barHeight: 38
  property color background: "#000000"

  property color foreground: "#e6e6e6"

  // Wired up by shell.qml. Stays null until then, in which case the
  // sound button is simply inert.
  property var soundCenter: null

  // Mirrors the live output channel so the bar icon reflects volume and
  // mute without the sound center ever being opened.
  readonly property bool hasOutput: !!(Pipewire.defaultAudioSink && Pipewire.defaultAudioSink.audio)
  readonly property bool outputMuted: hasOutput ? Pipewire.defaultAudioSink.audio.muted : false
  readonly property real outputVolume: hasOutput ? Pipewire.defaultAudioSink.audio.volume : 0

  Variants {
    model: Quickshell.screens

    delegate: Component {
      PanelWindow {
        id: bar
        required property var modelData

        screen: modelData
        color: root.background
        implicitWidth: 0
        implicitHeight: barHeight
        exclusionMode: ExclusionMode.Auto 
        aboveWindows: true
        surfaceFormat.opaque: false
        WlrLayershell.namespace: "quickshell-bar"
        WlrLayershell.layer: WlrLayer.Top

        anchors {
          top: true
          left: true
          right: true
        }

        Item {
          id: content
          anchors.fill: parent
          clip: true

          Clock {
            id: clock
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.verticalCenter: parent.verticalCenter
            foreground: root.foreground
          }

          // ── Sound center button ────────────────────────
          // Icon only; opens the sound center panel.
          Rectangle {
            id: soundButton
            anchors.right: parent.right
            anchors.rightMargin: 8
            anchors.verticalCenter: parent.verticalCenter
            width: 26
            height: 26
            radius: Theme.radius
            color: soundHover.containsMouse ? Theme.surfaceHover : "transparent"

            Text {
              anchors.centerIn: parent
              text: soundButton.soundIcon()
              color: Theme.foreground
              font.family: Theme.fontFamily
              font.pixelSize: Theme.fontMd
              opacity: root.outputMuted ? 0.5 : 1.0
            }

            // Speaker glyph follows the live volume, matching the panel.
            function soundIcon() {
              if (!root.hasOutput || root.outputMuted) return "󰕾";
              if (root.outputVolume >= 0.67) return "󰕽";
              if (root.outputVolume >= 0.34) return "󰖀";
              if (root.outputVolume > 0) return "󰔀";
              return "󰕾";
            }

            MouseArea {
              id: soundHover
              anchors.fill: parent
              hoverEnabled: true
              cursorShape: Qt.PointingHandCursor
              // Right-click is the mute-anywhere gesture, matching omarchy.
              onClicked: function(mouse) {
                if (!root.soundCenter) return;
                if (mouse.button === Qt.RightButton) root.soundCenter.toggleAllMuted();
                else root.soundCenter.toggle();
              }
            }
          }
        }
      }
    }
  }
}
