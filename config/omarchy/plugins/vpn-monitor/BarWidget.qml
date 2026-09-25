import QtQuick
import Quickshell
import Quickshell.Io
import qs.Ui as ShellUi
import "VpnUiModel.js" as Ui

ShellUi.BarWidget {
  id: root
  moduleName: "vpn-monitor"
  property bool opened: false
  property var report: ({})
  property string backendError: ""
  property bool diagnosticInProgress: false
  property string pendingAction: ""
  property var barFacade: root.bar
  readonly property string connectionState: String(report && report.connection && report.connection.state || "UNKNOWN")
  readonly property string barLabel: connectionState === "CONNECTED" || connectionState === "DEGRADED" ? "VPN" : "VPN—"
  readonly property color indicatorColor: Ui.color(connectionState)
  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  function open() { opened = true }
  function close() { opened = false }
  function toggle() { opened = !opened }

  IpcHandler {
    target: "sanya.vpn-monitor"

    function state(): string {
      return JSON.stringify({
        opened: root.opened,
        popupOpen: popup.open,
        popupVisible: popup.visible,
        connectionState: root.connectionState
      })
    }
    function open(): void { root.open() }
    function close(): void { root.close() }
    function toggle(): void { root.toggle() }
  }

  Timer {
    id: clickTimer
    interval: 280
    repeat: false
    onTriggered: root.toggle()
  }

  function syncBarRegistration() {
    if (barFacade && typeof barFacade.registerClickTarget === "function") barFacade.registerClickTarget(button)
  }

  onBarChanged: syncBarRegistration()
  Component.onCompleted: syncBarRegistration()
  Component.onDestruction: {
    if (barFacade && typeof barFacade.unregisterClickTarget === "function") barFacade.unregisterClickTarget(button)
  }

  VpnDashboardClient {
    id: client
    onStatusChangedFromBackend: function(value) {
      root.report = value
      root.backendError = ""
      // Status polling is independent of an in-flight test. Do not clear the
      // busy state merely because the two-second poll returned.
      var speed = value && value.diagnostics ? value.diagnostics.speedTest : null
      var speedState = speed ? String(speed.status || "") : ""
      var terminal = speedState === "COMPLETED" || speedState === "ERROR" || speedState === "CANCELLED"
      if ((root.pendingAction === "speed-test" || root.pendingAction === "speed-test-cancel")
          && terminal && speed.testId) {
        root.pendingAction = ""
      }
    }
    onRequestFinished: function(action, success) {
      if (!success) {
        root.diagnosticInProgress = false
        root.pendingAction = ""
        return
      }
      if (action === "diagnostics") root.diagnosticInProgress = false
      // Speed tests are asynchronous: remain busy until a terminal status is
      // observed in the normal status stream.
      if (action !== "speed-test" && action !== "speed-test-cancel") root.pendingAction = ""
    }
    onErrorMessageChanged: {
      if (errorMessage !== "") {
        root.backendError = errorMessage
        root.diagnosticInProgress = false
        root.pendingAction = ""
      }
    }
  }

  ShellUi.BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: root.barLabel
    active: root.connectionState === "CONNECTED" || root.connectionState === "DEGRADED"
    foreground: root.indicatorColor
    activeColor: root.indicatorColor
    tooltipText: root.backendError !== "" ? root.backendError
      : ((root.report.client && root.report.client.name ? root.report.client.name + " · " : "") + Ui.label(root.connectionState))
    onPressed: function(buttonCode) {
      if (buttonCode === Qt.RightButton) {
        root.toggle()
      } else if (buttonCode === Qt.LeftButton) {
        if (clickTimer.running) {
          clickTimer.stop()
          root.open()
          root.pendingAction = "toggle-connection"
          client.requestAction("toggle-connection")
        } else {
          clickTimer.start()
        }
      }
    }
  }

  VpnNotificationPopup {
    id: popup
    anchorItem: button
    owner: root
    bar: root.bar
    open: root.opened

    VpnStatusToast {
      id: toast
      anchors.fill: parent
      status: root.report
      diagnosticInProgress: root.diagnosticInProgress
      // Background status polling must not gray the controls. Only a real
      // user-started action owns the busy state.
      operationInProgress: root.pendingAction !== ""
      operationAction: root.pendingAction
      errorMessage: root.backendError
      onActionRequested: function(action) {
        root.pendingAction = action
        root.diagnosticInProgress = action === "diagnostics"
        client.requestAction(action)
      }
    }
  }
}
