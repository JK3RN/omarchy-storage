import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Commons as Commons
import qs.Ui
import "Model.js" as Model

Panel {
  id: root
  moduleName: "dev.kern.storage"
  ipcTarget: "dev.kern.storage"
  manageIpc: false

  property var anchorItem: null
  property var hostWidget: null
  property var storage: null
  readonly property var barIdentity: hostWidget || root
  readonly property color foreground: bar ? bar.foreground : Commons.Color.foreground
  readonly property string fontFamily: bar ? bar.fontFamily : Style.font.family
  readonly property string pluginRoot: (Quickshell.env("HOME") || "") + "/.config/omarchy/plugins/dev.kern.storage"

  property bool investigating: false
  property bool scanning: false
  property bool expectedStop: false
  property string pendingPath: ""
  property string currentPath: ""
  property string scanError: ""
  property string scanStderr: ""
  property var entries: []
  property real scanTotal: 0

  function expandedStartPath() {
    var configured = String(setting("investigatePath", "~"))
    var home = Quickshell.env("HOME") || "/home"
    if (configured === "~") return home
    if (configured.indexOf("~/") === 0) return home + configured.slice(1)
    return configured.charAt(0) === "/" ? configured : home + "/" + configured
  }

  function open() {
    if (storage) storage.refresh()
    root.controller.show()
    Qt.callLater(function() { if (root.opened) root.setCenterHoverRevealSuppressed(true) })
  }

  function close() {
    root.stopScan()
    root.investigating = false
    root.setCenterHoverRevealSuppressed(false)
    root.controller.hide()
  }

  function toggle() { if (root.opened) root.close(); else root.open() }
  function closeForPopoutSwitch() { root.close() }
  function setCenterHoverRevealSuppressed(value) {
    if (bar && typeof bar.setCenterHoverRevealSuppressed === "function") bar.setCenterHoverRevealSuppressed(value)
  }
  function switchPanel(direction) {
    if (bar && typeof bar.switchPanelFrom === "function") return bar.switchPanelFrom(barIdentity, direction)
    return false
  }

  function investigate(path) {
    var target = path || expandedStartPath()
    root.investigating = true
    root.currentPath = target
    root.entries = []
    root.scanTotal = 0
    root.scanError = ""
    root.scanStderr = ""
    if (scanProcess.running) {
      root.pendingPath = target
      root.expectedStop = true
      scanProcess.running = false
    } else root.startScan(target)
  }

  function startScan(path) {
    root.pendingPath = ""
    root.currentPath = path
    scanProcess.command = [root.pluginRoot + "/scripts/storage-scan", path]
    root.scanning = true
    scanProcess.running = true
  }

  function stopScan() {
    root.pendingPath = ""
    if (scanProcess.running) {
      root.expectedStop = true
      scanProcess.running = false
    }
    root.scanning = false
  }

  function goBack() {
    if (!investigating) return
    var start = expandedStartPath()
    if (currentPath === start) { investigating = false; stopScan(); return }
    investigate(Model.parentPath(currentPath))
  }

  Process {
    id: scanProcess
    command: []
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var result = Model.parseScan(text, root.currentPath)
        root.entries = result.entries
        root.scanTotal = result.total
      }
    }
    stderr: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.scanStderr = String(text || "").trim()
    }
    onExited: function(exitCode) {
      if (root.pendingPath !== "") {
        var next = root.pendingPath
        root.pendingPath = ""
        root.expectedStop = false
        Qt.callLater(function() { root.startScan(next) })
        return
      }
      root.scanning = false
      if (root.expectedStop) { root.expectedStop = false; return }
      if (exitCode !== 0) root.scanError = root.scanStderr || "Analysis failed (exit " + exitCode + ")"
    }
  }

  KeyboardPanel {
    id: popup
    anchorItem: root.anchorItem
    owner: root.barIdentity
    bar: root.bar
    open: root.opened
    centerOnBar: true
    focusTarget: keyCatcher
    contentWidth: popup.fittedContentWidth(Style.space(430))
    contentHeight: popup.fittedContentHeight(content.implicitHeight)

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      onCloseRequested: root.close()
      onTabRequested: function(direction) { root.switchPanel(direction) }

      Flickable {
        anchors.fill: parent
        contentWidth: width
        contentHeight: content.implicitHeight
        clip: true
        boundsBehavior: Flickable.StopAtBounds

        Column {
          id: content
          width: parent.width
          spacing: Style.space(12)

          Row {
            width: parent.width
            spacing: Style.space(14)

            StorageGlyph {
              width: Style.space(64)
              height: width
              fraction: root.storage ? root.storage.percent / 100 : 0
              foreground: root.foreground
              urgent: Commons.Color.urgent
            }

            Column {
              anchors.verticalCenter: parent.verticalCenter
              spacing: Style.space(2)
              Text {
                text: root.investigating ? "INVESTIGATE STORAGE" : "STORAGE"
                color: Qt.darker(root.foreground, 1.4)
                font.family: root.fontFamily
                font.pixelSize: Style.font.caption
                font.bold: true
              }
              Text {
                text: root.storage ? root.storage.percent + "%" : "—"
                color: root.foreground
                font.family: root.fontFamily
                font.pixelSize: Style.font.displayLarge
                font.bold: true
              }
              Text {
                text: root.storage && root.storage.primary
                  ? Model.formatBytes(root.storage.primary.used) + " / " + Model.formatBytes(root.storage.primary.size)
                  : "Waiting for filesystem metadata…"
                color: Qt.darker(root.foreground, 1.4)
                font.family: root.fontFamily
                font.pixelSize: Style.font.bodySmall
              }
            }
          }

          PanelSeparator { width: parent.width }

          Column {
            visible: !root.investigating
            width: parent.width
            spacing: Style.space(9)

            Repeater {
              model: root.storage && root.storage.primary ? [
                { label: "Used", value: Model.formatBytes(root.storage.primary.used) },
                { label: "Free", value: Model.formatBytes(root.storage.primary.avail) },
                { label: "Total", value: Model.formatBytes(root.storage.primary.size) }
              ] : []
              Row {
                required property var modelData
                width: parent.width
                Text { text: modelData.label; width: parent.width * 0.55; color: root.foreground; font.family: root.fontFamily; font.pixelSize: Style.font.body }
                Text { text: modelData.value; width: parent.width * 0.45; horizontalAlignment: Text.AlignRight; color: root.foreground; font.family: root.fontFamily; font.pixelSize: Style.font.body; font.bold: true }
              }
            }

            PanelSectionHeader { text: "FILE SYSTEMS"; foreground: root.foreground; fontFamily: root.fontFamily }

            Repeater {
              model: root.storage ? root.storage.mounts : []
              Column {
                required property var modelData
                width: parent.width
                spacing: Style.space(3)
                Row {
                  width: parent.width
                  Text { text: modelData.target; width: parent.width * 0.68; elide: Text.ElideMiddle; color: root.foreground; font.family: root.fontFamily; font.pixelSize: Style.font.bodySmall }
                  Text { text: modelData.percent + "%"; width: parent.width * 0.32; horizontalAlignment: Text.AlignRight; color: modelData.percent >= 90 ? Commons.Color.urgent : root.foreground; font.family: root.fontFamily; font.pixelSize: Style.font.bodySmall; font.bold: true }
                }
                Rectangle {
                  width: parent.width
                  height: Math.max(2, Style.space(3))
                  radius: height / 2
                  color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.16)
                  Rectangle { width: parent.width * modelData.percent / 100; height: parent.height; radius: parent.radius; color: modelData.percent >= 90 ? Commons.Color.urgent : root.foreground }
                }
              }
            }

            Text {
              visible: root.storage && root.storage.error !== ""
              width: parent.width
              wrapMode: Text.WordWrap
              text: root.storage ? root.storage.error : ""
              color: Commons.Color.urgent
              font.family: root.fontFamily
              font.pixelSize: Style.font.bodySmall
            }

            Rectangle {
              width: parent.width
              height: Style.space(38)
              radius: Style.cornerRadius
              color: investigateMouse.containsMouse ? Style.hoverFillFor(root.foreground, Commons.Color.accent) : Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.08)
              Text { anchors.centerIn: parent; text: "Investigate Storage  ›"; color: root.foreground; font.family: root.fontFamily; font.pixelSize: Style.font.body; font.bold: true }
              MouseArea { id: investigateMouse; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: root.investigate(root.expandedStartPath()) }
            }
          }

          Column {
            visible: root.investigating
            width: parent.width
            spacing: Style.space(8)

            Row {
              width: parent.width
              spacing: Style.space(8)
              PanelActionButton { iconText: "󰁍"; tooltipText: "Back"; foreground: root.foreground; fontFamily: root.fontFamily; onClicked: root.goBack() }
              Text { width: parent.width - Style.space(68); anchors.verticalCenter: parent.verticalCenter; text: root.currentPath; elide: Text.ElideMiddle; color: root.foreground; font.family: root.fontFamily; font.pixelSize: Style.font.bodySmall; font.bold: true }
              PanelActionButton { iconText: root.scanning ? "󰅖" : "󰑐"; tooltipText: root.scanning ? "Cancel analysis" : "Scan again"; foreground: root.foreground; fontFamily: root.fontFamily; onClicked: { if (root.scanning) root.stopScan(); else root.investigate(root.currentPath) } }
            }

            Text {
              visible: root.scanning
              text: "Analyzing this directory…"
              color: Qt.darker(root.foreground, 1.4)
              font.family: root.fontFamily
              font.pixelSize: Style.font.bodySmall
            }

            Repeater {
              model: root.entries
              Rectangle {
                required property var modelData
                width: parent.width
                height: Style.space(48)
                radius: Style.cornerRadius
                color: modelData.path !== "" && entryMouse.containsMouse ? Style.hoverFillFor(root.foreground, Commons.Color.accent) : "transparent"
                Column {
                  anchors.fill: parent
                  anchors.margins: Style.space(7)
                  Row {
                    width: parent.width
                    Text { width: parent.width * 0.68; text: modelData.name; elide: Text.ElideMiddle; color: root.foreground; font.family: root.fontFamily; font.pixelSize: Style.font.bodySmall; font.bold: true }
                    Text { width: parent.width * 0.32; text: Model.formatBytes(modelData.size); horizontalAlignment: Text.AlignRight; color: root.foreground; font.family: root.fontFamily; font.pixelSize: Style.font.bodySmall }
                  }
                  Rectangle {
                    width: parent.width
                    height: Math.max(2, Style.space(3))
                    color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.14)
                    Rectangle { width: parent.width * modelData.percent / 100; height: parent.height; color: root.foreground }
                  }
                }
                MouseArea { id: entryMouse; anchors.fill: parent; enabled: modelData.path !== ""; hoverEnabled: enabled; cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor; onClicked: root.investigate(modelData.path) }
              }
            }

            Text {
              visible: !root.scanning && root.entries.length === 0 && root.scanError === ""
              text: "No readable child directories found."
              color: Qt.darker(root.foreground, 1.4)
              font.family: root.fontFamily
              font.pixelSize: Style.font.bodySmall
            }
            Text {
              visible: root.scanError !== ""
              width: parent.width
              wrapMode: Text.WordWrap
              text: root.scanError
              color: Commons.Color.urgent
              font.family: root.fontFamily
              font.pixelSize: Style.font.bodySmall
            }
          }
        }
      }
    }
  }
}
