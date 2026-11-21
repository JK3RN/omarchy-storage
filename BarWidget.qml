import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui

BarWidget {
  id: root
  moduleName: "dev.kern.storage"

  readonly property bool opened: panelLoader.item ? panelLoader.item.opened === true : false
  readonly property bool popoutSwitchClosing: panelLoader.item ? panelLoader.item.popoutSwitchClosing === true : false

  function open() { if (panelLoader.item) panelLoader.item.open() }
  function close() { if (panelLoader.item) panelLoader.item.close() }
  function toggle() { if (panelLoader.item) panelLoader.item.toggle() }
  function closeForPopoutSwitch() { if (panelLoader.item) panelLoader.item.closeForPopoutSwitch() }
  function refresh() { storage.refresh() }

  function injectPanel() {
    if (!panelLoader.item) return
    panelLoader.item.bar = root.bar
    panelLoader.item.settings = root.settings
    panelLoader.item.anchorItem = button
    panelLoader.item.hostWidget = root
    panelLoader.item.storage = storage
  }

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight
  onBarChanged: injectPanel()
  onSettingsChanged: {
    storage.primaryTarget = String(setting("mount", "/"))
    storage.refreshSeconds = Number(setting("refreshSeconds", 60))
    injectPanel()
    storage.refresh()
  }

  StorageState {
    id: storage
    primaryTarget: String(root.setting("mount", "/"))
    refreshSeconds: Number(root.setting("refreshSeconds", 60))
  }

  Loader {
    id: panelLoader
    active: true
    source: Qt.resolvedUrl("Panel.qml")
    visible: false
    onLoaded: { root.injectPanel(); Qt.callLater(root.injectPanel) }
  }

  IpcHandler {
    target: "dev.kern.storage"
    function open(): void { root.open() }
    function close(): void { root.close() }
    function show(): void { root.open() }
    function hide(): void { root.close() }
    function toggle(): void { root.toggle() }
    function refresh(): void { root.refresh() }
  }

  WidgetButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    labelVisible: false
    hasVisualContent: true
    fixedWidth: vertical ? -1 : Style.bar.statusSlot
    fixedHeight: vertical ? Style.bar.statusSlot : -1
    active: storage.percent >= 90
    tooltipText: storage.error !== "" ? "Storage · " + storage.error
      : "Storage · " + storage.percent + "% used"
    onPressed: function(code) {
      if (code === Qt.MiddleButton) storage.refresh()
      else if (code === Qt.LeftButton) root.toggle()
    }

    StorageGlyph {
      anchors.centerIn: parent
      width: Style.bar.iconCanvas
      height: width
      fraction: storage.percent / 100
      foreground: button.foreground
      urgent: button.activeColor
    }
  }
}
