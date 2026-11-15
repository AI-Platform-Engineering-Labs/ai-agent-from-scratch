# Deploying to the KodeKloud AWS sandbox (EKS)

Learning-only variant for a KodeKloud AWS Playground. Terraform is in `infra/terraform-sandbox-aws/`, the app manifests are shared with the other sandboxes (`k8s-sandbox/`), and the deploy script is `scripts/sandbox-deploy-aws.sh`.

## What the sandbox forces

| Sandbox rule | What the Terraform does |
|---|---|
| Limited regions (Oregon / Ohio listed) | `region` defaults to `us-east-2`; check your lab page |
| EKS control-plane role: only `eksClusterRole` is permitted | reads the existing role instead of creating one (`cluster_role_name`) |
| Node instance types: nano/micro/small/medium of t1, t2, t3 | `t3.medium` (use `t3.small` if denied) |
| Disks: `gp2` only, max 30 GB per volume | launch template with a 20 GB `gp2` root volume |
| IAM changes are restricted | node role is created only if you do not supply one (`node_role_name`) |
| Managed node groups and Fargate have been reported as not working | `create_node_group = false` lets you build the cluster only and add self-managed nodes yourself |
| NAT gateways and big networking add cost | uses the default VPC; nodes get public IPs |

## Prerequisites

Terraform >= 1.6, AWS CLI v2, `kubectl`, `envsubst` (`gettext`), `openssl`, Docker (to build and push the image), an Anthropic API key.

## Steps

### 1. Credentials
Launch the playground and note the console login. Terraform and the AWS CLI need programmatic credentials for the sandbox IAM user: create an access key in the IAM console if the playground allows it, then:
```bash
aws configure           # or export AWS_ACCESS_KEY_ID / AWS_SECRET_ACCESS_KEY / AWS_DEFAULT_REGION
aws sts get-caller-identity
```
If you cannot create access keys, run Terraform from AWS CloudShell in the console if the playground offers it.

### 2. Cluster
```bash
cd infra/terraform-sandbox-aws
cp terraform.tfvars.example terraform.tfvars
terraform init
terraform apply
```
Cluster creation takes around 10 minutes, node group a few more.

### 3. Deploy
```bash
cd ../..
export ANTHROPIC_API_KEY=sk-ant-...
scripts/sandbox-deploy-aws.sh                       # builds and pushes to ECR, then deploys
IMAGE=docker.io/<user>/tiny-agent:v1 scripts/sandbox-deploy-aws.sh   # or use a public image you pushed
```
The image is built for `linux/amd64`, which matters if you are on an Apple Silicon laptop. The script prints the generated API token once.

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
| `AccessDenied` on `iam:CreateRole` | Find a pre-created node role in the IAM console and set `node_role_name` |
| `eksClusterRole` not found | Check the exact role name the playground created and set `cluster_role_name` |
| Node group stuck `CREATING` / `NodeCreationFailure` | Try `t3.small`; check the node role has the three standard EKS node policies; otherwise set `create_node_group = false` and add self-managed nodes |
| Pods `ImagePullBackOff` from ECR | The node role needs `AmazonEC2ContainerRegistryReadOnly` |
| `kubectl` unauthorized | Run `aws eks update-kubeconfig` as the same IAM user that ran Terraform |
| Session expired | Sandbox accounts are reset. Delete `terraform.tfstate*` and `.terraform/` and start again |

## Cleanup
`terraform destroy` (ECR uses `force_delete`, so images do not block it). The playground reset removes everything anyway.

## Sources
KodeKloud: [AWS playground](https://kodekloud.com/cloud-playgrounds/aws), [AWS free playground](https://kodekloud.com/cloud-playgrounds/aws-free), community threads on [EKS node limits](https://kodekloud.com/community/t/aws-eks-unable-to-create-managed-node-group-or-self-managed/241451) and [self-managed nodes](https://kodekloud.com/community/t/seeking-help-to-solve-my-issues/271279). Playground limits change; the lab page is authoritative.
