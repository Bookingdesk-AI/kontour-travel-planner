#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

fail() {
  echo "[FAIL] $1" >&2
  exit 1
}

pass() {
  echo "[PASS] $1"
}

SCAN_TARGETS=(scripts/plan.sh scripts/export-gmaps.sh scripts/gen-airports.py)

NETWORK_RAW_SOCKET_PATTERN='\bcurl\b|\bwget\b|\bfetch\s*\(|\baxios\s*\(|\brequests\.(get|post|put|delete|request)\b|\burllib\.(request|urlopen)\b|\bhttpx\.(get|post|put|delete|request|Client|AsyncClient)\b|\b(nc|netcat|ncat|socat|telnet)\b|/dev/tcp/|\bimport\s+socket\b|\bfrom\s+socket\s+import\b|socket\.socket\('
DYNAMIC_EXEC_PATTERN='eval\(|\beval\b|bash -c|sh -c|source <\(|os\.system|subprocess\.|exec\('

echo "Running static trust review checks..."

# 1) Runtime/generator scripts should not make outbound network calls or raw socket use.
if rg -n "$NETWORK_RAW_SOCKET_PATTERN" "${SCAN_TARGETS[@]}" >/tmp/socket-review-network.txt; then
  cat /tmp/socket-review-network.txt >&2
  fail "Runtime/generator scripts include network-client or raw-socket patterns."
fi
pass "Runtime/generator scripts contain no network-client or raw-socket patterns."

# 2) Runtime scripts should avoid dynamic command execution primitives.
if rg -n "$DYNAMIC_EXEC_PATTERN" "${SCAN_TARGETS[@]}" >/tmp/socket-review-exec.txt; then
  cat /tmp/socket-review-exec.txt >&2
  fail "Runtime/generator scripts include dynamic execution patterns."
fi
pass "Runtime/generator scripts contain no dynamic execution primitives."

# 3) Ensure publish metadata keeps the approved license.
if ! rg -n "^license:\s*MIT-0$" SKILL.md >/dev/null; then
  fail "SKILL.md license is not MIT-0."
fi
pass "SKILL.md license remains MIT-0."

# 4) Spot obvious credential-like strings in tracked content.
if rg -n "AKIA[0-9A-Z]{16}|ghp_[A-Za-z0-9]{36}|sk-[A-Za-z0-9]{20,}|xox[baprs]-[A-Za-z0-9-]{20,}" SKILL.md scripts references README.md >/tmp/socket-review-secrets.txt; then
  cat /tmp/socket-review-secrets.txt >&2
  fail "Potential credential pattern detected."
fi
pass "No obvious credential patterns detected."

echo "All static trust review checks passed."
