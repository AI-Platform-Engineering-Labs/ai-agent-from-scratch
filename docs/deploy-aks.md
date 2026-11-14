# Deploying the agent to AKS (Azure + Terraform)

This deploys `service/` (an HTTP wrapper around the agent loop) to Azure Kubernetes Service. Note that the **model is not hosted by you**: the service calls the Claude API. What runs on AKS is the agent service.

## What gets created

```
Azure subscription
└── rg-tinyagent-prod
    ├── VNet + AKS subnet
    ├── AKS (Azure CNI Overlay + Cilium, Entra ID RBAC, workload identity, autoscaling, zones)
    ├── ACR (nodes pull images with AcrPull; admin user disabled)
    ├── Key Vault (RBAC mode, purge protection) holding the two runtime secrets
    ├── User-assigned identity + federated credential -> ServiceAccount agent/agent-sa
    └── Log Analytics workspace (Container Insights)
```

In the cluster (`k8s/`): namespace with the `restricted` Pod Security level, Deployment (2 replicas, non-root, read-only filesystem, probes), ClusterIP Service, HPA, PodDisruptionBudget, default-deny NetworkPolicy with minimal egress, and a SecretProviderClass that mounts Key Vault secrets as files.

### How secrets flow

Terraform never sees secret values. You store them in Key Vault with `scripts/set-secrets.sh`. The pod gets a federated Entra token through workload identity, the Secrets Store CSI driver reads Key Vault with it and mounts the values at `/mnt/secrets/`, and `service/app.py` reads them from there. No Kubernetes Secret object and no static credentials.

### How the service differs from `agent.py`

| | `agent.py` (CLI) | `service/app.py` (prod) |
|---|---|---|
| Interface | terminal | `POST /v1/run` |
| Tools | `list_dir`, `read_file`, `run_shell` | `list_dir`, `read_file` only, confined to `/app/data` |
| Approval prompt | yes | none, so no shell tool |
| Auth | n/a | bearer token |
| Limits | `MAX_STEPS` | step cap, request size cap, API timeout |
| Observability | printed trace | JSON logs, per-run token totals, health probes |

## Prerequisites

- Azure CLI (`az login`), Terraform >= 1.6, `kubectl` and `kubelogin` (`az aks install-cli`), `envsubst`, `openssl`
- Rights to create resources and role assignments in the subscription (Owner, or Contributor plus User Access Administrator)
- An Anthropic API key

## Steps

### 1. Remote state (once)
```bash
scripts/bootstrap-tfstate.sh
cp infra/terraform/backend.hcl.example infra/terraform/backend.hcl   # paste the values it prints
```

### 2. Infrastructure
```bash
cd infra/terraform
cp terraform.tfvars.example terraform.tfvars    # set subscription_id; strongly consider api_authorized_ip_ranges
terraform init -backend-config=backend.hcl
terraform plan -out tfplan
terraform apply tfplan
```
Before applying, confirm the VM size exists in your region and zones: `az vm list-skus -l centralindia --size Standard_D2ds_v5 -o table`. Adjust `node_vm_size` or `availability_zones` if not.

### 3. Secrets
```bash
cd ../..
scripts/set-secrets.sh        # prompts for the Anthropic key, generates and prints the agent API token
```

### 4. Build and deploy
```bash
scripts/deploy.sh
```
This runs `az acr build`, fetches credentials, and applies the manifests.

### 5. Call it
```bash
kubectl -n agent port-forward svc/agent 8080:80 &
TOKEN=<token printed in step 3>

curl -s localhost:8080/readyz
curl -s -X POST localhost:8080/v1/run \
  -H "Authorization: Bearer $TOKEN" -H "Content-Type: application/json" \
  -d '{"goal": "List the files and tell me who owns the billing migration"}' | python3 -m json.tool
```
The response includes the answer, every step's tool calls and token counts, and totals.

## Run it locally first

```bash
cd service
pip install -r requirements.txt -r requirements-dev.txt
python -m pytest tests            # no API key needed, the model is mocked
export ANTHROPIC_API_KEY=sk-ant-... AGENT_API_TOKEN=dev AGENT_DATA_DIR=$PWD/data
uvicorn app:app --port 8080
```

## Operating it

- **Logs:** `kubectl -n agent logs deploy/agent`, or in Log Analytics (`ContainerLogV2`), filter on `run complete` for per-run steps, tokens and duration.
- **Rotate a secret:** `az keyvault secret set ...`. The CSI driver refreshes the mounted file within a couple of minutes (`app.py` reads the token on every request; the API key is cached, so `kubectl -n agent rollout restart deploy/agent` after changing it).
- **Scale:** the HPA scales 2 to 6 replicas on CPU. The node autoscaler scales nodes between `node_min_count` and `node_max_count`.
- **Cost:** driven mainly by the nodes, Standard tier AKS and Claude API tokens. Use the Azure pricing calculator for your region.
- **Teardown:** `terraform destroy`. The Key Vault has purge protection, so its name stays reserved for the retention period.

## Known gaps / next hardening steps

These are deliberately not in this baseline:

1. **Public access with TLS:** the Service is ClusterIP. Add the AKS application routing add-on (or ingress-nginx) with a certificate, and allow its namespace in `networkpolicy.yaml`.
2. **Private cluster / restricted API server:** set `api_authorized_ip_ranges` now; consider a private cluster later.
3. **Egress control:** egress allows any HTTPS destination. Tighten with Azure Firewall or FQDN-based policy limited to `api.anthropic.com` and Entra.
4. **Rate limiting and per-caller auth:** one shared bearer token today. Move to per-client tokens or Entra ID, and add rate limits and a spend budget, since every request costs money.
5. **CI/CD:** build and deploy from GitHub Actions with OIDC federation instead of running scripts by hand.
6. **Image supply chain:** pin by digest, scan images, enable Defender for Containers.
7. **Terraform state locking and environments:** add a separate state key per environment.
