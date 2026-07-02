#!/usr/bin/env bash
set -euo pipefail

if ! command -v brew >/dev/null 2>&1; then
  echo "Homebrew is required first. Install it from the official Homebrew site."
  exit 1
fi

brew update
brew install awscli kubectl helm argocd kustomize jq git
brew install --cask docker || true

cat <<'MSG'
Tools installed.
Open Docker Desktop, then verify:
  aws --version
  kubectl version --client
  helm version
  argocd version --client
  kustomize version
  docker version

This lab uses your existing Kubernetes cluster on EC2. eksctl is not required.
MSG
