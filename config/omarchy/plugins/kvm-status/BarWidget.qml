import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui

BarWidget {
  id: root
  moduleName: "kvm-status"

  readonly property string backend: Quickshell.env("HOME") + "/.config/omarchy/plugins/kvm-status/metrics-backend"
  property var report: ({})
  property bool reportValid: false
  property bool opened: false
  readonly property bool ready: reportValid
  readonly property bool kvmAvailable: ready && Number(root.field("kvm_device", 0)) === 1
  readonly property int vmCount: ready ? Number(root.field("vm_count", 0)) : 0
  readonly property bool vpnActive: ready && Number(root.field("vpn_active", 0)) === 1
  // UI masking only: it changes the label shown in the shell, not the OS,
  // routing table, VPN process, or network traffic.
  readonly property string privateNetworkLabel: vpnActive ? "Private network" : "No private network"

  function refresh() { if (!probe.running) probe.running = true }
  function field(name, fallback) {
    var value = root.report
    return value && typeof value === "object" && value[name] !== undefined && value[name] !== null ? value[name] : fallback
  }
  function toggle() { opened = !opened }
  function open() { opened = true }
  function close() { opened = false }

  Process {
    id: probe
    command: [root.backend]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        try {
          var parsed = JSON.parse(text || "{}")
          root.report = parsed && typeof parsed === "object" && !Array.isArray(parsed) ? parsed : ({})
          root.reportValid = parsed && typeof parsed === "object" && !Array.isArray(parsed)
        }
        catch (error) { console.warn("kvm-status: invalid backend response", error) }
      }
    }
  }

  Timer { interval: 3000; running: true; repeat: true; triggeredOnStart: true; onTriggered: root.refresh() }

  BarIconButton {
    anchors.fill: parent
    bar: root.bar
    text: root.ready ? (root.kvmAvailable ? "KVM" : "KVM—") + (root.vmCount > 0 ? " " + root.vmCount : "") : "KVM—"
    slotSize: Style.bar.statusSlot * 2
    tooltipText: root.ready
      ? (root.kvmAvailable ? "KVM доступен" : "KVM недоступен") + " · ВМ: " + root.vmCount + " · " + root.privateNetworkLabel
      : "KVM status"
    onPressed: function(button) { if (button === Qt.LeftButton || button === Qt.RightButton) root.toggle() }
  }

  PopupCard {
    id: popup
    anchorItem: parent
    owner: root
    bar: root.bar
    open: root.opened
    contentWidth: fittedContentWidth(Style.space(380))
    contentHeight: fittedContentHeight(details.implicitHeight)

    Column {
      id: details
      anchors.fill: parent
      spacing: Style.space(9)
      Text { text: "KVM и приватная сеть"; color: "#cacccc"; font.pixelSize: 14; font.bold: true }
      Text { text: "Только чтение; обновление каждые 3 секунды"; color: "#707880"; font.pixelSize: 11 }
      Repeater {
        model: [
          {name: "KVM", value: root.ready ? (root.kvmAvailable ? "доступен" : "недоступен") : "—"},
          {name: "Модули", value: root.ready ? ((Number(root.field("kvm_amd", 0)) ? "kvm_amd " : "") + (Number(root.field("kvm_intel", 0)) ? "kvm_intel" : "")) || "нет" : "—"},
          {name: "Активные ВМ", value: root.ready ? String(root.vmCount) : "—"},
          {name: "Сеть", value: root.privateNetworkLabel}
        ]
        delegate: Row {
          width: 330
          spacing: Style.space(10)
          Text { text: (modelData || {}).name || ""; color: "#707880"; font.pixelSize: 12; width: 120 }
          Text { text: (modelData || {}).value || ""; color: "#cacccc"; font.pixelSize: 12; font.bold: true; wrapMode: Text.Wrap }
        }
      }
      Text {
        visible: root.ready && root.vmCount > 0 && String(root.field("vm_names", "")) !== ""
        text: root.ready ? "Процессы: " + String(root.field("vm_names", "")) : ""
        color: "#707880"; font.pixelSize: 11; wrapMode: Text.Wrap; width: 330
      }
    }
  }
}
