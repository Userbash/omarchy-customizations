import QtQuick

Item {
  id: root

  // This is the sole frontend transport boundary. It only calls the
  // local monitor API; it never probes processes, routes or interfaces.
  property string apiBaseUrl: "http://127.0.0.1:8765"
  property int pollInterval: 2000
  property bool autoRefresh: true
  property bool loading: false
  property string errorMessage: ""
  property var status: ({})
  property var lastResponse: ({})
  property var activeRequest: null

  signal statusChangedFromBackend(var status)
  signal requestFinished(string action, bool success)

  function cancelActiveRequest() {
    if (!root.activeRequest) return
    root.activeRequest.cancelled = true
    root.activeRequest.onreadystatechange = null
    root.activeRequest.abort()
    root.activeRequest = null
    root.loading = false
  }

  function statusFromPayload(payload) {
    var items = payload && Array.isArray(payload.items) ? payload.items : []
    var selectedClientId = payload && payload.selectedClientId ? String(payload.selectedClientId) : ""
    if (selectedClientId === "") return ({})
    for (var i = 0; i < items.length; ++i) {
      var candidate = items[i] || ({})
      if (candidate.client && candidate.client.id === selectedClientId) return candidate
    }
    return ({})
  }

  function applyStatusPayload(payload) {
    root.lastResponse = payload || ({})
    var selected = root.statusFromPayload(root.lastResponse)
    if (Object.keys(selected).length === 0) {
      root.errorMessage = root.lastResponse.error && root.lastResponse.error.message
        ? String(root.lastResponse.error.message)
        : "Select a VPN client to view its status"
      root.status = ({})
      // The bar owns a cached report, so it must receive the clear event
      // instead of retaining the last connected status indefinitely.
      root.statusChangedFromBackend(root.status)
      return
    }
    root.errorMessage = ""
    root.status = selected
    root.statusChangedFromBackend(root.status)
  }

  function refresh() {
    if (root.loading) return
    root.loading = true
    var request = new XMLHttpRequest()
    root.activeRequest = request
    request.open("GET", root.apiBaseUrl + "/api/v1/status")
    request.onreadystatechange = function() {
      if (request.cancelled || request.readyState !== XMLHttpRequest.DONE) return
      if (root.activeRequest !== request) return
      root.activeRequest = null
      root.loading = false
      if (request.status < 200 || request.status >= 300) {
        root.errorMessage = "Unable to refresh VPN status"
        return
      }
      try {
        root.applyStatusPayload(JSON.parse(request.responseText))
      } catch (exception) {
        root.errorMessage = "Invalid response from VPN monitor"
      }
    }
    request.send()
  }

  function mergeDiagnostics(currentStatus, result) {
    var current = currentStatus || ({})
    var diagnosticResult = result || ({})
    var diagnostics = current.diagnostics || ({})
    diagnostics.pingMs = diagnosticResult.ping && diagnosticResult.ping.averageMs !== undefined
      ? diagnosticResult.ping.averageMs : diagnostics.pingMs
    diagnostics.packetLoss = diagnosticResult.ping && diagnosticResult.ping.packetLoss !== undefined
      ? diagnosticResult.ping.packetLoss : diagnostics.packetLoss
    diagnostics.dns = diagnosticResult.dns || diagnostics.dns
    diagnostics.http = diagnosticResult.http || diagnostics.http
    current.diagnostics = diagnostics
    var server = current.server || ({})
    if (diagnosticResult.externalIp) server.exitIp = diagnosticResult.externalIp
    var identity = diagnosticResult.server || ({})
    if (identity.country !== undefined) server.country = identity.country
    if (identity.countryCode !== undefined) server.countryCode = identity.countryCode
    if (identity.flag !== undefined) server.flag = identity.flag
    if (identity.usesWarp !== undefined) server.usesWarp = identity.usesWarp
    current.server = server
    return current
  }

  function runConnectivityCheck() {
    if (root.loading) return
    root.loading = true
    var request = new XMLHttpRequest()
    root.activeRequest = request
    request.open("POST", root.apiBaseUrl + "/api/v1/diagnostics/connectivity")
    request.setRequestHeader("X-Vpn-Monitor-Request", "1")
    request.onreadystatechange = function() {
      if (request.cancelled || request.readyState !== XMLHttpRequest.DONE) return
      if (root.activeRequest !== request) return
      root.activeRequest = null
      root.loading = false
      if (request.status < 200 || request.status >= 300) {
        root.errorMessage = "Unable to run connectivity check"
        root.requestFinished("diagnostics", false)
        return
      }
      try {
        root.status = root.mergeDiagnostics(root.status, JSON.parse(request.responseText))
        root.errorMessage = ""
        root.statusChangedFromBackend(root.status)
        root.requestFinished("diagnostics", true)
      } catch (exception) {
        root.errorMessage = "Invalid diagnostic response from VPN monitor"
        root.requestFinished("diagnostics", false)
      }
    }
    request.send()
  }

  function requestAction(action) {
    if (action === "diagnostics") {
      root.cancelActiveRequest()
      runConnectivityCheck()
      return
    }
    if (action === "refresh") {
      refresh()
      return
    }
    // A background GET status poll must not make a user click fail. Abort the
    // poll and give the action its own request slot.
    root.cancelActiveRequest()
    var endpoint = ""
    if (action === "speed-test") endpoint = "/api/v1/diagnostics/speed-test"
    else if (action === "speed-test-cancel") {
      var speedTestId = root.status && root.status.diagnostics && root.status.diagnostics.speedTest
        ? String(root.status.diagnostics.speedTest.testId || "") : ""
      if (speedTestId === "") {
        root.errorMessage = "No speed test is running"
        return
      }
      endpoint = "/api/v1/diagnostics/speed-test/" + speedTestId + "/cancel"
    }
    else if (action === "toggle-connection" || action === "start" || action === "stop" || action === "connect" || action === "disconnect") {
      var clientId = root.status && root.status.client && root.status.client.id ? String(root.status.client.id) : ""
      if (clientId === "") {
        root.errorMessage = "Choose a VPN client before sending a command"
        return
      }
      endpoint = "/api/v1/vpn/" + clientId + "/" + action
    } else {
      root.errorMessage = "Unsupported VPN action"
      return
    }

    root.loading = true
    var request = new XMLHttpRequest()
    root.activeRequest = request
    request.open("POST", root.apiBaseUrl + endpoint)
    request.setRequestHeader("X-Vpn-Monitor-Request", "1")
    request.onreadystatechange = function() {
      if (request.cancelled || request.readyState !== XMLHttpRequest.DONE) return
      if (root.activeRequest !== request) return
      root.activeRequest = null
      root.loading = false
      if (request.status < 200 || request.status >= 300) {
        try {
          var errorPayload = JSON.parse(request.responseText)
          root.errorMessage = errorPayload.message ? String(errorPayload.message) : "Backend refused VPN action"
        } catch (exception) {
          root.errorMessage = "Backend refused VPN action"
        }
        root.requestFinished(action, false)
        return
      }
      root.errorMessage = ""
      root.requestFinished(action, true)
      root.refresh()
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
