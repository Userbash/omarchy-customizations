#!/usr/bin/env bash
set -euo pipefail
root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
proc_root="$tmp/proc"
sys_net_root="$tmp/sys/class/net"
mkdir -p "$proc_root/123" "$sys_net_root/throne-tun"
printf 'kvm_amd 1 0 - Live 0x0\n' > "$proc_root/modules"
printf 'qemu-system-"test\nnode\n' > "$proc_root/123/comm"
printf 'up\n' > "$sys_net_root/throne-tun/operstate"
touch "$tmp/dev-kvm"

OMARCHY_KVM_PROC_ROOT="$proc_root" \
OMARCHY_KVM_SYS_CLASS_NET_ROOT="$sys_net_root" \
OMARCHY_KVM_DEVICE_PATH="$tmp/dev-kvm" \
  sh "$root/config/omarchy/plugins/kvm-status/metrics-backend" > "$tmp/result.json"

jq -e '
  .kvm_device == 1 and
  .kvm_amd == 1 and
  .kvm_intel == 0 and
  .vm_count == 1 and
  .vm_names == "qemu-system-\"test\nnode" and
  .vpn_active == 1 and
  .vpn_name == "throne-tun"
' "$tmp/result.json" >/dev/null
printf 'KVM metrics JSON escaping test: ok\n'
