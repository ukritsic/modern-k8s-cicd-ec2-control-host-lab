#!/usr/bin/env bash
set -euo pipefail

CURRENT_CONTEXT="$(kubectl config current-context 2>/dev/null || true)"
if [[ -z "$CURRENT_CONTEXT" ]]; then
  echo "kubectl has no current context. Copy your cluster kubeconfig first."
  exit 1
fi

echo "Current context: $CURRENT_CONTEXT"
kubectl cluster-info
kubectl get nodes -o wide

NOT_READY="$(kubectl get nodes --no-headers 2>/dev/null | awk '$2 != "Ready" {count++} END {print count+0}')"
if [[ "$NOT_READY" -gt 0 ]]; then
  echo "One or more Kubernetes nodes are not Ready. Fix the cluster before continuing."
  exit 1
fi

echo "Cluster validation passed."
