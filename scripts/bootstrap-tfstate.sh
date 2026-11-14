#!/usr/bin/env bash
# Creates the storage account that holds Terraform remote state.
# Run once, before `terraform init`. Requires: az login, and rights to create resources.
set -euo pipefail

LOCATION="${LOCATION:-centralindia}"
PROJECT="${PROJECT:-tinyagent}"
RG="rg-tfstate-${PROJECT}"
SA="tfstate${PROJECT}$(openssl rand -hex 3)"
CONTAINER="tfstate"

az group create --name "$RG" --location "$LOCATION" --output none
az storage account create \
  --name "$SA" --resource-group "$RG" --location "$LOCATION" \
  --sku Standard_LRS --kind StorageV2 \
  --min-tls-version TLS1_2 --allow-blob-public-access false \
  --allow-shared-key-access false --output none
az storage account blob-service-properties update \
  --account-name "$SA" --resource-group "$RG" \
  --enable-versioning true --output none

# Give the current user data-plane access (state uses Entra ID auth, not keys).
ME=$(az ad signed-in-user show --query id -o tsv)
SCOPE=$(az storage account show --name "$SA" --resource-group "$RG" --query id -o tsv)
az role assignment create --assignee-object-id "$ME" --assignee-principal-type User \
  --role "Storage Blob Data Contributor" --scope "$SCOPE" --output none

# Role assignments can take a minute to propagate before the container can be created.
for i in 1 2 3 4 5 6; do
  az storage container create --name "$CONTAINER" --account-name "$SA" --auth-mode login --output none && break
  echo "waiting for role assignment to propagate..."; sleep 15
done

cat <<OUT

Done. Put this in infra/terraform/backend.hcl:

resource_group_name  = "$RG"
storage_account_name = "$SA"
container_name       = "$CONTAINER"
key                  = "tiny-agent-prod.tfstate"
use_azuread_auth     = true
OUT
