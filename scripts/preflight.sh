#!/usr/bin/env bash
# Fail fast if a required tool is missing or Docker is not running.
set -euo pipefail
missing=0
for tool in docker kind kubectl helm curl openssl; do
  if ! command -v "$tool" >/dev/null 2>&1; then
    echo "✗ missing: $tool" >&2; missing=1
  else
    echo "✓ $tool"
  fi
done
docker info >/dev/null 2>&1 || { echo "✗ Docker daemon is not running" >&2; missing=1; }
exit $missing
