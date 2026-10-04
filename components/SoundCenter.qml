import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Services.Mpris
import Quickshell.Services.Pipewire
import Quickshell.Wayland
import "."
import "AudioModel.js" as Audio

// SoundCenter: output/input/stream volume control, opened from the bar.
//
// Ported from omarchy's shell/plugins/panels/audio/Panel.qml. The
// differences are deliberate:
//
//   * No omarchy plugin infrastructure. Their `Panel`, `KeyboardPanel`,
//     `PanelSlider`, `CursorSurface`, `ToggleSwitch`, `Style` and `Color`
//     all live in qs.Ui / qs.Commons, which this config does not have.
//     Colours come from Theme.qml, and this is a plain PanelWindow rather
//     than a bar-anchored popup.
//   * No omarchy helper binaries. `omarchy-audio-output-sink`,
//     `omarchy-audio-sink-availability` and
//     `omarchy-audio-output-set-default` are not installed here, so the
//     default sink comes straight from Pipewire. See setDefaultSink().
//   * Flat cursor model instead of their focusSection/selectedIndex pair:
//     every visible row is one entry in `rows`, so keyboard navigation is
//     a single index that skips headers.
//
// Rows come from Pipewire directly, but the Repeater renders from
// snapshots rather than the live model: a Repeater rebuilt from PipeWire's
// own removal signal has crashed omarchy's Pipewire service, so the
// refresh timer lets that mutation settle first.
Scope {
    id: root

    property bool visible: false

    // ── Toggle ─────────────────────────────────────────────────
    // Opening refreshes the row snapshots and parks the cursor on the
    // output slider. Closing drops the snapshots, so a hidden panel holds
    // no PipeWire references.
    function toggle() {
        root.visible = !root.visible;
        if (root.visible) {
            cursorIndex = 0;
            root.refreshDisplay();
        } else {
            displaySinks = [];
            displaySources = [];
            displayStreams = [];
            sinkOptions = [];
            streamInputs = [];
            streamRoutes = ({});
            expandedStreamId = -1;
        }
    }

    // ── PipeWire state ─────────────────────────────────────────
    readonly property var sink: Pipewire.defaultAudioSink
    readonly property var source: Pipewire.defaultAudioSource
    readonly property var nodes: Pipewire.nodes ? Pipewire.nodes.values : []
    readonly property var mprisPlayers: Mpris.players ? Mpris.players.values : []

    // Only channels that actually exist get a vote, so a machine with no
    // microphone cannot report "input unmuted" forever.
    readonly property bool hasOutput: !!(sink && sink.audio)
    readonly property bool hasInput: !!(source && source.audio)

    // The default source is very often a DSP node: EasyEffects publishes
    // easyeffects_source, and that node is only bound while something is
    // actually recording, so it sits at ready === false / audio === null
    // most of the time. Writing to it is impossible in that state, so fall
    // back to the first input device that does have an audio interface --
    // otherwise the input slider is permanently dead on a machine running
    // EasyEffects, which is exactly this one.
    readonly property var inputTarget: {
        if (root.hasInput) return root.source;
        var list = root.sources;
        for (var i = 0; i < list.length; i++) {
            if (list[i] && list[i].audio) return list[i];
        }
        return root.source;
    }

    readonly property bool hasInputTarget: !!(inputTarget && inputTarget.audio)

    readonly property real outputVolume: hasOutput ? sink.audio.volume : 0
    readonly property bool outputMuted: hasOutput ? sink.audio.muted : false
    readonly property real inputVolume: hasInputTarget ? inputTarget.audio.volume : 0
    readonly property bool inputMuted: hasInputTarget ? inputTarget.audio.muted : false

    // The hero switch is the panel's master on/off. It reads as on while
    // anything is still audible, so muting one channel does not flip it.
    readonly property bool anyAudible: (hasOutput && !outputMuted) || (hasInputTarget && !inputMuted)
    readonly property string toggleHint: anyAudible ? "Mute" : "Unmute"

    // ── Candidate nodes ────────────────────────────────────────
    // Structural checks only; no property reads.
    readonly property var candidateSinks: {
        var list = [];
        for (var i = 0; i < nodes.length; i++) {
            var n = nodes[i];
            if (n && n.isSink && !n.isStream) list.push(n);
        }
        return list;
    }

    readonly property var candidateSources: {
        var list = [];
        for (var i = 0; i < nodes.length; i++) {
            var n = nodes[i];
            if (!n || n.isSink || n.isStream) continue;
            // Quickshell's own capture node is plumbing, not a microphone.
            if (String(n.name || "") === "quickshell") continue;
            if (!Audio.isAudioSource(n) && !Audio.isUnclassifiedVirtualSource(n)) continue;
            list.push(n);
        }
        return list;
    }

    readonly property var candidateStreams: {
        var list = [];
        for (var i = 0; i < nodes.length; i++) {
            var n = nodes[i];
            if (!n || !n.isStream || !Audio.isPlaybackStream(n)) continue;
            // A speaker tuning is a playback stream, but it is the processing
            // itself rather than an application.
            if (String(n.name || "").indexOf("omarchy_speaker_tuning") === 0) continue;
            list.push(n);
        }
        return list;
    }

    // `audio` is only populated once a node is bound, so a node without it
    // is not usable yet and is left out until the next refresh.
    readonly property var sinks: {
        var list = [];
        for (var i = 0; i < candidateSinks.length; i++) {
            if (candidateSinks[i] && candidateSinks[i].audio) list.push(candidateSinks[i]);
        }
        // Never drop the live default, even if WirePlumber has not
        // republished the node list yet.
        if (sink && list.indexOf(sink) < 0) list.unshift(sink);
        return list;
    }

    readonly property var sources: {
        var list = [];
        for (var i = 0; i < candidateSources.length; i++) {
            if (candidateSources[i] && candidateSources[i].audio) list.push(candidateSources[i]);
        }
        if (source && list.indexOf(source) < 0) list.unshift(source);
        return list;
    }

    readonly property var streams: {
        var list = [];
        for (var i = 0; i < candidateStreams.length; i++) {
            if (candidateStreams[i] && candidateStreams[i].audio) list.push(candidateStreams[i]);
        }
        return list;
    }

    // What the input device list shows. Wider than `sources` above: a DSP
    // node that is not currently bound still belongs in the list, it simply
    // cannot take a volume until something is recording into it.
    readonly property var listableSources: {
        var list = Audio.listSnapshot(candidateSources);
        if (source && list.indexOf(source) < 0) list.unshift(source);
        return list;
    }

    // Snapshots the Repeater actually renders from.
    property var displaySinks: []
    property var displaySources: []
    property var displayStreams: []

    function refreshDisplay() {
        if (!root.visible) return;
        displaySinks = Audio.listSnapshot(sinks);
        displaySources = Audio.listSnapshot(listableSources);
        displayStreams = Audio.listSnapshot(streams);
        root.applyRoutes();
        root.clampCursor();
    }

    // Keep the tracker attached to candidate nodes so PipeWire does not tear
    // them down while the snapshots still reference them.
    PwObjectTracker { objects: root.candidateSinks }
    PwObjectTracker { objects: root.candidateSources }
    PwObjectTracker { objects: root.candidateStreams }

    // Pipewire exposes `nodes` as a constant model with no change signal,
    // so there is nothing to hook here: refreshDisplay() reads the derived
    // sinks/sources/streams properties, which re-evaluate against the
    // current node list on every tick.
    Timer {
        id: refreshTimer
        interval: 500
        repeat: true
        running: root.visible
        triggeredOnStart: true
        onTriggered: root.refreshDisplay()
    }

    // ── Per-app output routing (pactl) ─────────────────────────
    // Quickshell's Pipewire service exposes PwNodeIface.properties as
    // read-only, so a stream's target cannot be written from QML and
    // `pactl move-sink-input` is the only way to move a live stream.
    // Routing state therefore comes from pactl while volume and mute stay on
    // the native Pipewire path.
    property var sinkOptions: []
    property var streamInputs: []
    property var streamRoutes: ({})
    property int expandedStreamId: -1

    function refreshRoutes() {
        sinkProbe.running = true;
        streamProbe.running = true;
    }

    function applySinks(text) {
        sinkOptions = Audio.joinSinks(Audio.parseSinksShort(text), displaySinks);
    }

    function applyStreamInputs(text) {
        streamInputs = Audio.parseSinkInputs(text);
        root.applyRoutes();
    }

    // Called on every display refresh so the current-output chip tracks
    // changes made outside the panel too.
    function applyRoutes() {
        streamRoutes = Audio.streamRouteMap(displayStreams, streamInputs);
    }

    function optionForSinkIndex(index) {
        for (var i = 0; i < sinkOptions.length; i++) {
            if (sinkOptions[i].index === index) return sinkOptions[i];
        }
        return null;
    }

    function routeFor(node) {
        if (!node) return null;
        var r = streamRoutes[node.id];
        return r ? r : null;
    }

    function toggleStreamExpanded(node) {
        if (!node) return;
        expandedStreamId = expandedStreamId === node.id ? -1 : node.id;
    }

    function moveStream(node, option) {
        if (!node || !option || !option.pulseName) return;
        var route = root.routeFor(node);
        // No pactl counterpart means this stream came from a native PipeWire
        // client that pipewire-pulse never saw, so there is nothing to move.
        if (!route) return;

        routeMove.command = [
            "pactl", "move-sink-input",
            String(route.pulseIndex), option.pulseName
        ];
        routeMove.running = true;
        expandedStreamId = -1;
        // Let WirePlumber apply the move before re-reading, otherwise the
        // chip briefly reports the old output.
        routeSettle.restart();
    }

    Process {
        id: sinkProbe
        command: ["pactl", "list", "sinks", "short"]
        stdout: StdioCollector {
            onStreamFinished: root.applySinks(text)
        }
    }

    Process {
        id: streamProbe
        command: ["pactl", "list", "sink-inputs"]
        stdout: StdioCollector {
            onStreamFinished: root.applyStreamInputs(text)
        }
    }

    Process {
        id: routeMove
        command: ["pactl", "move-sink-input", "0", ""]
    }

    Timer {
        id: routeSettle
        interval: 600
        onTriggered: root.refreshRoutes()
    }

    // Routing is polled rather than event-driven because it lives outside
    // Quickshell's Pipewire service. Slower than the row refresh because each
    // tick forks pactl.
    Timer {
        id: routeTimer
        interval: 2500
        repeat: true
        running: root.visible
        triggeredOnStart: true
        onTriggered: root.refreshRoutes()
    }

    // Input level meter.
    PwNodePeakMonitor {
        id: inputPeak
        node: root.inputTarget
        enabled: root.visible && root.hasInputTarget
    }

    // ── Keyboard cursor ────────────────────────────────────────
    // One flat list of every visible row, headers included but not
    // selectable, so navigation is a single index.
    property int cursorIndex: 0

    readonly property var rows: {
        var list = [];
        list.push({ "type": "header", "label": "OUTPUT" });
        list.push({ "type": "channel", "kind": "output" });

        for (var i = 0; i < displaySinks.length; i++)
            list.push({ "type": "device", "kind": "output", "node": displaySinks[i] });

        if (displaySources.length > 0 || hasInput) {
            list.push({ "type": "header", "label": "INPUT" });
            list.push({ "type": "channel", "kind": "input" });
            for (var j = 0; j < displaySources.length; j++)
                list.push({ "type": "device", "kind": "input", "node": displaySources[j] });
        }

        if (displayStreams.length > 0) {
            list.push({ "type": "header", "label": "SOURCES" });
            for (var k = 0; k < displayStreams.length; k++)
                list.push({ "type": "stream", "node": displayStreams[k] });
        }
        return list;
    }

    readonly property var currentRow: {
        var r = rows;
        return cursorIndex >= 0 && cursorIndex < r.length ? r[cursorIndex] : null;
    }

    // Walk in `delta` direction to the next selectable row, skipping
    // headers and the gaps between sections.
    function moveCursor(delta) {
        var n = rows.length;
        if (n === 0) return;
        var i = cursorIndex;
        for (var guard = 0; guard < n; guard++) {
            i += delta;
            if (i < 0) { cursorIndex = 0; return; }
            if (i >= n) { cursorIndex = n - 1; return; }
            if (rows[i].type !== "header") { cursorIndex = i; return; }
        }
    }

    // Device lists change underneath the cursor as devices come and go.
    function clampCursor() {
        if (rows.length === 0) { cursorIndex = 0; return; }
        if (cursorIndex >= rows.length) { cursorIndex = rows.length - 1; return; }
        if (rows[cursorIndex].type === "header") {
            for (var i = cursorIndex; i < rows.length; i++) {
                if (rows[i].type !== "header") { cursorIndex = i; return; }
            }
        }
    }

    // A stream row grows to fit its open output list. Declared here because
    // the delegate's height binding is evaluated in the Repeater's scope,
    // where the inline row ids are not in scope.
    readonly property int streamRowBaseHeight: 76
    readonly property int streamOptionHeight: 26

    function streamRowHeight(row) {
        if (!row || row.type !== "stream" || !row.node) return root.streamRowBaseHeight;
        if (root.expandedStreamId !== row.node.id) return root.streamRowBaseHeight;
        return root.streamRowBaseHeight + root.sinkOptions.length * root.streamOptionHeight + 6;
    }

    // ── Actions ────────────────────────────────────────────────
    function setOutputVolume(v) {
        if (!hasOutput) return;
        sink.audio.volume = Audio.clamp(v, 0, 1);
    }

    function setInputVolume(v) {
        if (!hasInputTarget) return;
        inputTarget.audio.volume = Audio.clamp(v, 0, 1);
    }

    function setStreamVolume(node, v) {
        if (node && node.audio) node.audio.volume = Audio.clamp(v, 0, 1.5);
    }

    function toggleOutputMute() {
        if (hasOutput) sink.audio.muted = !sink.audio.muted;
    }

    function toggleInputMute() {
        if (hasInputTarget) inputTarget.audio.muted = !inputMuted;
    }

    function toggleAllMuted() {
        var mute = root.anyAudible;
        if (hasOutput) sink.audio.muted = mute;
        if (hasInputTarget) inputTarget.audio.muted = mute;
    }

    // Prefer the PipeWire route so the choice survives a WirePlumber restart.
    // omarchy additionally shells out to omarchy-audio-output-set-default,
    // which is not installed here.
    //
    // Caveat: if a DSP sink (EasyEffects, a speaker tuning) is ever made the
    // default, this slider moves that sink's level *into* the processing
    // rather than the physical device. omarchy resolves through the chain to
    // the real sink to avoid that; that resolution is not ported yet. Your
    // current default is a physical ALSA sink, so it does not apply today.
    function setDefaultSink(node) {
        if (node) Pipewire.preferredDefaultAudioSink = node;
    }

    function setDefaultSource(node) {
        if (node) Pipewire.preferredDefaultAudioSource = node;
    }

    // ── Keyboard actions on the cursor row ─────────────────────
    // Left/right only move a volume when the cursor is on a volume control.
    // On a device row they are a no-op rather than silently moving the
    // global slider.
    function adjustCursorVolume(delta) {
        var r = root.currentRow;
        if (!r) return;
        if (r.type === "channel") {
            if (r.kind === "output") root.setOutputVolume(root.outputVolume + delta);
            else root.setInputVolume(root.inputVolume + delta);
        } else if (r.type === "stream" && r.node && r.node.audio) {
            r.node.audio.volume = Audio.clamp(r.node.audio.volume + delta, 0, 1.5);
        }
    }

    function toggleCursorMute() {
        var r = root.currentRow;
        if (!r) return;
        if (r.type === "channel") {
            if (r.kind === "output") root.toggleOutputMute();
            else root.toggleInputMute();
        } else if (r.type === "stream" && r.node && r.node.audio) {
            r.node.audio.muted = !r.node.audio.muted;
        }
    }

    function activateCursor() {
        var r = root.currentRow;
        if (!r) return;
        if (r.type === "channel") {
            if (r.kind === "output") root.toggleOutputMute();
            else root.toggleInputMute();
        } else if (r.type === "device") {
            if (r.kind === "output") root.setDefaultSink(r.node);
            else root.setDefaultSource(r.node);
        } else if (r.type === "stream" && r.node && r.node.audio) {
            r.node.audio.muted = !r.node.audio.muted;
        }
    }

    // ── Overlay window ─────────────────────────────────────────
    PanelWindow {
        visible: root.visible

        anchors {
            top: true
            bottom: true
            left: true
            right: true
        }

        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive

        color: Qt.rgba(0, 0, 0, Theme.dimOpacity)

        Item {
            id: surface
            anchors.fill: parent
            focus: true

            Keys.onPressed: function(event) {
                switch (event.key) {
                case Qt.Key_Escape:
                    root.toggle();
                    break;
                case Qt.Key_Up:
                    root.moveCursor(-1);
                    break;
                case Qt.Key_Down:
                    root.moveCursor(1);
                    break;
                case Qt.Key_Left:
                    root.adjustCursorVolume(-0.05);
                    break;
                case Qt.Key_Right:
                    root.adjustCursorVolume(0.05);
                    break;
                case Qt.Key_M:
                    root.toggleCursorMute();
                    break;
                case Qt.Key_Return:
                case Qt.Key_Enter:
                case Qt.Key_Space:
                    root.activateCursor();
                    break;
                default:
                    return;  // let anything else through unhandled
                }
                event.accepted = true;
            }

            // Clicking the dimmed background closes, matching the launcher.
            MouseArea {
                anchors.fill: parent
                onClicked: root.toggle()
            }

            // ── Sound center card ────────────────────────────
            Rectangle {
                anchors.centerIn: parent
                width: 480
                height: 540
                radius: Theme.radiusCard
                color: Theme.background
                border.color: Theme.border
                border.width: 1

                ColumnLayout {
                    anchors.fill: parent
                    anchors.margins: 16
                    spacing: 12

                    // ── Hero: speaker icon · status · master mute ──
                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 12

                        Text {
                            text: Audio.outputIcon(root.outputVolume, root.outputMuted)
                            color: Theme.foreground
                            font.family: Theme.fontFamily
                            font.pixelSize: Theme.fontLg
                            opacity: root.outputMuted ? 0.5 : 1.0
                        }

                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 2

                            Text {
                                text: "Audio"
                                color: Theme.foreground
                                font.pixelSize: Theme.fontLg
                                font.bold: true
                            }

                            Text {
                                text: Audio.outputVolumeName(root.outputVolume, root.outputMuted).toUpperCase()
                                color: Theme.muted
                                font.pixelSize: Theme.fontXs
                                font.bold: true
                                font.letterSpacing: 1.2
                                elide: Text.ElideRight
                                Layout.fillWidth: true
                            }
                        }

                        // Master on/off for both channels at once.
                        Rectangle {
                            Layout.preferredWidth: 64
                            Layout.preferredHeight: 22
                            radius: height / 2
                            color: root.anyAudible ? Theme.accent : Theme.surface
                            border.color: Theme.surfaceHover
                            border.width: 1

                            Text {
                                anchors.left: parent.left
                                anchors.leftMargin: 8
                                anchors.verticalCenter: parent.verticalCenter
                                text: root.toggleHint
                                color: root.anyAudible ? Theme.accentText : Theme.muted
                                font.pixelSize: Theme.fontXs
                                font.bold: true
                            }

                            Rectangle {
                                anchors.verticalCenter: parent.verticalCenter
                                anchors.right: parent.right
                                anchors.rightMargin: 2
                                width: 18
                                height: 18
                                radius: width / 2
                                color: Theme.foreground
                                x: root.anyAudible ? 0 : parent.width - width - 4

                                Behavior on x {
                                    NumberAnimation { duration: 130; easing.type: Easing.OutCubic }
                                }
                            }

                            MouseArea {
                                anchors.fill: parent
                                cursorShape: Qt.PointingHandCursor
                                onClicked: root.toggleAllMuted()
                            }
                        }
                    }

                    Rectangle {
                        Layout.fillWidth: true
                        height: 1
                        color: Theme.border
                    }

                    // ── Rows ───────────────────────────────────
                    ScrollView {
                        id: scroll
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        clip: true
                        ScrollBar.horizontal.policy: ScrollBar.AlwaysOff
                        ScrollBar.vertical.policy: rowColumn.height > scroll.height
                            ? ScrollBar.AsNeeded
                            : ScrollBar.AlwaysOff

                        Column {
                            id: rowColumn
                            width: scroll.availableWidth
                            spacing: 4

                            Repeater {
                                model: root.rows

                                // One delegate for every row kind; the four
                                // layouts below are switched by visibility so
                                // all their bindings stay live.
                                delegate: Item {
                                    id: row
                                    required property var modelData
                                    required property int index

                                    width: rowColumn.width
                                    height: modelData.type === "header" ? 24
                                          : modelData.type === "channel"
                                            ? (modelData.kind === "output" ? 44 : 60)
                                          : modelData.type === "device" ? 34
                                          : streamRowHeight(modelData)

                                    // Selection comes from the keyboard cursor only,
                                    // never from hover, so mouse and keyboard agree.
                                    readonly property bool selected: root.visible
                                        && index === root.cursorIndex

                                    // Row highlight, shared by every kind.
                                    Rectangle {
                                        anchors.fill: parent
                                        anchors.margins: -2
                                        radius: Theme.radius
                                        color: row.selected ? Theme.surface : "transparent"
                                    }

                                    // ── Header ──────────────────────────
                                    Item {
                                        visible: row.modelData.type === "header"
                                        anchors.fill: parent

                                        Text {
                                            anchors.left: parent.left
                                            anchors.bottom: parent.bottom
                                            text: row.modelData.type === "header"
                                                ? row.modelData.label
                                                : ""
                                            color: Theme.muted
                                            font.pixelSize: Theme.fontXs
                                            font.bold: true
                                            font.letterSpacing: 1.1
                                        }
                                    }

                                    // ── Output volume ───────────────────
                                    Item {
                                        visible: row.modelData.type === "channel"
                                            && row.modelData.kind === "output"
                                        anchors.fill: parent

                                        Text {
                                            anchors.right: parent.right
                                            anchors.top: parent.top
                                            text: Math.round(root.outputVolume * 100) + "%"
                                            color: Theme.muted
                                            font.pixelSize: Theme.fontXs
                                            font.bold: true
                                            opacity: root.outputMuted ? 0.5 : 1.0
                                        }

                                        VolumeSlider {
                                            id: outSlider
                                            anchors.left: parent.left
                                            anchors.right: parent.right
                                            anchors.verticalCenter: parent.verticalCenter
                                            anchors.leftMargin: 6
                                            anchors.rightMargin: 6
                                            value: root.outputVolume
                                            muted: root.outputMuted
                                            enabled: root.hasOutput
                                            onMoved: function(v) { root.setOutputVolume(v) }
                                            onRightClicked: root.toggleOutputMute()
                                        }

                                        // Claims hover without covering the slider.
                                        MouseArea {
                                            anchors.fill: parent
                                            anchors.bottomMargin: 18
                                            hoverEnabled: true
                                            onContainsMouseChanged: if (containsMouse)
                                                root.cursorIndex = row.index
                                        }
                                    }

                                    // ── Input volume + level meter ───────
                                    Item {
                                        visible: row.modelData.type === "channel"
                                            && row.modelData.kind === "input"
                                        anchors.fill: parent

                                        Text {
                                            anchors.right: parent.right
                                            anchors.top: parent.top
                                            text: Math.round(root.inputVolume * 100) + "%"
                                            color: Theme.muted
                                            font.pixelSize: Theme.fontXs
                                            font.bold: true
                                            opacity: root.inputMuted ? 0.5 : 1.0
                                        }

                                        VolumeSlider {
                                            id: inSlider
                                            anchors.left: parent.left
                                            anchors.right: parent.right
                                            anchors.top: parent.top
                                            anchors.topMargin: 16
                                            anchors.leftMargin: 6
                                            anchors.rightMargin: 6
                                            value: root.inputVolume
                                            muted: root.inputMuted
                                            enabled: root.hasInputTarget
                                            onMoved: function(v) { root.setInputVolume(v) }
                                            onRightClicked: root.toggleInputMute()
                                        }

                                        // Live input level, so it is obvious when the
                                        // microphone is actually picking something up.
                                        Rectangle {
                                            id: peakTrack
                                            anchors.left: parent.left
                                            anchors.right: parent.right
                                            anchors.bottom: parent.bottom
                                            anchors.bottomMargin: 8
                                            anchors.leftMargin: 6
                                            anchors.rightMargin: 6
                                            height: 4
                                            radius: 2
                                            color: Theme.surface
                                            opacity: root.inputMuted ? 0.35 : 1.0

                                            Rectangle {
                                                height: parent.height
                                                width: parent.width * Audio.clamp(inputPeak.peak, 0, 1)
                                                radius: parent.radius
                                                color: Theme.accent

                                                Behavior on width {
                                                    NumberAnimation { duration: 70 }
                                                }
                                            }
                                        }

                                        MouseArea {
                                            anchors.fill: parent
                                            anchors.bottomMargin: 20
                                            hoverEnabled: true
                                            onContainsMouseChanged: if (containsMouse)
                                                root.cursorIndex = row.index
                                        }
                                    }

                                    // ── Device row (sink or source) ─────
                                    Item {
                                        id: devRow
                                        visible: row.modelData.type === "device"
                                        anchors.fill: parent

                                        readonly property bool isOutput: row.modelData.kind === "output"
                                        readonly property var node: row.modelData.node
                                        readonly property bool isActive: {
                                            if (!node) return false;
                                            var def = isOutput ? root.sink : root.source;
                                            return !!def && def.id === node.id;
                                        }

                                        Row {
                                            anchors.left: parent.left
                                            anchors.right: parent.right
                                            anchors.verticalCenter: parent.verticalCenter
                                            anchors.leftMargin: 6
                                            anchors.rightMargin: 6
                                            spacing: 8

                                            Text {
                                                text: devRow.isOutput
                                                    ? Audio.sinkGlyph(devRow.node)
                                                    : Audio.sourceGlyph(devRow.node)
                                                color: Theme.foreground
                                                font.family: Theme.fontFamily
                                                font.pixelSize: Theme.fontMd
                                                width: 20
                                                horizontalAlignment: Text.AlignHCenter
                                            }

                                            Text {
                                                text: Audio.nodeLabel(devRow.node)
                                                color: Theme.foreground
                                                font.pixelSize: Theme.fontMd
                                                font.bold: devRow.isActive
                                                elide: Text.ElideRight
                                                width: parent.width - 28
                                            }
                                        }

                                        MouseArea {
                                            anchors.fill: parent
                                            hoverEnabled: true
                                            cursorShape: Qt.PointingHandCursor
                                            onContainsMouseChanged: if (containsMouse)
                                                root.cursorIndex = row.index
                                            onClicked: {
                                                if (devRow.isOutput) root.setDefaultSink(devRow.node);
                                                else root.setDefaultSource(devRow.node);
                                            }
                                        }
                                    }

                                    // ── Per-app stream row ──────────────
                                    Item {
                                        id: strRow
                                        visible: row.modelData.type === "stream"
                                        anchors.fill: parent

                                        readonly property var node: row.modelData.node
                                        readonly property real streamVolume: node && node.audio ? node.audio.volume : 0
                                        readonly property bool streamMuted: node && node.audio ? node.audio.muted : false

                                        // Per-app output routing.
                                        readonly property var route: root.routeFor(strRow.node)
                                        readonly property bool expanded: strRow.node
                                            && root.expandedStreamId === strRow.node.id
                                        readonly property var currentOption: strRow.route
                                            ? root.optionForSinkIndex(strRow.route.sinkIndex)
                                            : null
                                        readonly property string routeLabel: !strRow.route
                                            ? "Unavailable"
                                            : strRow.currentOption
                                                ? (strRow.currentOption.node
                                                    ? Audio.nodeLabel(strRow.currentOption.node)
                                                    : strRow.currentOption.pulseName)
                                                : "Unknown"

                                        Row {
                                            id: strTop
                                            anchors.left: parent.left
                                            anchors.right: parent.right
                                            anchors.top: parent.top
                                            anchors.topMargin: 6
                                            anchors.leftMargin: 6
                                            anchors.rightMargin: 6
                                            spacing: 8

                                            // Per-stream mute, independent of the channel.
                                            Text {
                                                id: strMuteIcon
                                                text: strRow.streamMuted ? "󰝟" : "󰕾"
                                                color: Theme.foreground
                                                font.family: Theme.fontFamily
                                                font.pixelSize: Theme.fontMd
                                                width: 20
                                                horizontalAlignment: Text.AlignHCenter
                                                opacity: strRow.streamMuted ? 0.5 : 1.0

                                                MouseArea {
                                                    anchors.fill: parent
                                                    cursorShape: Qt.PointingHandCursor
                                                    onClicked: if (strRow.node && strRow.node.audio)
                                                        strRow.node.audio.muted = !strRow.node.audio.muted
                                                }
                                            }

                                            Text {
                                                text: Audio.streamLabel(
                                                    strRow.node,
                                                    root.mprisPlayers,
                                                    root.displayStreams)
                                                color: Theme.foreground
                                                font.pixelSize: Theme.fontMd
                                                elide: Text.ElideRight
                                                width: strTop.width - strMuteIcon.width - strPct.width - 16
                                            }

                                            Text {
                                                id: strPct
                                                text: Math.round(strRow.streamVolume * 100) + "%"
                                                color: Theme.muted
                                                font.pixelSize: Theme.fontXs
                                                font.bold: true
                                                width: 36
                                                horizontalAlignment: Text.AlignRight
                                                opacity: strRow.streamMuted ? 0.5 : 1.0
                                            }
                                        }

                                        VolumeSlider {
                                            anchors.left: parent.left
                                            anchors.right: parent.right
                                            anchors.bottom: parent.bottom
                                            anchors.bottomMargin: 6
                                            anchors.leftMargin: 6
                                            anchors.rightMargin: 6
                                            // Streams accept over-unity gain, which is
                                            // why this ceiling sits above the others.
                                            maximum: 1.5
                                            value: strRow.streamVolume
                                            muted: strRow.streamMuted
                                            onMoved: function(v) { root.setStreamVolume(strRow.node, v) }
                                            onRightClicked: if (strRow.node && strRow.node.audio)
                                                strRow.node.audio.muted = !strRow.node.audio.muted
                                        }

                                        // Hover only: the slider and mute icon above
                                        // keep their own clicks.
                                        MouseArea {
                                            anchors.fill: parent
                                            hoverEnabled: true
                                            acceptedButtons: Qt.NoButton
                                            onContainsMouseChanged: if (containsMouse)
                                                root.cursorIndex = row.index
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}
