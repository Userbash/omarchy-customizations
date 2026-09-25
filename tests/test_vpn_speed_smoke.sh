#!/usr/bin/env bash
set -euo pipefail

api=${VPN_MONITOR_API:-http://127.0.0.1:8765}
header=(-H 'X-Vpn-Monitor-Request: 1')

health=$(curl -fsS --max-time 5 "$api/health")
printf '%s' "$health" | jq -e '.status == "ok"' >/dev/null

start=$(curl -fsS --max-time 5 -X POST "${header[@]}" "$api/api/v1/diagnostics/speed-test")
test_id=$(printf '%s' "$start" | jq -r '.testId')

[[ -n "$test_id" && "$test_id" != "null" ]]
for _ in $(seq 1 30); do
  result=$(curl -fsS --max-time 5 "$api/api/v1/diagnostics/speed-test/$test_id")
  state=$(printf '%s' "$result" | jq -r '.status')
  case "$state" in
    COMPLETED)
      printf '%s\n' "$result" | jq -e '(.downloadMbps | type) == "number" and (.uploadMbps | type) == "number" and (.latencyMs == null or (.latencyMs | type) == "number")' >/dev/null
      printf 'vpn speed smoke: ok (%s)\n' "$result"
      exit 0
      ;;
    ERROR|CANCELLED)
      printf 'vpn speed smoke: terminal state %s: %s\n' "$state" "$result" >&2
      exit 1
      ;;
  esac
  sleep 1
done

printf 'vpn speed smoke: timeout waiting for %s\n' "$test_id" >&2
exit 1
