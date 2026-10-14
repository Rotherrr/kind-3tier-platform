#!/usr/bin/env bash
# End-to-end check through the Ingress: frontend -> API -> MongoDB (write + read), plus Grafana health.
set -euo pipefail
BASE="${BASE_URL:-http://127.0.0.1}"
fail() { echo "✗ $1" >&2; exit 1; }

curl -fsS "$BASE/" | grep -q "Three-Tier" && echo "✓ frontend served via ingress" || fail "frontend"
MSG="smoke-$(date +%s)"
curl -fsS -X POST "$BASE/api/messages" -H 'Content-Type: application/json' -d "{\"text\":\"$MSG\"}" >/dev/null \
  && echo "✓ POST /api/messages (write to MongoDB)" || fail "api write"
curl -fsS "$BASE/api/messages" | grep -q "$MSG" && echo "✓ GET /api/messages (read back from MongoDB)" || fail "api read"
curl -fsS -H 'Host: grafana.localtest.me' "$BASE/api/health" | grep -q '"database": "ok"' \
  && echo "✓ Grafana healthy" || fail "grafana"
echo "All smoke tests passed 🎉"
