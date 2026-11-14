#!/usr/bin/env bash
# Stores the two runtime secrets in Key Vault. Values never touch Terraform state or shell history.
# Usage: scripts/set-secrets.sh            (reads key from a hidden prompt, generates the API token)
set -euo pipefail

TF_DIR="$(dirname "$0")/../infra/terraform"
KV=$(terraform -chdir="$TF_DIR" output -raw key_vault_name)

read -r -s -p "Anthropic API key: " ANTHROPIC_KEY; echo
[ -n "$ANTHROPIC_KEY" ] || { echo "empty key" >&2; exit 1; }
AGENT_TOKEN=$(openssl rand -base64 36 | tr -d '\n')

az keyvault secret set --vault-name "$KV" --name anthropic-api-key --value "$ANTHROPIC_KEY" --output none
az keyvault secret set --vault-name "$KV" --name agent-api-token   --value "$AGENT_TOKEN"   --output none

echo "Secrets stored in Key Vault '$KV'."
echo
echo "Your agent API token (shown once; also retrievable from Key Vault):"
echo "$AGENT_TOKEN"
