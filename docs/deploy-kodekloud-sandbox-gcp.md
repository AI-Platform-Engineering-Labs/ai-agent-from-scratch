# Deploying to the KodeKloud Google Cloud sandbox (GKE)

Learning-only variant for a KodeKloud Google Cloud Playground. Terraform is in `infra/terraform-sandbox-gcp/`, the app manifests are shared (`k8s-sandbox/`), and the deploy script is `scripts/sandbox-deploy-gcp.sh`.

## What the sandbox forces

| Sandbox rule | What the Terraform does |
|---|---|
| Regions: only US West 1 and US Central | `region = us-central1`, `zone = us-central1-a` |
| A pre-created project named `clgcporg*` | you pass it as `project_id`; nothing creates projects |
| Machine types: `e2-medium` or smaller, or `n1-standard-2` or smaller | `e2-medium` |
| Disks: standard persistent disk only, 50 GB total | `pd-standard`, 30 GB, one node |
| GKE Standard only (no Autopilot) | `google_container_cluster` in Standard mode |
| Disk quota is tiny | **zonal** cluster, node settings on the cluster itself (no default pool that would first try a 100 GB disk) |
| Container Registry is documented, in US regions | Artifact Registry is optional and off by default; otherwise push to a public registry |
| Credentials are valid for about 3 hours | plan for short sessions |

## Prerequisites

Terraform >= 1.6, Google Cloud CLI with `gke-gcloud-auth-plugin` (`gcloud components install gke-gcloud-auth-plugin`), `kubectl`, `envsubst` (`gettext`), `openssl`, Docker, an Anthropic API key.

## Steps

### 1. Sign in
Launch the playground and sign in with the temporary Google account it gives you.
```bash
gcloud auth login
gcloud auth application-default login     # Terraform uses these credentials
gcloud projects list                       # find the clgcporg* project
gcloud services list --enabled --project <project> | grep -i container   # GKE API should be on
```
If the Kubernetes Engine API is not enabled: `gcloud services enable container.googleapis.com --project <project>`.

### 2. Cluster
```bash
cd infra/terraform-sandbox-gcp
cp terraform.tfvars.example terraform.tfvars      # set project_id
terraform init
terraform apply
```

### 3. Deploy
```bash
cd ../..
export ANTHROPIC_API_KEY=sk-ant-...
IMAGE=docker.io/<user>/tiny-agent:v1 scripts/sandbox-deploy-gcp.sh   # public image (safest choice)
scripts/sandbox-deploy-gcp.sh        # only if enable_artifact_registry = true and allowed
```
Build and push a public image first for the first option:
```bash
docker build --platform linux/amd64 -t docker.io/<user>/tiny-agent:v1 service && docker push docker.io/<user>/tiny-agent:v1
```
The image contains only sample data and no secrets. The script prints the generated API token once.

### 4. Call it
```bash
kubectl -n agent port-forward svc/agent 8080:80 &
curl -s -X POST localhost:8080/v1/run \
  -H "Authorization: Bearer $TOKEN" -H "Content-Type: application/json" \
  -d '{"goal": "List the files and tell me who owns the billing migration"}' | python3 -m json.tool
```

## Troubleshooting

| Symptom | What to try |
|---|---|
| Quota or org-policy error on disk or machine | Keep `e2-medium`, `pd-standard`, one node, total disk under 50 GB |
| `Kubernetes Engine API has not been used` | `gcloud services enable container.googleapis.com` |
| Cluster creation permission denied | Confirm you are using the sandbox project and the sandbox account (`gcloud config list`) |
| `executable gke-gcloud-auth-plugin not found` | `gcloud components install gke-gcloud-auth-plugin` |
| Pods `Pending` | One e2-medium node is small; check `kubectl -n agent describe pod` |
| Artifact Registry denied | Leave `enable_artifact_registry = false` and use a public image |
| Credentials expired (about 3 hours) | Launch a new playground, delete `terraform.tfstate*` and `.terraform/`, start again |

## Cleanup
`terraform destroy`; the sandbox reset removes everything anyway.

## Sources
KodeKloud: [GCP playground restrictions](https://support.kodekloud.com/gcp-playground), [what GCP playgrounds support](https://support.kodekloud.com/what-does-gcp-support), [GKE playground how-to](https://kodekloud.com/community/t/playground-series-how-to-create-a-managed-kubernetes-cluster-with-google-kubernetes-engine/230314). Playground limits change; the lab page is authoritative.
