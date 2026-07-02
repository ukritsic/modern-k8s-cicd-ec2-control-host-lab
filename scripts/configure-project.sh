#!/usr/bin/env bash
set -euo pipefail

if [[ $# -lt 1 || $# -gt 2 ]]; then
  echo "Usage: $0 YOUR_GITHUB_USER_OR_ORG [GITHUB_REPOSITORY]"
  exit 1
fi

GITHUB_OWNER="$1"
GITHUB_REPOSITORY="${2:-modern-k8s-cicd-ec2-control-host-lab}"
AWS_REGION="${AWS_REGION:-ap-southeast-1}"
ECR_REPOSITORY="${ECR_REPOSITORY:-modern-k8s-cicd-app}"
AWS_ACCOUNT_ID="$(aws sts get-caller-identity --query Account --output text)"

python3 - "$AWS_ACCOUNT_ID" "$AWS_REGION" "$ECR_REPOSITORY" "$GITHUB_OWNER" "$GITHUB_REPOSITORY" <<'PY'
from pathlib import Path
import sys

account_id, region, ecr_repository, github_owner, github_repository = sys.argv[1:]
replacements = {
    "REPLACE_AWS_ACCOUNT_ID": account_id,
    "REPLACE_AWS_REGION": region,
    "REPLACE_ECR_REPOSITORY": ecr_repository,
    "REPLACE_GITHUB_USER": github_owner,
    "REPLACE_GITHUB_REPOSITORY": github_repository,
}

for filename in [
    Path("k8s/overlays/prod/kustomization.yaml"),
    Path("argocd/application.yaml"),
]:
    text = filename.read_text()
    for old, new in replacements.items():
        text = text.replace(old, new)
    filename.write_text(text)
    print(f"Updated {filename}")
PY

echo "Project configured for AWS account ${AWS_ACCOUNT_ID}."
echo "Git repository: https://github.com/${GITHUB_OWNER}/${GITHUB_REPOSITORY}.git"
