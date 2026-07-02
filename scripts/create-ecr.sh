#!/usr/bin/env bash
set -euo pipefail

AWS_REGION="${AWS_REGION:-ap-southeast-1}"
ECR_REPOSITORY="${ECR_REPOSITORY:-modern-k8s-cicd-app}"

aws sts get-caller-identity >/dev/null

if aws ecr describe-repositories \
  --region "$AWS_REGION" \
  --repository-names "$ECR_REPOSITORY" >/dev/null 2>&1; then
  echo "ECR repository already exists: $ECR_REPOSITORY"
else
  aws ecr create-repository \
    --region "$AWS_REGION" \
    --repository-name "$ECR_REPOSITORY" \
    --image-scanning-configuration scanOnPush=true \
    --encryption-configuration encryptionType=AES256 >/dev/null
  echo "Created ECR repository: $ECR_REPOSITORY"
fi

AWS_ACCOUNT_ID="$(aws sts get-caller-identity --query Account --output text)"
echo "Image registry: ${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com/${ECR_REPOSITORY}"
