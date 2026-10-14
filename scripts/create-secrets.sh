#!/usr/bin/env bash
# Creates the MongoDB credentials Secret with a random password - nothing secret lives in git.
# Idempotent: an existing Secret is kept, because Mongo only reads root credentials on FIRST
# initialisation of the volume. Rotating the Secret under an existing PVC would break the app.
set -euo pipefail
NS="${NAMESPACE:-three-tier}"

if kubectl -n "$NS" get secret mongodb-credentials >/dev/null 2>&1; then
  echo "✓ secret mongodb-credentials already exists - keeping it"
  exit 0
fi

kubectl -n "$NS" create secret generic mongodb-credentials \
  --from-literal=MONGO_USER=appadmin \
  --from-literal=MONGO_PASSWORD="$(openssl rand -hex 16)"
echo "✓ secret mongodb-credentials created"
