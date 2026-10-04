import QtQuick
import Quickshell
import Quickshell.Io
import "components"
import "components/AudioModel.js" as Audio0

ShellRoot {
  id: root
  Bar {
    soundCenter: audioCenter
  }
  Launcher {
    id: appLauncher
  }
  SoundCenter {
    id: audioCenter
  }

  IpcHandler {
    target: "toggleLauncher"
    function toggle(): void {
      appLauncher.toggle();
    }
  }

  IpcHandler {
    target: "toggleSoundCenter"
    function toggle(): void {
      audioCenter.toggle();
    }
  }

  IpcHandler {
    target: "probeTypes"
    function dump(): void {
      var ns = audioCenter.nodes;
      for (var i = 0; i < ns.length; i++) {
        var n = ns[i];
        if (!n) continue;
        var p = Audio0.nodeProps(n);
        console.log("PROBE name=" + n.name
          + " type=[" + String(n.type) + "]"
          + " ready=" + n.ready
          + " media.class=[" + (p["media.class"] || "-") + "]"
          + " app.icon=[" + (p["application.icon-name"] || "-") + "]");
      }
    }
  }
}
