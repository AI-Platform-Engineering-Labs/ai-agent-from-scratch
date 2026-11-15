variable "region" {
  description = "Use a region the playground allows (the lab page lists them, e.g. us-east-2 or us-west-2)."
  type        = string
  default     = "us-east-2"
}

variable "name_prefix" {
  type    = string
  default = "tinyagent"
}

variable "kubernetes_version" {
  description = "EKS version. Null uses the AWS default."
  type        = string
  default     = null
}

variable "cluster_role_name" {
  description = "Existing IAM role for the EKS control plane. The playground permits eksClusterRole."
  type        = string
  default     = "eksClusterRole"
}

variable "node_role_name" {
  description = "Existing IAM role for worker nodes. If null, Terraform tries to create one (may be denied in the sandbox: then pick a pre-created role in the IAM console and set this)."
  type        = string
  default     = null
}

variable "create_node_group" {
  description = "Create a managed node group. Managed node groups have been unreliable in the playground; if creation fails, set false and add self-managed nodes yourself."
  type        = bool
  default     = true
}

variable "node_instance_type" {
  description = "Playground allows nano/micro/small/medium of the t1, t2, t3 classes. Use t3.small if t3.medium is denied."
  type        = string
  default     = "t3.medium"
}

variable "node_count" {
  type    = number
  default = 2
}

variable "node_disk_gb" {
  description = "Playground max is 30 GB per volume, gp2 only."
  type        = number
  default     = 20
}

variable "enable_ecr" {
  description = "Create an ECR repository for the image."
  type        = bool
  default     = true
}
