data "aws_caller_identity" "current" {}

# Use the default VPC: no NAT gateway, nodes get public IPs to pull images.
data "aws_vpc" "default" {
  default = true
}

data "aws_subnets" "default" {
  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.default.id]
  }
  filter {
    name   = "default-for-az"
    values = ["true"]
  }
}

data "aws_iam_role" "cluster" {
  name = var.cluster_role_name
}

data "aws_iam_role" "node_existing" {
  count = var.create_node_group && var.node_role_name != null ? 1 : 0
  name  = var.node_role_name
}

# ---------------------------------------------------------------- Node role (only if not supplied)
resource "aws_iam_role" "node" {
  count = var.create_node_group && var.node_role_name == null ? 1 : 0
  name  = "${var.name_prefix}-sandbox-node"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "ec2.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy_attachment" "node" {
  for_each = var.create_node_group && var.node_role_name == null ? toset([
    "arn:aws:iam::aws:policy/AmazonEKSWorkerNodePolicy",
    "arn:aws:iam::aws:policy/AmazonEKS_CNI_Policy",
    "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly",
  ]) : toset([])
  role       = aws_iam_role.node[0].name
  policy_arn = each.value
}

locals {
  node_role_arn = var.create_node_group ? (
    var.node_role_name != null ? data.aws_iam_role.node_existing[0].arn : aws_iam_role.node[0].arn
  ) : null
}

# ---------------------------------------------------------------- Registry
resource "aws_ecr_repository" "agent" {
  count        = var.enable_ecr ? 1 : 0
  name         = "tiny-agent"
  force_delete = true

  image_scanning_configuration {
    scan_on_push = true
  }
}

# ---------------------------------------------------------------- EKS
resource "aws_eks_cluster" "this" {
  name     = "${var.name_prefix}-sandbox"
  role_arn = data.aws_iam_role.cluster.arn
  version  = var.kubernetes_version

  vpc_config {
    subnet_ids              = data.aws_subnets.default.ids
    endpoint_public_access  = true
    endpoint_private_access = false
  }

  # The identity running Terraform becomes cluster admin, so kubectl works right away.
  access_config {
    authentication_mode                         = "API_AND_CONFIG_MAP"
    bootstrap_cluster_creator_admin_permissions = true
  }
}

# gp2, small disk: the playground rejects other volume types and sizes.
resource "aws_launch_template" "nodes" {
  count       = var.create_node_group ? 1 : 0
  name_prefix = "${var.name_prefix}-sandbox-"

  block_device_mappings {
    device_name = "/dev/xvda"
    ebs {
      volume_size           = var.node_disk_gb
      volume_type           = "gp2"
      delete_on_termination = true
    }
  }
}

resource "aws_eks_node_group" "nodes" {
  count           = var.create_node_group ? 1 : 0
  cluster_name    = aws_eks_cluster.this.name
  node_group_name = "${var.name_prefix}-nodes"
  node_role_arn   = local.node_role_arn
  subnet_ids      = data.aws_subnets.default.ids
  instance_types  = [var.node_instance_type]

  scaling_config {
    desired_size = var.node_count
    min_size     = 1
    max_size     = var.node_count
  }

  launch_template {
    id      = aws_launch_template.nodes[0].id
    version = aws_launch_template.nodes[0].latest_version
  }

  depends_on = [aws_iam_role_policy_attachment.node]
}
