#!/usr/bin/env bash
# Deploys the agent to the KodeKloud Azure sandbox cluster created by infra/terraform-sandbox.
#
# Required env:  ANTHROPIC_API_KEY
# Image source (one of):
#   IMAGE=docker.io/youruser/tiny-agent:v1     use an image you already pushed (must be public)
#   or, if the sandbox allowed ACR (enable_acr=true), leave IMAGE unset and it builds in ACR.
# Optional env:  AGENT_API_TOKEN (generated if unset)
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
tf() { terraform -chdir="$ROOT/infra/terraform-sandbox" output -raw "$1" 2>/dev/null || true; }

: "${ANTHROPIC_API_KEY:?Set ANTHROPIC_API_KEY first}"

RG=$(tf resource_group)
AKS=$(tf aks_name)
ACR=$(tf acr_name)
[ -n "$RG" ] && [ -n "$AKS" ] || { echo "No Terraform outputs found. Run terraform apply in infra/terraform-sandbox first." >&2; exit 1; }

if [ -z "${IMAGE:-}" ]; then
  if [ -n "$ACR" ]; then
    TAG="${IMAGE_TAG:-$(git -C "$ROOT" rev-parse --short HEAD 2>/dev/null || date +%Y%m%d%H%M%S)}"
    echo ">> Building tiny-agent:$TAG in ACR $ACR"
    az acr build --registry "$ACR" --image "tiny-agent:$TAG" "$ROOT/service"
    IMAGE="$(tf acr_login_server)/tiny-agent:$TAG"
  else
    echo "No ACR and IMAGE not set. Build and push a public image first, then:" >&2
    echo "  IMAGE=docker.io/<user>/tiny-agent:v1 $0" >&2
    exit 1
  fi
fi
export IMAGE

AGENT_API_TOKEN="${AGENT_API_TOKEN:-$(openssl rand -base64 36 | tr -d '\n')}"

echo ">> Getting cluster credentials"
az aks get-credentials --resource-group "$RG" --name "$AKS" --overwrite-existing

echo ">> Applying manifests (image: $IMAGE)"
kubectl apply -f "$ROOT/k8s-sandbox/namespace.yaml"
# Secret values are passed through file descriptors, not command-line arguments.
kubectl -n agent create secret generic agent-secrets \
  --from-file=anthropic-api-key=<(printf %s "$ANTHROPIC_API_KEY") \
  --from-file=agent-api-token=<(printf %s "$AGENT_API_TOKEN") \
  --dry-run=client -o yaml | kubectl apply -f -
for f in deployment service; do
  envsubst '${IMAGE}' < "$ROOT/k8s-sandbox/$f.yaml" | kubectl apply -f -
done

kubectl -n agent rollout status deploy/agent --timeout=300s
echo
echo ">> Done."
echo "Agent API token (save it; it is only shown now): $AGENT_API_TOKEN"
echo "Try: kubectl -n agent port-forward svc/agent 8080:80"
