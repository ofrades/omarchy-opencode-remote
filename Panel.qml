import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import qs.Commons
import qs.Ui
import "Model.js" as Model

Panel {
  id: root
  moduleName: "io.github.ofrades.opencode-remote"
  ipcTarget: "io.github.ofrades.opencode-remote"
  manageIpc: false

  property var anchorItem: null
  property var hostWidget: null
  readonly property var barIdentity: hostWidget || root
  property bool showHistory: false
  property string currentTab: "local"
  readonly property color foreground: bar ? bar.foreground : Color.foreground
  readonly property color urgent: bar ? bar.urgent : Color.urgent
  readonly property color dim: Qt.darker(foreground, 1.55)
  readonly property string fontFamily: bar ? bar.fontFamily : Style.font.family
  readonly property int totalCount: service.localSessions.length
  readonly property int remoteCount: service.peers.filter(function(peer) { return peer.detected === true }).length
  readonly property int unavailableCount: service.peers.filter(function(peer) { return peer.online === true && peer.detected !== true }).length
  readonly property int hostCount: (service.published ? 1 : 0) + remoteCount
  readonly property bool healthy: service.configured
  readonly property string heroMeta: currentTab === "remote"
    ? remoteCount + (remoteCount === 1 ? " server ready" : " servers ready")
    : service.configured
      ? totalCount + (totalCount === 1 ? " active session" : " active sessions")
      : "Remote access needs attention"

  function open() { refresh(); controller.show() }
  function close() { controller.hide() }
  function toggle() { if (opened) close(); else open() }
  function refresh() { service.refresh() }
  function switchPanel(direction) {
    if (bar && typeof bar.switchPanelFrom === "function") return bar.switchPanelFrom(barIdentity, direction)
    return false
  }

  onOpenedChanged: if (opened) {
    if (panelFlick) panelFlick.contentY = 0
    refresh()
    Qt.callLater(function() { keyCatcher.forceActiveFocus() })
  }

  Service { id: service; settings: root.settings }

  KeyboardPanel {
    id: panel
    anchorItem: root.anchorItem
    owner: root.barIdentity
    bar: root.bar
    open: root.opened
    focusTarget: keyCatcher
    contentWidth: panel.fittedContentWidth(Style.space(420))
    contentHeight: panel.fittedContentHeight(column.implicitHeight, Style.space(600))

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      onCloseRequested: root.close()
      onTabRequested: function(direction) { root.switchPanel(direction) }
      onTextKey: function(text) {
        if (text === "r" || text === "R") service.refresh()
        else if (text === "1") root.currentTab = "local"
        else if (text === "2") root.currentTab = "remote"
      }

      Flickable {
        id: panelFlick
        anchors.fill: parent
        contentWidth: width
        contentHeight: column.implicitHeight
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        flickableDirection: Flickable.VerticalFlick
        ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }

        Column {
          id: column
          width: panelFlick.width
          spacing: Style.space(12)

          PanelHero {
            width: parent.width
            title: "OpenCode Remote"
            meta: root.heroMeta
            foreground: root.foreground
            fontFamily: root.fontFamily
            iconOpacity: root.healthy ? 1.0 : 0.5
            iconComponent: Component {
              Text { textFormat: Text.PlainText; text: "󰆍"; color: root.foreground; font.family: root.fontFamily; font.pixelSize: Style.font.display }
            }
          }

          RowLayout {
            width: parent.width
            spacing: Style.space(8)
            Button {
              text: "This machine"; fontSize: Style.font.bodySmall; foreground: root.foreground; fontFamily: root.fontFamily
              bordered: true; active: root.currentTab === "local"; Layout.fillWidth: true
              onClicked: root.currentTab = "local"
            }
            Button {
              text: "Remote"; fontSize: Style.font.bodySmall; foreground: root.foreground; fontFamily: root.fontFamily
              bordered: true; active: root.currentTab === "remote"; Layout.fillWidth: true
              onClicked: root.currentTab = "remote"
            }
          }

          Column {
            visible: root.currentTab === "local"
            width: parent.width
            spacing: Style.space(10)

            PanelSectionHeader { text: "THIS MACHINE"; foreground: root.foreground; fontFamily: root.fontFamily }

            RowLayout {
              width: parent.width
              spacing: Style.space(6)
              StatusBadge { label: "OpenCode"; value: service.localReachable ? "Running" : (service.opencodeInstalled ? "Stopped" : "Missing"); good: service.localReachable; Layout.fillWidth: true }
              StatusBadge { label: "Tailscale"; value: service.tailscaleRunning ? "Connected" : (service.tailscaleInstalled ? "Offline" : "Missing"); good: service.tailscaleRunning; Layout.fillWidth: true }
              StatusBadge { label: "Remote"; value: service.published ? "Ready" : "Off"; good: service.published; Layout.fillWidth: true }
            }

            Text {
              visible: service.actionStatus !== "" || service.lastError !== ""
              width: parent.width
              textFormat: Text.PlainText
              text: service.lastError !== "" ? service.lastError : service.actionStatus
              color: service.lastError !== "" ? root.urgent : root.dim
              font.family: root.fontFamily
              font.pixelSize: Style.font.bodySmall
              wrapMode: Text.WordWrap
            }

            ActionRow {
              visible: !service.configured
              title: service.published ? "Repair remote access" : "Enable remote access"
              subtitle: "Start OpenCode and connect it through Tailscale"
              onClicked: service.publish()
            }

            RowLayout {
              visible: service.published
              width: parent.width
              spacing: Style.space(6)
              Text { textFormat: Text.PlainText; text: "●"; color: root.foreground; font.family: root.fontFamily; font.pixelSize: Style.font.caption }
              Text { textFormat: Text.PlainText; text: service.publicUrl; color: root.dim; font.family: root.fontFamily; font.pixelSize: Style.font.caption; elide: Text.ElideMiddle; Layout.fillWidth: true }
            }

            ActionRow { visible: service.published; title: "Open dashboard"; subtitle: "Open OpenCode in your browser"; onClicked: { service.openDashboard(); root.close() } }
          }

          Column {
            visible: root.currentTab === "local" && service.localReachable
            width: parent.width
            spacing: Style.space(6)

            PanelSectionHeader { text: "ACTIVE · " + service.localSessions.length; foreground: root.foreground; fontFamily: root.fontFamily }

            EmptyState {
              visible: service.localSessions.length === 0
              message: "No active sessions"
            }

            Repeater {
              model: service.localSessions
              SessionRow { required property var modelData; session: modelData }
            }

            ActionRow {
              visible: service.localHistory.length > 0
              title: (root.showHistory ? "▾ " : "▸ ") + "History (" + service.localHistory.length + ")"
              subtitle: root.showHistory ? "Hide past sessions" : "Show past sessions"
              onClicked: root.showHistory = !root.showHistory
            }

            Column {
              visible: root.showHistory
              width: parent.width
              spacing: Style.space(6)
              Repeater { model: service.localHistory; SessionRow { required property var modelData; session: modelData } }
            }
          }

          Column {
            visible: root.currentTab === "remote"
            width: parent.width
            spacing: Style.space(8)

            PanelSectionHeader { text: "AVAILABLE · " + root.remoteCount; foreground: root.foreground; fontFamily: root.fontFamily }

            Text {
              visible: service.tailscaleRunning && root.remoteCount > 0
              width: parent.width
              textFormat: Text.PlainText
              text: "OpenCode servers discovered on your tailnet"
              color: root.dim
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
            }

            Text {
              visible: !service.tailscaleRunning
              width: parent.width
              textFormat: Text.PlainText
              text: "Connect Tailscale to discover other published machines."
              color: root.dim
              font.family: root.fontFamily
              font.pixelSize: Style.font.bodySmall
              wrapMode: Text.WordWrap
            }

            Repeater {
              model: service.peers.filter(function(peer) { return peer.detected === true })
              ActionRow {
                required property var modelData
                title: String(modelData.hostName || "OpenCode server")
                subtitle: (modelData.loginRequired === true ? "Login required · " : "") + String(modelData.dnsName || modelData.url || "")
                onClicked: { service.openPeer(modelData); root.close() }
              }
            }

            EmptyState {
              visible: service.tailscaleRunning && service.peers.filter(function(peer) { return peer.detected === true }).length === 0
              message: "No published servers found"
            }

            Text {
              visible: root.unavailableCount > 0
              width: parent.width
              textFormat: Text.PlainText
              text: root.unavailableCount + (root.unavailableCount === 1 ? " other online machine" : " other online machines")
              color: root.dim
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
              wrapMode: Text.WordWrap
            }
          }

          Text {
            width: parent.width
            textFormat: Text.PlainText
            text: "r refresh · 1–2 switch tabs · Esc close"
            color: root.dim
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
            horizontalAlignment: Text.AlignHCenter
          }
        }
      }
    }
  }

  component ActionRow: CursorSurface {
    id: actionRow
    signal clicked()
    property string title: ""
    property string subtitle: ""
    width: parent ? parent.width : 0
    foreground: root.foreground
    implicitHeight: actionContent.implicitHeight + Style.spacing.rowPaddingX
    MouseArea { anchors.fill: parent; hoverEnabled: true; cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor; enabled: !service.busy; onClicked: actionRow.clicked() }
    RowLayout {
      id: actionContent
      anchors.left: parent.left; anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter
      anchors.leftMargin: Style.space(10); anchors.rightMargin: Style.space(10); spacing: Style.space(8)
      ColumnLayout {
        Layout.fillWidth: true; spacing: Style.space(1)
        Text { textFormat: Text.PlainText; Layout.fillWidth: true; text: actionRow.title; color: root.foreground; font.family: root.fontFamily; font.pixelSize: Style.font.body; elide: Text.ElideRight }
        Text { visible: actionRow.subtitle !== ""; textFormat: Text.PlainText; Layout.fillWidth: true; text: actionRow.subtitle; color: root.dim; font.family: root.fontFamily; font.pixelSize: Style.font.caption; elide: Text.ElideMiddle }
      }
      Text { textFormat: Text.PlainText; text: "›"; color: root.dim; font.family: root.fontFamily; font.pixelSize: Style.font.body }
    }
  }

  component StatusBadge: Rectangle {
    property string label: ""
    property string value: ""
    property bool good: false
    color: "transparent"
    border.width: 1
    border.color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, good ? 0.3 : 0.12)
    radius: Style.space(4)
    implicitHeight: badgeContent.implicitHeight + Style.space(12)
    Column {
      id: badgeContent
      anchors.centerIn: parent
      spacing: Style.space(1)
      Text { anchors.horizontalCenter: parent.horizontalCenter; textFormat: Text.PlainText; text: parent.parent.label; color: root.dim; font.family: root.fontFamily; font.pixelSize: Style.font.caption }
      Text { anchors.horizontalCenter: parent.horizontalCenter; textFormat: Text.PlainText; text: (parent.parent.good ? "● " : "○ ") + parent.parent.value; color: parent.parent.good ? root.foreground : root.dim; font.family: root.fontFamily; font.pixelSize: Style.font.bodySmall }
    }
  }

  component EmptyState: Item {
    property string message: ""
    width: parent ? parent.width : 0
    implicitHeight: Style.space(52)
    Text {
      anchors.centerIn: parent
      textFormat: Text.PlainText
      text: parent.message
      color: root.dim
      font.family: root.fontFamily
      font.pixelSize: Style.font.bodySmall
    }
  }

  component SessionRow: CursorSurface {
    id: sessionRow
    required property var session
    width: parent ? parent.width : 0
    foreground: root.foreground
    implicitHeight: sessionContent.implicitHeight + Style.spacing.rowPaddingX
    MouseArea { anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: { service.openSession(sessionRow.session); root.close() } }
    RowLayout {
      anchors.left: parent.left; anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter
      anchors.leftMargin: Style.space(10); anchors.rightMargin: Style.space(6); spacing: Style.space(8)
      ColumnLayout {
        id: sessionContent
        Layout.fillWidth: true; spacing: Style.space(1)
        Text { textFormat: Text.PlainText; Layout.fillWidth: true; text: String(sessionRow.session.title || "Untitled session"); color: root.foreground; font.family: root.fontFamily; font.pixelSize: Style.font.body; elide: Text.ElideRight }
        Text { textFormat: Text.PlainText; Layout.fillWidth: true; text: Model.sessionSubtitle(sessionRow.session); color: root.dim; font.family: root.fontFamily; font.pixelSize: Style.font.caption; elide: Text.ElideMiddle }
      }
      Text { textFormat: Text.PlainText; text: "↗"; color: root.dim; font.family: root.fontFamily; font.pixelSize: Style.font.body }
    }
  }
}
