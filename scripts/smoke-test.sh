#!/usr/bin/env bash
# End-to-end check through the Ingress: frontend -> API -> MongoDB (write + read), plus Grafana health.
# Every call is retried: right after a rollout, endpoints can take a few seconds to settle.
set -euo pipefail
BASE="${BASE_URL:-http://127.0.0.1}"
TIMEOUT="${SMOKE_TIMEOUT:-90}"

ok()   { echo "✓ $1"; }
fail() { echo "✗ $1" >&2; exit 1; }

retry() {
  local deadline=$((SECONDS + TIMEOUT))
  until "$@"; do
    (( SECONDS >= deadline )) && return 1
    sleep 3
  done
}

page=$(retry curl -fsS "$BASE/") || fail "frontend unreachable"
if grep -q "Three-Tier" <<<"$page"; then ok "frontend served via ingress"; else fail "frontend content"; fi

MSG="smoke-$(date +%s)"
if retry curl -fsS -X POST "$BASE/api/messages" -H 'Content-Type: application/json' -d "{\"text\":\"$MSG\"}" >/dev/null; then
  ok "POST /api/messages (write to MongoDB)"
else
  fail "api write"
fi

messages=$(retry curl -fsS "$BASE/api/messages") || fail "api read unreachable"
if grep -q "$MSG" <<<"$messages"; then ok "GET /api/messages (read back from MongoDB)"; else fail "api read"; fi

health=$(retry curl -fsS -H 'Host: grafana.localtest.me' "$BASE/api/health") || fail "grafana unreachable"
if grep -q '"database": "ok"' <<<"$health"; then ok "Grafana healthy"; else fail "grafana"; fi

echo "All smoke tests passed 🎉"