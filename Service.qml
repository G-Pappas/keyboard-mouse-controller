import QtQuick
import Quickshell
import Quickshell.Io

// Asks (once, by notification) before hooking keymouse.lua into the Hyprland
// config. Nothing is changed unless the user accepts or runs setup.sh apply.
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
