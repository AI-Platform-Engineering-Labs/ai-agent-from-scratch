#!/usr/bin/env bash
# Shared helpers for the sandbox deploy scripts. Source this file; do not run it.

# deploy_manifests: creates the Secret and applies k8s-sandbox/ for the current kubectl context.
# Needs: ROOT, IMAGE, ANTHROPIC_API_KEY. Optional: AGENT_API_TOKEN (generated if unset).
deploy_manifests() {
  export IMAGE
  AGENT_API_TOKEN="${AGENT_API_TOKEN:-$(openssl rand -base64 36 | tr -d '\n')}"

  echo ">> Applying manifests (image: $IMAGE)"
  kubectl apply -f "$ROOT/k8s-sandbox/namespace.yaml"
  # Secret values go through file descriptors, not command-line arguments.
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
}
