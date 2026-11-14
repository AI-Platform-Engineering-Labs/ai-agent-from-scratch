#!/usr/bin/env bash
# Builds the image in ACR (no local Docker needed) and applies the Kubernetes manifests.
# Run after `terraform apply` and scripts/set-secrets.sh.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TF="terraform -chdir=$ROOT/infra/terraform output -raw"

RG=$($TF resource_group)
AKS=$($TF aks_name)
ACR=$($TF acr_name)
LOGIN_SERVER=$($TF acr_login_server)
export KEY_VAULT_NAME=$($TF key_vault_name)
export TENANT_ID=$($TF tenant_id)
export AGENT_IDENTITY_CLIENT_ID=$($TF agent_identity_client_id)

TAG="${IMAGE_TAG:-$(git -C "$ROOT" rev-parse --short HEAD 2>/dev/null || date +%Y%m%d%H%M%S)}"
export IMAGE="$LOGIN_SERVER/tiny-agent:$TAG"

echo ">> Building $IMAGE in ACR"
az acr build --registry "$ACR" --image "tiny-agent:$TAG" "$ROOT/service"

echo ">> Getting cluster credentials"
az aks get-credentials --resource-group "$RG" --name "$AKS" --overwrite-existing
# Local accounts are disabled, so kubectl authenticates with Entra ID through kubelogin.
kubelogin convert-kubeconfig -l azurecli

echo ">> Applying manifests"
kubectl apply -f "$ROOT/k8s/namespace.yaml"
for f in serviceaccount secretproviderclass deployment service hpa pdb networkpolicy; do
  envsubst '${AGENT_IDENTITY_CLIENT_ID} ${TENANT_ID} ${KEY_VAULT_NAME} ${IMAGE}' < "$ROOT/k8s/$f.yaml" | kubectl apply -f -
done

kubectl -n agent rollout status deploy/agent --timeout=300s
echo ">> Done. Try: kubectl -n agent port-forward svc/agent 8080:80"
