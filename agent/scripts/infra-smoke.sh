#!/usr/bin/env bash
# Smoke-tests the local compose stack (compose.yaml): Redpanda, Valkey and SeaweedFS.
# Needs: the stack is up (`make infra-up`). Run from the repo root: agent/scripts/infra-smoke.sh
# Exits non-zero at the first failed check. Removes the test topic, key and file it creates.
set -euo pipefail

compose=(docker compose)
topic="smoke-$$"
key="smoke-$$"
payload="hello-$$"
fails=0

pass() { printf 'ok    %s\n' "$1"; }
fail() { printf 'FAIL  %s\n' "$1"; fails=$((fails + 1)); }

check_http() { # name url
  local code
  code=$(curl -s -o /dev/null -w '%{http_code}' "$2" || true)
  if [[ "$code" == 200 ]]; then pass "$1"; else fail "$1 (HTTP $code)"; fi
}

# Redpanda
"${compose[@]}" exec -T redpanda rpk topic create "$topic" -p 1 -r 1 >/dev/null
echo "$payload" | "${compose[@]}" exec -T redpanda rpk topic produce "$topic" >/dev/null
got=$("${compose[@]}" exec -T redpanda rpk topic consume "$topic" -n 1 -f '%v\n')
[[ "$got" == "$payload" ]] && pass "redpanda produce/consume" || fail "redpanda produce/consume (got '$got')"
"${compose[@]}" exec -T redpanda rpk topic delete "$topic" >/dev/null
check_http "redpanda schema registry" http://127.0.0.1:18081/subjects
check_http "redpanda admin api" http://127.0.0.1:19644/v1/status/ready

# Valkey
"${compose[@]}" exec -T valkey valkey-cli set "$key" "$payload" >/dev/null
got=$("${compose[@]}" exec -T valkey valkey-cli get "$key")
[[ "$got" == "$payload" ]] && pass "valkey set/get" || fail "valkey set/get (got '$got')"
"${compose[@]}" exec -T valkey valkey-cli del "$key" >/dev/null

# SeaweedFS
check_http "seaweedfs master" http://127.0.0.1:9333/cluster/status
tmp=$(mktemp)
trap 'rm -f "$tmp"' EXIT
echo "$payload" > "$tmp"
curl -s -F "file=@$tmp;filename=smoke.txt" "http://127.0.0.1:8888/smoke-$$/" >/dev/null
got=$(curl -s "http://127.0.0.1:8888/smoke-$$/smoke.txt")
[[ "$got" == "$payload" ]] && pass "seaweedfs filer write/read" || fail "seaweedfs filer write/read (got '$got')"
curl -s -X DELETE "http://127.0.0.1:8888/smoke-$$/?recursive=true" >/dev/null
check_http "seaweedfs s3" http://127.0.0.1:8333/

if (( fails > 0 )); then
  echo "$fails check(s) failed"
  exit 1
fi
echo "all checks passed"
