#!/usr/bin/env bash
# Deploys the agent to the EKS cluster created by infra/terraform-sandbox-aws.
#
# Required: ANTHROPIC_API_KEY, working `aws` credentials, kubectl, envsubst
# Image:    builds and pushes to ECR with Docker (linux/amd64), or set IMAGE to a public image.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
# shellcheck source=scripts/lib-sandbox.sh
source "$ROOT/scripts/lib-sandbox.sh"
tf() { terraform -chdir="$ROOT/infra/terraform-sandbox-aws" output -raw "$1" 2>/dev/null || true; }

: "${ANTHROPIC_API_KEY:?Set ANTHROPIC_API_KEY first}"

REGION=$(tf region)
CLUSTER=$(tf cluster_name)
ECR_URL=$(tf ecr_repository_url)
[ -n "$REGION" ] && [ -n "$CLUSTER" ] || { echo "No Terraform outputs. Run terraform apply in infra/terraform-sandbox-aws first." >&2; exit 1; }

if [ -z "${IMAGE:-}" ]; then
  [ -n "$ECR_URL" ] || { echo "No ECR repo and IMAGE not set. Set IMAGE=<public image>." >&2; exit 1; }
  TAG="${IMAGE_TAG:-$(git -C "$ROOT" rev-parse --short HEAD 2>/dev/null || date +%Y%m%d%H%M%S)}"
  IMAGE="$ECR_URL:$TAG"
  echo ">> Building and pushing $IMAGE"
  aws ecr get-login-password --region "$REGION" | docker login --username AWS --password-stdin "${ECR_URL%%/*}"
  docker build --platform linux/amd64 -t "$IMAGE" "$ROOT/service"
  docker push "$IMAGE"
fi

echo ">> Getting cluster credentials"
aws eks update-kubeconfig --region "$REGION" --name "$CLUSTER"

deploy_manifests
