import QtQuick
import Quickshell.Io
import "Model.js" as Model

QtObject {
  id: root

  property string primaryTarget: "/"
  property int refreshSeconds: 60
  property var primary: null
  property var mounts: []
  property string error: ""
  property bool loading: false
  readonly property int percent: primary ? primary.percent : 0

  function refresh() {
    if (metadataProcess.running) return
    root.loading = true
    metadataProcess.running = true
  }

  function consume(raw) {
    var result = Model.parseMetadata(raw, root.primaryTarget)
    root.primary = result.primary
    root.mounts = result.mounts
    root.error = result.error
  }

  property Timer refreshTimer: Timer {
    interval: Math.max(15, root.refreshSeconds) * 1000
    repeat: true
    running: true
    onTriggered: root.refresh()
  }

  property Process metadataProcess: Process {
    id: metadataProcess
    command: ["findmnt", "--json", "--list", "--bytes", "--real",
              "--output", "TARGET,SOURCE,FSTYPE,SIZE,USED,AVAIL"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.consume(text)
    }
    onExited: function(exitCode) {
      root.loading = false
      if (exitCode !== 0 && !root.primary) root.error = "findmnt failed (exit " + exitCode + ")"
    }
  }

  Component.onCompleted: refresh()
}
