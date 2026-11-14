# Deploying to the KodeKloud Azure sandbox

A cut-down variant of [the AKS deployment](deploy-aks.md) for practising in a KodeKloud Azure Playground. **This is for learning, not production**: it drops the security and reliability features the sandbox will not let you create.

Everything runs from your own machine. The playground only provides a temporary Azure subscription.

## What is different from the prod setup

| Area | Prod (`infra/terraform`, `k8s`) | Sandbox (`infra/terraform-sandbox`, `k8s-sandbox`) |
|---|---|---|
| Region | `centralindia` | the region of the pre-created resource group (the playground offers US regions) |
| Resource group | created by Terraform | **already exists**, read with a data source |
| Nodes | `Standard_D2ds_v5`, 2 to 4, autoscaling, zones | `Standard_B2s`, 1 fixed node |
| Cluster auth | Entra ID RBAC, local accounts disabled | default cluster credentials |
| Monitoring | Log Analytics / Container Insights | none (playground may block it) |
| Secrets | Key Vault + workload identity + CSI driver | plain Kubernetes Secret created by the script |
| Registry | ACR with managed pull | ACR optional; otherwise a public image |
| Terraform state | remote (Azure storage) | local file |
| Pods | 2 replicas, HPA, PDB, NetworkPolicy | 1 replica |

The application code is identical: `service/app.py` reads secrets from `/mnt/secrets`, which is a Key Vault mount in prod and a Kubernetes Secret volume here.

## Prerequisites

- A KodeKloud Pro account with the Azure Playground launched. Note the credentials, subscription and the resource group it shows or creates.
- Terraform >= 1.6, Azure CLI, `kubectl`, `envsubst` (package `gettext`), `openssl`
- An Anthropic API key
- If you cannot use ACR: Docker and an account on a registry that allows public images (Docker Hub or GHCR)

## Steps

### 1. Sign in and find the resource group
Log in with the credentials the playground gives you, then:
```bash
az login                                   # or the service principal login shown by the playground
az account show --query id -o tsv         # subscription id
az group list -o table                    # find your pre-created resource group
export ARM_SUBSCRIPTION_ID=$(az account show --query id -o tsv)
```

### 2. Create the cluster
```bash
cd infra/terraform-sandbox
cp terraform.tfvars.example terraform.tfvars    # set resource_group_name
terraform init
terraform apply
```
If AKS creation is rejected with `RequestDisallowedByPolicy`, check the message for which resource was denied (see Troubleshooting).

### 3. Get an image
**Option A: ACR allowed.** Set `enable_acr = true` in `terraform.tfvars`, re-run `terraform apply`, and skip to step 4. The script builds the image in ACR. If the role assignment is blocked, also set `acr_pull_role_assignment = false` and use option B.

**Option B: public registry.**
```bash
docker build -t docker.io/<user>/tiny-agent:v1 service
docker push docker.io/<user>/tiny-agent:v1       # make the repository public
```
The image contains only sample data and no secrets, so a public repository is fine. If you use a private repository you must add an image pull secret yourself.

### 4. Deploy
```bash
cd ../..
export ANTHROPIC_API_KEY=sk-ant-...
IMAGE=docker.io/<user>/tiny-agent:v1 scripts/sandbox-deploy.sh      # option B
scripts/sandbox-deploy.sh                                          # option A
```
The script prints the generated agent API token once. Save it.

### 5. Call it
```bash
kubectl -n agent port-forward svc/agent 8080:80 &
curl -s localhost:8080/readyz
curl -s -X POST localhost:8080/v1/run \
  -H "Authorization: Bearer $TOKEN" -H "Content-Type: application/json" \
  -d '{"goal": "List the files and tell me who owns the billing migration"}' | python3 -m json.tool
```

## Sandbox lifecycle

- Playground sessions expire and the subscription is reset, so the cluster disappears. Terraform's local state then points at resources that no longer exist: delete `terraform.tfstate*` and `.terraform/` before the next session and re-run from step 1.
- `terraform destroy` before the session ends is good practice but not required.
- The Anthropic API key is stored in a plain Kubernetes Secret in the sandbox cluster. Use a key with a low spend limit, and revoke it when you are done.

## Troubleshooting

| Symptom | What to try |
|---|---|
| `RequestDisallowedByPolicy` | The sandbox denies services not on its allow-list. Read which resource was blocked. If it is a load balancer or similar, try again later or ask KodeKloud support; they have changed the policy before. |
| VM size not allowed | Only `Standard_B2s` is allowed for AKS nodes. Keep the default. |
| Not allowed to create a resource group | Use the one the playground pre-created via `resource_group_name`. |
| Provider not registered errors | Providers must already be registered. Ask a lab instructor or try the portal; the sandbox user usually cannot register them. |
| ACR or role assignment denied | Set `enable_acr = false` (or `acr_pull_role_assignment = false`) and use a public registry image. |
| Pod `ImagePullBackOff` | The image is private or the tag is wrong. Make the repository public or check the name. |
| Pod `Pending` | One B2s node is small; check `kubectl -n agent describe pod`. System pods use part of the 4 GB. |
| `terraform apply` fails to authenticate | Run `az login` again and export `ARM_SUBSCRIPTION_ID`. The playground credentials may have expired. |
