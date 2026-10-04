import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Hyprland
import "."

// Launcher: a full-screen overlay that provides a searchable
// application menu.
//
// How it works:
//   1. On toggle(), it spawns a background process that scans
//      .desktop files in /usr/share/applications/ and
//      ~/.local/share/applications/ for app names and IDs.
//   2. Results are collected into a ListModel (appModel) and
//      displayed in a ListView inside a centered dialog card.
//   3. The search field filters apps in real-time by name.
//   4. Running Hyprland windows are tracked so the launcher
//      can "switch to" an already-open app instead of
//      launching a duplicate.
Scope {
    id: root

    property bool visible: false

    // ── Toggle visibility ──────────────────────────────────────
    // Opens or closes the launcher. When opening, it clears the
    // previous app list, re-scans .desktop files, focuses the
    // search field, and resets the filter.
    function toggle() {
        root.visible = !root.visible;
        if (root.visible) {
            appModel.clear();
            appFetcher.running = true;
            searchField.forceActiveFocus();
            searchField.text = "";
            root.filterApps("");
        }
    }

    // ── Running-window detection ───────────────────────────────
    // Checks if a Hyprland toplevel window matches an app by
    // comparing its Wayland app-id or X11 class against the
    // app's desktop file basename (execName).
    function windowIsApp(toplevel, execName) {
        var name = execName.toLowerCase();
        var appId = (toplevel.wayland?.appId || "").toLowerCase();
        var cls = (toplevel.lastIpcObject?.class || "").toLowerCase();
        var iCls = (toplevel.lastIpcObject?.initialClass || "").toLowerCase();
        return name === appId || name === cls || name === iCls;
    }

    // Returns all running Hyprland windows that match the given
    // app, sorted by most-recently-focused first.
    function runningWindows(execName) {
        var matches = [];
        var wins = Hyprland.toplevels.values || [];
        for (var i = 0; i < wins.length; i++) {
            if (root.windowIsApp(wins[i], execName)) matches.push(wins[i]);
        }
        matches.sort(function (a, b) {
            return (a.lastIpcObject?.focusHistoryID ?? 0) - (b.lastIpcObject?.focusHistoryID ?? 0);
        });
        return matches;
    }

    // Re-checks every app in the model to update its runningCount.
    // If any count changed and the launcher is open, re-filters
    // the list so "Switch to App" badges update in real-time.
    function refreshRunning() {
        var changed = false;
        for (var i = 0; i < appModel.count; i++) {
            var n = root.runningWindows(appModel.get(i).execName).length;
            if (appModel.get(i).runningCount !== n) {
                appModel.setProperty(i, "runningCount", n);
                changed = true;
            }
        }
        if (changed && root.visible) root.filterApps(searchField.text);
    }

    // Re-fetch running windows whenever Hyprland's toplevel list
    // changes (window opened, closed, or focused).
    Connections {
        target: Hyprland.toplevels
        function onValuesChanged() { root.refreshRunning() }
    }

    // Periodic fallback: re-check running windows every 2 seconds
    // in case a toplevel change event was missed.
    Timer {
        interval: 2000
        running: true
        repeat: true
        onTriggered: root.refreshRunning()
    }

    // ── App scanner ────────────────────────────────────────────
    // A shell process that iterates over all .desktop files in
    // the standard XDG application directories. For each file it
    // extracts:
    //   - id:      the .desktop filename without extension
    //   - name:    the human-readable Name= field
    //   - multi:   1 if the app supports "New Window" actions
    //              and isn't marked SingleMainWindow
    //
    // Output format: "id|name|multi" (one line per app).
    Process {
        id: appFetcher
        command: ["sh", "-c", "for f in /usr/share/applications/*.desktop ~/.local/share/applications/*.desktop; do [ -f \"$f\" ] || continue; id=$(basename \"$f\" .desktop); name=$(grep -m1 '^Name=' \"$f\" | cut -d= -f2-); [ -n \"$name\" ] || continue; multi=$(grep -io '^\\[Desktop Action[^]]*\\]' \"$f\" | sed 's/^\\[Desktop Action *//I' | cut -d] -f1 | grep -qiE '^(new|new[-_ ]?window|newwindow)$' && echo 1 || echo 0); grep -qiE '^(SingleMainWindow|X-GNOME-SingleWindow)=true' \"$f\" && multi=0; echo \"$id|$name|$multi\"; done 2>/dev/null"]

        stdout: SplitParser {
            onRead: data => {
                var parts = data.split('|');
                if (parts.length === 3 && !hasApp(parts[1])) {
                    appModel.append({ "appName": parts[1].trim(), "execName": parts[0].trim(), "multiInstance": parts[2].trim() === "1", "runningCount": 0 });
                    root.refreshRunning();
                    root.filterApps(searchField.text);
                }
            }
        }
    }

    // Master list of all installed applications.
    ListModel {
        id: appModel
    }

    // Checks if an app with the given name is already in the model
    // (to avoid duplicates from duplicate .desktop files).
    function hasApp(name) {
        for (var i = 0; i < appModel.count; i++) {
            if (appModel.get(i).appName === name) return true;
        }
        return false;
    }

    // ── Filtered list model ────────────────────────────────────
    // Holds the apps matching the current search query. For apps
    // that are running and support multiple instances, an extra
    // "New Window" entry is appended so the user can open a new
    // instance instead of switching to the existing one.
    ListModel {
        id: filteredModel
    }

    // Filters apps by a search query. For apps that are running
    // and support multiple instances, an extra "New Window" entry
    // is appended so the user can open a new instance instead of
    // switching to the existing one.
    function filterApps(query) {
        filteredModel.clear();
        var q = query.toLowerCase();
        // Apps: match by app name. Running + multi-instance apps
        // get an extra "New Window" entry.
        for (var i = 0; i < appModel.count; i++) {
            var item = appModel.get(i);
            if (item.appName.toLowerCase().includes(q)) {
                filteredModel.append({
                    "appName": item.appName,
                    "execName": item.execName,
                    "multiInstance": item.multiInstance,
                    "runningCount": item.runningCount,
                    "newWindow": false
                });
                if (item.runningCount > 0 && item.multiInstance) {
                    filteredModel.append({
                        "appName": item.appName,
                        "execName": item.execName,
                        "multiInstance": item.multiInstance,
                        "runningCount": item.runningCount,
                        "newWindow": true
                    });
                }
            }
        }
        appList.currentIndex = 0;
    }

    // ── Overlay window ─────────────────────────────────────────
    // A full-screen panel on the Overlay layer. This sits above
    // all windows and grabs exclusive keyboard focus so the
    // search field receives keystrokes immediately.
    PanelWindow {
        id: launcherWindow
        visible: root.visible

        // Covers the entire screen on all edges.
        anchors {
            top: true
            bottom: true
            left: true
            right: true
        }

        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive

        // Semi-transparent black dim behind the launcher card.
        color: Qt.rgba(0, 0, 0, Theme.dimOpacity)

        Item {
            anchors.fill: parent

            // Escape key closes the launcher.
            Keys.onEscapePressed: root.toggle()

            // Clicking the dimmed background also closes it.
            MouseArea {
                anchors.fill: parent
                onClicked: root.toggle()
            }

            // ── Launcher dialog card ───────────────────────────
            // A centered rectangle containing the search field
            // and the filtered app list.
            Rectangle {
                anchors.centerIn: parent
                width: 500
                height: 400
                radius: Theme.radiusCard
                color: Theme.background
                border.color: Theme.border
                border.width: 1

                ColumnLayout {
                    anchors.fill: parent
                    anchors.margins: 16
                    spacing: 12

                    // ── Search field ───────────────────────────
                    // Text input for filtering apps.
                    // Arrow keys navigate the list; Enter launches
                    // the currently highlighted item.
                    TextField {
                        id: searchField
                        Layout.fillWidth: true
                        placeholderText: "Search..."
                        placeholderTextColor: Theme.muted
                        color: Theme.foreground
                        font.pixelSize: Theme.fontLg

                        background: Rectangle {
                            color: "transparent"
                            radius: Theme.radius
                        }

                        onTextChanged: root.filterApps(text)

                        Keys.onDownPressed: appList.incrementCurrentIndex()
                        Keys.onUpPressed: appList.decrementCurrentIndex()
                        Keys.onEscapePressed: root.toggle()
                        Keys.onReturnPressed: {
                            if (appList.currentItem) {
                                appList.currentItem.launch();
                            }
                        }
                    }

                    // ── App list ──────────────────────────────
                    // Displays filtered results. Each delegate is a
                    // clickable row with the app name and an optional
                    // badge (Switch to App or New Window).
                    ListView {
                        id: appList
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        clip: true
                        model: filteredModel
                        spacing: 4

                        delegate: Rectangle {
                            id: delegateItem
                            width: appList.width
                            height: 40
                            radius: Theme.radius
                            color: ListView.isCurrentItem ? Theme.surfaceHover : "transparent"

                            // Launch behavior depends on item state:
                            // - Running multi-instance apps: open new window.
                            // - Running single-instance apps: focus existing window.
                            // - Not running apps: launch via gtk-launch.
                            function launch() {
                                if (model.newWindow) {
                                    launcherProcess.command = [
                                        "sh", "-c",
                                        "nohup gtk-launch '" + model.execName + "' > /dev/null 2>&1 &"
                                    ];
                                    launcherProcess.running = true;
                                } else {
                                    var wins = root.runningWindows(model.execName);
                                    if (wins.length > 0) {
                                        Hyprland.dispatch('hl.dsp.focus({ window = "address:0x' + wins[0].address + '" })');
                                    } else {
                                        launcherProcess.command = [
                                            "sh", "-c",
                                            "nohup gtk-launch '" + model.execName + "' > /dev/null 2>&1 &"
                                        ];
                                        launcherProcess.running = true;
                                    }
                                }
                                root.toggle();
                            }
                            MouseArea {
                                anchors.fill: parent
                                hoverEnabled: true
                                onEntered: appList.currentIndex = index
                                onClicked: delegateItem.launch()
                            }

                            RowLayout {
                                anchors.fill: parent
                                anchors.margins: 8
                                spacing: 12

                                // App name.
                                Text {
                                    text: model.appName
                                    color: Theme.foreground
                                    font.pixelSize: Theme.fontMd
                                    Layout.fillWidth: true
                                }

                                // ── Action badge ────────────────
                                // A small pill-shaped label showing
                                // the available action for this item.
                                Rectangle {
                                    visible: model.newWindow || model.runningCount > 0
                                    height: 22
                                    Layout.preferredWidth: switchLabel.implicitWidth + 16
                                    radius: 11
                                    color: Theme.surface
                                    border.color: Theme.surfaceHover
                                    border.width: 1

                                    Text {
                                        id: switchLabel
                                        anchors.centerIn: parent
                                        text: model.newWindow ? "New Window" : "Switch to App"
                                        color: model.newWindow ? Theme.warning : Theme.success
                                        font.pixelSize: Theme.fontXs
                                        font.bold: true
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    // Process used to launch apps via gtk-launch.
    Process {
        id: launcherProcess
    }
}
