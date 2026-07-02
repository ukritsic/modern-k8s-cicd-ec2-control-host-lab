#!/usr/bin/env bash
set -euo pipefail

kubectl delete -f argocd/application.yaml --ignore-not-found || true
kubectl delete namespace modern-cicd --ignore-not-found || true

echo "Application resources were removed."
echo "Your EC2 instances and Kubernetes cluster were not changed."
echo "Argo CD remains installed in namespace argocd."
