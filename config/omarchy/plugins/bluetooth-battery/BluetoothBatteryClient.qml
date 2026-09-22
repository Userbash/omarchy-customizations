import QtQuick

Item {
  id: root
  visible: false
  implicitWidth: 0
  implicitHeight: 0
  property string apiBaseUrl: "http://127.0.0.1:8765"
  property int pollInterval: 90000
  property bool autoRefresh: true
  property bool loading: false
  property bool adapterPowered: false
  property var devices: []
  property string lastError: ""
  property var activeRequest: null
  signal stateChangedFromBackend(var state)

  function applyPayload(payload) {
    if (!payload || !Array.isArray(payload.devices)) {
      root.lastError = "Invalid Bluetooth status"
      return false
    }
    root.adapterPowered = payload.adapterPowered === true
    root.devices = payload.devices
    root.lastError = ""
    root.stateChangedFromBackend(payload)
    return true
  }

  function refresh() {
    if (root.loading) return
    root.loading = true
    var request = new XMLHttpRequest()
    root.activeRequest = request
    request.open("GET", root.apiBaseUrl + "/api/v1/bluetooth/status")
    request.onreadystatechange = function() {
      if (request.cancelled || request.readyState !== XMLHttpRequest.DONE) return
      if (root.activeRequest !== request) return
      root.activeRequest = null
      root.loading = false
      if (request.status < 200 || request.status >= 300) {
        root.lastError = "Bluetooth status unavailable"
        return
      }
      try { root.applyPayload(JSON.parse(request.responseText)) }
      catch (error) { root.lastError = "Invalid Bluetooth response" }
    }
    request.send()
  }

  Component.onDestruction: {
    if (root.activeRequest) {
      root.activeRequest.cancelled = true
      root.activeRequest.onreadystatechange = null
      root.activeRequest.abort()
      root.activeRequest = null
    }
  }

  Timer {
    interval: root.pollInterval
    running: root.autoRefresh
    repeat: true
    triggeredOnStart: true
    onTriggered: root.refresh()
  }
}
