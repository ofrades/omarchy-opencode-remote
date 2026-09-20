import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui
import "Model.js" as Model

// OpenCode Remote popup: every session on every tailnet machine, in one
// picker. The backend is Service.qml (local + remote opencode servers over
// QML Process); this file is only layout and wiring.
//
// BarWidget.qml owns the bar slot and hands this panel the button to
// anchor against.
Panel {
  id: root
  moduleName: "io.github.ofrades.opencode-remote"
  ipcTarget: "io.github.ofrades.opencode-remote"
  manageIpc: false

  property var anchorItem: null
  property var hostWidget: null
  readonly property var barIdentity: hostWidget || root

  property string currentTab: "local"

  property bool showHistory: false

  readonly property color foreground: bar ? bar.foreground : Color.foreground
  readonly property color urgent: bar ? bar.urgent : Color.urgent
  readonly property color dim: Qt.darker(foreground, 1.55)
  readonly property string fontFamily: bar ? bar.fontFamily : Style.font.family

  readonly property int totalCount: sessions.totalSessions
  readonly property int hostCount: sessions.reachableHosts
  readonly property bool healthy: sessions.configured
  readonly property string heroMeta: !sessions.opencodeInstalled ? "opencode is not installed"
    : totalCount === 0 ? "No sessions found"
    : totalCount + (totalCount === 1 ? " session" : " sessions") + " · " + hostCount + (hostCount === 1 ? " machine" : " machines")

  function open() {
    refresh()
    root.controller.show()
  }

  function close() {
    root.controller.hide()
  }

  function toggle() {
    if (root.opened) root.close()
    else root.open()
  }

  function switchPanel(direction) {
    if (root.bar && typeof root.bar.switchPanelFrom === "function")
      return root.bar.switchPanelFrom(root.barIdentity, direction)
    return false
  }

  function refresh() {
    sessions.refresh()
  }

  function showTab(name) {
    currentTab = name
  }

  function openSession(peerName, sessionId) {
    sessions.openSession(peerName, sessionId)
    root.close()
  }

  function openLocal(sessionId) {
    sessions.openLocalSession(sessionId)
    root.close()
  }

  function openRemote(peerName, sessionId) {
    sessions.openRemoteSession(peerName, sessionId)
    root.close()
  }

  onOpenedChanged: if (opened) {
    if (panelFlick) panelFlick.contentY = 0
    sessions.refresh()
    Qt.callLater(function() { keyCatcher.forceActiveFocus() })
  }

  Service {
    id: sessions
    settings: root.settings
  }

  // IPC is handled by BarWidget.qml (the bar-widget entry point), which
  // forwards open/close/toggle here. A second IpcHandler on the same
  // target would only conflict, so this panel exposes none.

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
      onTextKey: function(t) {
        if (t === "r" || t === "R") sessions.refresh()
        else if (t === "1") root.showTab("local")
        else if (t === "2") root.showTab("remote")
      }

      Flickable {
        id: panelFlick
        anchors.fill: parent
        contentWidth: width
        contentHeight: column.implicitHeight
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        flickableDirection: Flickable.VerticalFlick
        interactive: contentHeight > height
        ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }

        Column {
          id: column
          width: panelFlick.width
          spacing: Style.space(12)

          PanelHero {
            width: parent.width
            title: "OpenCode"
            meta: root.heroMeta
            foreground: root.foreground
            fontFamily: root.fontFamily
            iconOpacity: root.healthy ? 1.0 : 0.5
            iconComponent: Component {
              Text {
                textFormat: Text.PlainText
                text: "󰆍"
                color: root.foreground
                font.family: root.fontFamily
                font.pixelSize: Style.font.display
              }
            }
          }

          // ---- One picker across all machines.
          Column {
            width: parent.width
            spacing: Style.space(10)

            // View switcher as bordered pills, same as the wifi panel's
            // band/DNS pills: `active` fills the current view.
            RowLayout {
              width: parent.width
              spacing: Style.space(8)

              Button {
                text: "This machine"
                fontSize: Style.font.bodySmall
                foreground: root.foreground
                fontFamily: root.fontFamily
                bordered: true
                active: root.currentTab === "local"
                Layout.fillWidth: true
                Layout.preferredWidth: 100
                onClicked: root.showTab("local")
              }

              Button {
                text: "Remote"
                fontSize: Style.font.bodySmall
                foreground: root.foreground
                fontFamily: root.fontFamily
                bordered: true
                active: root.currentTab === "remote"
                Layout.fillWidth: true
                Layout.preferredWidth: 100
                onClicked: root.showTab("remote")
              }
            }

            // Incoming pairings first: trusting one is what makes new
            // sessions appear below.
            Column {
              visible: sessions.pairingInbox.length > 0 && root.currentTab === "remote"
              width: parent.width
              spacing: Style.space(6)

              PanelSectionHeader {
                text: "INCOMING PAIRINGS"
                foreground: root.foreground
                fontFamily: root.fontFamily
              }

              Text {
                width: parent.width
                textFormat: Text.PlainText
                text: "Only trust machines you recognize — this grants them full opencode API access."
                color: root.dim
                font.family: root.fontFamily
                font.pixelSize: Style.font.caption
                wrapMode: Text.WordWrap
              }

              Repeater {
                model: sessions.pairingInbox
                ActionRow {
                  required property var modelData
                  title: "Trust " + String(modelData.host || "unknown")
                  subtitle: String(modelData.tailIP || "") + ":" + modelData.port + " · " + String(modelData.fingerprint || "")
                  onClicked: sessions.trustPairing(String(modelData.file || ""), String(modelData.host || ""))
                }
              }
            }

            Text {
              textFormat: Text.PlainText
              visible: sessions.actionStatus !== "" || sessions.lastError !== ""
              width: parent.width
              text: sessions.actionStatus !== "" ? sessions.actionStatus : sessions.lastError
              color: sessions.lastError !== "" && sessions.actionStatus === "" ? root.urgent : root.dim
              font.family: root.fontFamily
              font.pixelSize: Style.font.bodySmall
              wrapMode: Text.WordWrap
            }

            ActionRow {
              visible: sessions.localReachable && root.currentTab === "local"
              title: "New local session"
              subtitle: "Open a fresh TUI on this machine"
              onClicked: root.openLocal("")
            }

            Text {
              visible: sessions.shareUrl !== "" && root.currentTab === "local"
              width: parent.width
              textFormat: Text.PlainText
              text: sessions.shareUrl
              color: root.dim
              font.family: root.fontFamily
              font.pixelSize: Style.font.bodySmall
              elide: Text.ElideMiddle
            }

            ActionRow {
              visible: sessions.shareUrl !== "" && root.currentTab === "local"
              title: "Copy server URL"
              subtitle: "Paste it into the phone app"
              onClicked: sessions.copyShareUrl()
            }

            ActionRow {
              visible: sessions.shareUrl !== "" && root.currentTab === "local"
              title: "Show phone QR"
              subtitle: "Scan it with OpenCode Mobile"
              onClicked: sessions.showPhoneQr()
            }

            Text {
              visible: !sessions.opencodeInstalled && root.currentTab === "local"
              width: parent.width
              textFormat: Text.PlainText
              text: "Install opencode v2 to begin."
              color: root.dim
              font.family: root.fontFamily
              font.pixelSize: Style.font.bodySmall
              wrapMode: Text.WordWrap
            }

            // This machine first: open sessions only, no history trawl.
            Column {
              visible: sessions.opencodeInstalled && root.currentTab === "local"
              width: parent.width
              spacing: Style.space(6)

              PanelSectionHeader {
                text: "RUNNING"
                foreground: root.foreground
                fontFamily: root.fontFamily
              }

              Text {
                visible: !sessions.localReachable
                width: parent.width
                textFormat: Text.PlainText
                text: sessions.localError !== "" ? ("Local server: " + sessions.localError) : "Local server not reachable"
                color: root.dim
                font.family: root.fontFamily
                font.pixelSize: Style.font.bodySmall
                wrapMode: Text.WordWrap
              }

              Text {
                visible: sessions.localReachable && sessions.localSessions.length === 0
                width: parent.width
                textFormat: Text.PlainText
                text: sessions.localTotal > 0 ? ("No running sessions — " + sessions.localTotal + " stopped.") : "No sessions here yet."
                color: root.dim
                font.family: root.fontFamily
                font.pixelSize: Style.font.body
                horizontalAlignment: Text.AlignHCenter
              }

              Repeater {
                model: sessions.localSessions
                SessionRow {
                  required property var modelData
                  width: parent.width
                  peerName: ""
                  session: modelData
                }
              }

              ActionRow {
                visible: sessions.localReachable && sessions.localHistory.length > 0
                title: (root.showHistory ? "▾ " : "▸ ") + "Stopped (" + sessions.localHistory.length + ")"
                subtitle: root.showHistory ? "Hide stopped sessions" : "Continue a stopped session"
                onClicked: root.showHistory = !root.showHistory
              }

              Column {
                visible: root.showHistory && sessions.localHistory.length > 0
                width: parent.width
                spacing: Style.space(6)

                Repeater {
                  model: sessions.localHistory
                  SessionRow {
                    required property var modelData
                    width: parent.width
                    peerName: ""
                    session: modelData
                  }
                }
              }
            }

            // Then one group per tailnet peer.
            Text {
              visible: root.currentTab === "remote" && !sessions.tailscaleRunning
              width: parent.width
              textFormat: Text.PlainText
              text: sessions.tailscaleInstalled ? "Tailscale is offline — connect, then reopen." : "Install Tailscale to reach your other machines."
              color: root.dim
              font.family: root.fontFamily
              font.pixelSize: Style.font.bodySmall
              wrapMode: Text.WordWrap
            }

            Repeater {
              model: sessions.peers
              Column {
                required property var modelData
                visible: root.currentTab === "remote"
                width: parent.width
                spacing: Style.space(6)

                PanelSectionHeader {
                  text: String(modelData.hostName || "unknown").toUpperCase()
                  foreground: root.foreground
                  fontFamily: root.fontFamily
                }

                Text {
                  visible: modelData.online !== true
                  width: parent.width
                  textFormat: Text.PlainText
                  text: "Offline"
                  color: root.dim
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.bodySmall
                }

                Text {
                  visible: modelData.online === true && modelData.reachable !== true
                  width: parent.width
                  textFormat: Text.PlainText
                  text: Model.peerLabel(modelData) + (modelData.error !== "" ? (" — " + modelData.error) : "")
                  color: root.dim
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.bodySmall
                  wrapMode: Text.WordWrap
                }

                ActionRow {
                  visible: modelData.online === true && modelData.reachable !== true
                  title: "Expose this machine"
                  subtitle: "Pair server to its tailnet URL, notify " + String(modelData.hostName || "unknown")
                  onClicked: sessions.pairWith(String(modelData.hostName || ""))
                }

                Text {
                  visible: modelData.reachable === true && String(modelData.url || "") !== ""
                  width: parent.width
                  textFormat: Text.PlainText
                  text: String(modelData.url || "")
                  color: root.dim
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.caption
                  elide: Text.ElideMiddle
                }

                ActionRow {
                  visible: modelData.reachable === true
                  title: "New session on " + String(modelData.hostName || "")
                  subtitle: "Tools run on that machine"
                  onClicked: root.openRemote(String(modelData.hostName || ""), "")
                }

                Repeater {
                  model: modelData.sessions
                  SessionRow {
                    required property var modelData
                    width: parent.width
                    peerName: String(parent.modelData.hostName || "")
                    session: modelData
                  }
                }

                Text {
                  visible: modelData.online === true && modelData.reachable === true && modelData.sessions.length === 0
                  width: parent.width
                  textFormat: Text.PlainText
                  text: "No sessions on this machine."
                  color: root.dim
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.body
                  horizontalAlignment: Text.AlignHCenter
                }
              }
            }

            Text {
              visible: root.currentTab === "remote" && sessions.tailscaleRunning && sessions.peers.length === 0
              width: parent.width
              textFormat: Text.PlainText
              text: "No tailnet peers found."
              color: root.dim
              font.family: root.fontFamily
              font.pixelSize: Style.font.body
              horizontalAlignment: Text.AlignHCenter
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

    // A full-width action row is the whole contract of this component. It has
    // to claim the width itself: the root is a Rectangle (via CursorSurface),
    // which has no implicit width, and a Column does not stretch its children
    // — so without this every ActionRow renders 0px wide inside the panel's
    // Columns and shows up as a blank gap.
    width: parent ? parent.width : 0

    foreground: root.foreground
    implicitHeight: actionContent.implicitHeight + Style.spacing.rowPaddingX

    MouseArea {
      anchors.fill: parent
      hoverEnabled: true
      cursorShape: enabled && !sessions.busy ? Qt.PointingHandCursor : Qt.ArrowCursor
      enabled: !sessions.busy
      onClicked: actionRow.clicked()
    }

    RowLayout {
      id: actionContent
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.verticalCenter: parent.verticalCenter
      anchors.leftMargin: Style.space(10)
      anchors.rightMargin: Style.space(10)
      spacing: Style.space(8)

      ColumnLayout {
        Layout.fillWidth: true
        spacing: Style.space(1)

        Text {
          textFormat: Text.PlainText
          Layout.fillWidth: true
          text: actionRow.title
          color: root.foreground
          opacity: sessions.busy ? 0.5 : 1.0
          font.family: root.fontFamily
          font.pixelSize: Style.font.body
          elide: Text.ElideRight
        }

        Text {
          visible: actionRow.subtitle !== ""
          textFormat: Text.PlainText
          Layout.fillWidth: true
          text: actionRow.subtitle
          color: root.dim
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
          elide: Text.ElideMiddle
        }
      }

      Text {
        textFormat: Text.PlainText
        text: "›"
        color: root.dim
        font.family: root.fontFamily
        font.pixelSize: Style.font.body
        Layout.alignment: Qt.AlignVCenter
      }
    }
  }

  component SessionRow: CursorSurface {
    id: sessionRow
    property string peerName: ""
    property var session: null
    readonly property string sessionId: session ? String(session.id || "") : ""
    readonly property bool isSelected: sessions.selectedSession !== ""
      && sessions.selectedSession === sessionId
      && sessions.selectedPeer === peerName

    foreground: root.foreground
    implicitHeight: sessionContent.implicitHeight + Style.spacing.rowPaddingX

    MouseArea {
      anchors.fill: parent
      hoverEnabled: true
      cursorShape: Qt.PointingHandCursor
      onClicked: root.openSession(sessionRow.peerName, sessionRow.sessionId)
    }

    RowLayout {
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.verticalCenter: parent.verticalCenter
      anchors.leftMargin: Style.space(10)
      anchors.rightMargin: Style.space(6)
      spacing: Style.space(8)

      Text {
        visible: sessionRow.isSelected
        textFormat: Text.PlainText
        text: "●"
        color: root.foreground
        font.family: root.fontFamily
        font.pixelSize: Style.font.bodySmall
        Layout.alignment: Qt.AlignVCenter
      }

      ColumnLayout {
        id: sessionContent
        Layout.fillWidth: true
        spacing: Style.space(1)

        Text {
          textFormat: Text.PlainText
          Layout.fillWidth: true
          text: sessionRow.session ? String(sessionRow.session.title || "Untitled session") : "Untitled session"
          color: root.foreground
          font.family: root.fontFamily
          font.pixelSize: Style.font.body
          elide: Text.ElideRight
        }

        Text {
          textFormat: Text.PlainText
          Layout.fillWidth: true
          text: sessionRow.session ? Model.sessionSubtitle(sessionRow.session) : ""
          color: root.dim
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
          elide: Text.ElideMiddle
        }
      }

      Text {
        visible: sessionRow.peerName === ""
        textFormat: Text.PlainText
        text: "›"
        color: root.dim
        font.family: root.fontFamily
        font.pixelSize: Style.font.body
        Layout.alignment: Qt.AlignVCenter
      }

      Text {
        visible: sessionRow.peerName !== ""
        textFormat: Text.PlainText
        text: "⇄"
        color: root.dim
        font.family: root.fontFamily
        font.pixelSize: Style.font.body
        Layout.alignment: Qt.AlignVCenter
      }
    }
  }

  component InfoPair: Row {
    property string label: ""
    property string value: ""

    width: parent.width
    spacing: Style.space(8)

    InfoLabel { text: label }
    Item { width: Math.max(0, parent.width - parent.children[0].implicitWidth - parent.children[2].implicitWidth - parent.spacing * 2); height: 1 }
    InfoValue { text: value }
  }

  component InfoLabel: Text {
    textFormat: Text.PlainText
    color: root.foreground
    opacity: 0.6
    font.family: root.fontFamily
    font.pixelSize: Style.font.bodySmall
  }

  component InfoValue: Text {
    textFormat: Text.PlainText
    color: root.foreground
    font.family: root.fontFamily
    font.pixelSize: Style.font.bodySmall
    elide: Text.ElideMiddle
  }
}
