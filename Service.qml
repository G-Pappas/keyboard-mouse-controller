import QtQuick
import Quickshell
import Quickshell.Io

// Hooks keymouse.lua into the Hyprland config the first time the plugin loads
// (setup.sh does nothing on later loads), so installing the plugin is enough.
Item {
  id: root

  // Injected by omarchy-shell.
  property var shell: null

  function bundledPath(name) {
    return decodeURIComponent(String(Qt.resolvedUrl(name)).replace(/^file:\/\//, ""))
  }

  Process {
    id: setup
    command: ["bash", root.bundledPath("setup.sh")]
    stdout: StdioCollector {
      onStreamFinished: {
        var line = text.trim()
        if (line !== "") console.log("keymouse: " + line)
      }
    }
  }

  Component.onCompleted: setup.running = true
}
