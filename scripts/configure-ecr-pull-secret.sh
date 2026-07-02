#!/usr/bin/env bash
set -euo pipefail

AWS_REGION="${AWS_REGION:-ap-southeast-1}"
NAMESPACE="${NAMESPACE:-modern-cicd}"
SECRET_NAME="${SECRET_NAME:-ecr-registry}"
AWS_ACCOUNT_ID="$(aws sts get-caller-identity --query Account --output text)"
ECR_REGISTRY="${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com"
PASSWORD="$(aws ecr get-login-password --region "$AWS_REGION")"

kubectl create namespace "$NAMESPACE" --dry-run=client -o yaml | kubectl apply -f -

kubectl create secret docker-registry "$SECRET_NAME" \
  --namespace "$NAMESPACE" \
  --docker-server="$ECR_REGISTRY" \
  --docker-username=AWS \
  --docker-password="$PASSWORD" \
  --dry-run=client -o yaml | kubectl apply -f -

echo "Created or refreshed $NAMESPACE/$SECRET_NAME for $ECR_REGISTRY"
echo "Important: ECR authorization tokens expire. Re-run this script before a later image pull,"
echo "or configure the kubelet image credential-provider plugin on every worker node for production."
