#!/usr/bin/env bash
set -euo pipefail

kubectl create namespace argocd --dry-run=client -o yaml | kubectl apply -f -
kubectl apply -n argocd --server-side --force-conflicts \
  -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml

kubectl rollout status deployment/argocd-server -n argocd --timeout=5m
kubectl get pods -n argocd

cat <<'MSG'
Access the Argo CD UI:
  kubectl port-forward svc/argocd-server -n argocd 8080:443

Open:
  https://localhost:8080

Username:
  admin

Initial password:
  argocd admin initial-password -n argocd
MSG
