import QtQuick
import "."

// Horizontal volume slider themed from Theme.qml.
//
// Modelled on omarchy's shell/Ui/PanelSlider.qml, minus the dependency on
// their Style singleton and bar object: colours come straight from Theme,
// and `bar` is replaced by a `muted` flag for the dimmed-when-inactive
// look the sound center uses.
Item {
    id: root

    property real value: 0
    property real minimum: 0
    property real maximum: 1
    property real step: 0.05
    property bool muted: false

    // Dragging needs a local copy of the value, otherwise the slider fights
    // the PipeWire round-trip while the pointer is still down.
    property bool dragging: false
    property real liveValue: value

    property color trackColor: Theme.surface
    property color fillColor: Theme.accent
    property color knobColor: Theme.foreground
    property int trackHeight: 5
    property int knobSize: 14

    signal moved(real value)
    signal rightClicked()

    readonly property real range: Math.max(0.0001, maximum - minimum)
    readonly property real progress: Math.max(0, Math.min(1, (liveValue - minimum) / range))
    readonly property bool hot: mouseArea.containsMouse || root.dragging

    onValueChanged: if (!dragging) liveValue = value

    implicitHeight: 22
    implicitWidth: 200

    function valueFromX(x) {
        var clamped = Math.max(0, Math.min(track.width, x))
        return Math.max(root.minimum, Math.min(root.maximum, root.minimum + (clamped / track.width) * root.range))
    }

    Rectangle {
        id: track
        anchors.verticalCenter: parent.verticalCenter
        anchors.left: parent.left
        anchors.right: parent.right
        height: root.trackHeight
        radius: height / 2
        color: root.trackColor
        opacity: root.muted ? 0.5 : 1.0
    }

    Rectangle {
        anchors.verticalCenter: track.verticalCenter
        anchors.left: track.left
        height: track.height
        radius: track.radius
        color: root.fillColor
        width: track.width * root.progress
        opacity: root.muted ? 0.5 : 1.0

        Behavior on width {
            enabled: !root.dragging
            NumberAnimation { duration: 140; easing.type: Easing.OutCubic }
        }
    }

    Rectangle {
        id: knob
        width: root.knobSize
        height: root.knobSize
        radius: width / 2
        color: root.knobColor
        // A ring in the panel background colour separates the knob from the
        // fill it sits on top of.
        border.width: 2
        border.color: Theme.background
        opacity: root.muted ? 0.5 : 1.0
        anchors.verticalCenter: track.verticalCenter
        x: Math.max(0, Math.min(track.width - width, track.width * root.progress - width / 2))
        scale: root.hot ? 1.15 : 1.0

        Behavior on x {
            enabled: !root.dragging
            NumberAnimation { duration: 140; easing.type: Easing.OutCubic }
        }
        Behavior on scale {
            NumberAnimation { duration: 110; easing.type: Easing.OutCubic }
        }
    }

    MouseArea {
        id: mouseArea
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        acceptedButtons: Qt.LeftButton | Qt.RightButton

        onPressed: function(mouse) {
            if (mouse.button !== Qt.LeftButton) return
            root.dragging = true
            var next = root.valueFromX(mouse.x)
            root.liveValue = next
            root.moved(next)
        }
        onPositionChanged: function(mouse) {
            if (!root.dragging) return
            var next = root.valueFromX(mouse.x)
            root.liveValue = next
            root.moved(next)
        }
        onReleased: function(mouse) {
            if (mouse.button !== Qt.LeftButton) return
            root.dragging = false
            root.liveValue = root.value
        }
        onClicked: function(mouse) {
            if (mouse.button === Qt.RightButton) root.rightClicked()
        }
        onWheel: function(wheel) {
            var delta = wheel.angleDelta.y > 0 ? root.step : -root.step
            var next = Math.max(root.minimum, Math.min(root.maximum, root.liveValue + delta))
            root.liveValue = next
            root.moved(next)
            root.liveValue = root.value
        }
    }
}
