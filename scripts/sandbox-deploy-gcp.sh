#!/usr/bin/env bash
# Deploys the agent to the GKE cluster created by infra/terraform-sandbox-gcp.
#
# Required: ANTHROPIC_API_KEY, `gcloud` logged in, gke-gcloud-auth-plugin, kubectl, envsubst
# Image:    builds and pushes to Artifact Registry with Docker (linux/amd64), or set IMAGE to a public image.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
# shellcheck source=scripts/lib-sandbox.sh
source "$ROOT/scripts/lib-sandbox.sh"
tf() { terraform -chdir="$ROOT/infra/terraform-sandbox-gcp" output -raw "$1" 2>/dev/null || true; }

: "${ANTHROPIC_API_KEY:?Set ANTHROPIC_API_KEY first}"

PROJECT=$(tf project_id)
CLUSTER=$(tf cluster_name)
ZONE=$(tf zone)
REPO=$(tf artifact_registry_repo)
[ -n "$PROJECT" ] && [ -n "$CLUSTER" ] || { echo "No Terraform outputs. Run terraform apply in infra/terraform-sandbox-gcp first." >&2; exit 1; }

if [ -z "${IMAGE:-}" ]; then
  [ -n "$REPO" ] || { echo "No Artifact Registry repo and IMAGE not set. Set IMAGE=<public image>." >&2; exit 1; }
  TAG="${IMAGE_TAG:-$(git -C "$ROOT" rev-parse --short HEAD 2>/dev/null || date +%Y%m%d%H%M%S)}"
  IMAGE="$REPO/tiny-agent:$TAG"
  echo ">> Building and pushing $IMAGE"
  gcloud auth configure-docker "${REPO%%/*}" --quiet
  docker build --platform linux/amd64 -t "$IMAGE" "$ROOT/service"
  docker push "$IMAGE"
fi

echo ">> Getting cluster credentials"
gcloud container clusters get-credentials "$CLUSTER" --zone "$ZONE" --project "$PROJECT"

deploy_manifests
