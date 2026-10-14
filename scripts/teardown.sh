#!/usr/bin/env bash
set -euo pipefail
kind delete cluster --name "${CLUSTER_NAME:-three-tier}"
