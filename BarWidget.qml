import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui

// Bar label for the opencode-remote widget. The popup lives in Panel.qml and
// is loaded here the same way the built-in clock loads its calendar: this
// widget owns the bar slot, the panel owns the UI and the backend.
BarWidget {
  id: root
  moduleName: "io.github.ofrades.opencode-remote"

  readonly property int totalCount: panelLoader.item ? panelLoader.item.totalCount : 0
  readonly property int hostCount: panelLoader.item ? panelLoader.item.hostCount : 0
  readonly property bool healthy: panelLoader.item ? panelLoader.item.healthy : false
  readonly property string displayText: totalCount > 0 ? ("󰆍 " + totalCount) : "󰆍"

  function refresh() {
    if (panelLoader.item && panelLoader.item.refresh) panelLoader.item.refresh()
  }

  // ---- Popup. Shape contract for shell.summon/hide/toggle routing:
  //      Bar.findPanelWidget requires open/close/opened on the
  //      bar-widget root.
  readonly property bool opened: panelLoader.item ? panelLoader.item.opened === true : false

  function open() {
    if (panelLoader.item) panelLoader.item.open()
  }

  function close() {
    if (panelLoader.item) panelLoader.item.close()
  }

  function togglePanel() {
    if (panelLoader.item) panelLoader.item.toggle()
  }

  readonly property bool popoutSwitchClosing: panelLoader.item ? panelLoader.item.popoutSwitchClosing === true : false

  function closeForPopoutSwitch() {
    if (panelLoader.item) panelLoader.item.closeForPopoutSwitch()
  }

  function injectPanel() {
    var target = panelLoader.item
    if (!target) return
    if ("bar" in target) target.bar = root.bar
    if ("settings" in target) target.settings = root.settings
    if ("anchorItem" in target) target.anchorItem = button
    if ("hostWidget" in target) target.hostWidget = root
  }

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  onBarChanged: injectPanel()
  onSettingsChanged: injectPanel()

  Loader {
    id: panelLoader
    active: true
    source: Qt.resolvedUrl("Panel.qml")
    visible: false
    onLoaded: {
      root.injectPanel()
      Qt.callLater(root.injectPanel)
    }
  }

  IpcHandler {
    target: "io.github.ofrades.opencode-remote"

    function refresh(): void { root.refresh() }
    function open(): void { root.open() }
    function close(): void { root.close() }
    function show(): void { root.open() }
    function hide(): void { root.close() }
    function toggle(): void { root.togglePanel() }
  }

  WidgetButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: root.displayText
    labelVisible: !root.vertical
    opacity: root.healthy ? 1.0 : 0.55
    tooltipText: root.hostCount > 0 ? (root.hostCount + (root.hostCount === 1 ? " published OpenCode server" : " published OpenCode servers")) : "OpenCode Remote"

    onPressed: function(b) {
      if (b === Qt.RightButton) root.refresh()
      else root.togglePanel()
    }
  }
}
