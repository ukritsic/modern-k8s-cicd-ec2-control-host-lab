#!/usr/bin/env bash
set -euo pipefail

kubectl get applications -n argocd
kubectl get deployments,pods,svc -n modern-cicd -o wide
kubectl rollout status deployment/fastapi-app -n modern-cicd --timeout=3m

NODE_IP="$(kubectl get nodes -o jsonpath='{.items[0].status.addresses[?(@.type=="ExternalIP")].address}' 2>/dev/null || true)"
if [[ -n "$NODE_IP" ]]; then
  echo "NodePort URL, when EC2 security groups allow TCP 30080 from your IP:"
  echo "  http://${NODE_IP}:30080/"
else
  cat <<'MSG'
No Kubernetes ExternalIP was reported for the first node.
Use its EC2 public IP with port 30080, or use port-forward:
  kubectl port-forward svc/fastapi-app -n modern-cicd 8000:80
  curl http://localhost:8000/
MSG
fi
