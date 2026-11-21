import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import qs.Commons as Commons
import qs.Commons
import qs.Ui
import "plugin" as Storage

// Showcase host for the README captures. It shows the unmodified plugin
// (BarWidget.qml -> Panel.qml) on a one-widget demo bar, drives it through the
// public panel functions and asks grim for a full-screen capture after each
// step. capture.sh runs it inside a sandbox whose /home only holds a synthetic
// /home/demo and whose findmnt/du print synthetic data (tools/showcase/data).
ShellRoot {
  id: host

  readonly property string outDir: Quickshell.env("STORAGE_DEMO_OUT")

  // Opaque backdrop so captures contain only the demo surfaces.
  PanelWindow {
    id: backdrop
    anchors { top: true; bottom: true; left: true; right: true }
    exclusionMode: ExclusionMode.Ignore
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.namespace: "omarchy-storage-showcase-backdrop"
    color: Commons.Color.background
  }

  PanelWindow {
    id: barWindow
    anchors { top: true; left: true; right: true }
    implicitHeight: Style.bar.sizeHorizontal
    exclusionMode: ExclusionMode.Ignore
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.namespace: "omarchy-storage-showcase-bar"
    color: Commons.Color.bar.background

    PluginBarApi {
      id: api
      pluginId: "dev.kern.storage"
      moduleName: "dev.kern.storage"
      foreground: Commons.Color.bar.text
      barForeground: Commons.Color.bar.text
      background: Commons.Color.bar.background
      urgent: Commons.Color.bar.active
      fontFamily: Style.font.family
      position: "top"
      vertical: false
      barSize: Style.bar.sizeHorizontal
    }

    Storage.BarWidget {
      id: widget
      anchors.centerIn: parent
      height: parent.height
      bar: api
      settings: ({ mount: "/", refreshSeconds: 60, investigatePath: "~" })
    }
  }

  function panel() {
    for (var i = 0; i < widget.data.length; i++)
      if (widget.data[i] && widget.data[i].item && typeof widget.data[i].item.investigate === "function")
        return widget.data[i].item
    return null
  }

  Process { id: grim }
  function shoot(name) {
    grim.command = ["grim", outDir + "/" + name + ".png"]
    grim.running = true
    console.log("SHOT " + name)
  }

  property var steps: [
    { wait: 1800, act: function() {} },
    { wait: 900, act: function() { widget.open() } },
    { wait: 700, act: function() { shoot("raw-glance") } },
    { wait: 1500, act: function() { panel().investigate(panel().expandedStartPath()) } },
    { wait: 1300, act: function() { shoot("raw-investigate") } },
    { wait: 1500, act: function() { panel().investigate("/home/demo/Games") } },
    { wait: 1300, act: function() { shoot("raw-drilldown") } },
    { wait: 600, act: function() { widget.close() } },
    { wait: 1200, act: function() { widget.settings = ({ mount: "/mnt/Archive", refreshSeconds: 60, investigatePath: "~" }) } },
    { wait: 900, act: function() { widget.open() } },
    { wait: 700, act: function() { shoot("raw-warning") } },
    { wait: 600, act: function() { widget.close() } },
    { wait: 300, act: function() { Qt.exit(0) } }
  ]
  property int stepIndex: 0
  Timer {
    id: sequencer
    running: true
    interval: host.steps[0].wait
    onTriggered: {
      host.steps[host.stepIndex].act()
      host.stepIndex++
      if (host.stepIndex < host.steps.length) {
        interval = host.steps[host.stepIndex].wait
        restart()
      }
    }
  }
}
