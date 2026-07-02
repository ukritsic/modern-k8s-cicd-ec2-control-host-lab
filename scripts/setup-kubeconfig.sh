#!/usr/bin/env bash
set -euo pipefail

if [[ $# -ne 1 ]]; then
  echo "Usage: $0 /path/to/kubeconfig"
  exit 1
fi

SOURCE_CONFIG="$1"
TARGET_DIR="${HOME}/.kube"
TARGET_CONFIG="${TARGET_DIR}/config"

if [[ ! -f "$SOURCE_CONFIG" ]]; then
  echo "Kubeconfig not found: $SOURCE_CONFIG"
  exit 1
fi

mkdir -p "$TARGET_DIR"
chmod 700 "$TARGET_DIR"

if [[ -f "$TARGET_CONFIG" ]]; then
  BACKUP="${TARGET_CONFIG}.backup.$(date +%Y%m%d%H%M%S)"
  cp "$TARGET_CONFIG" "$BACKUP"
  chmod 600 "$BACKUP"
  echo "Existing kubeconfig backed up to: $BACKUP"
fi

install -m 600 "$SOURCE_CONFIG" "$TARGET_CONFIG"

export KUBECONFIG="$TARGET_CONFIG"
CURRENT_CONTEXT="$(kubectl config current-context 2>/dev/null || true)"
if [[ -z "$CURRENT_CONTEXT" ]]; then
  echo "The installed file has no current Kubernetes context."
  exit 1
fi

echo "Installed kubeconfig: $TARGET_CONFIG"
echo "Current context: $CURRENT_CONTEXT"
kubectl cluster-info
kubectl get nodes -o wide
