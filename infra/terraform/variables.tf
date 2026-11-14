variable "subscription_id" {
  description = "Azure subscription ID to deploy into."
  type        = string
}

variable "project" {
  description = "Short name used as a prefix for resources (lowercase letters and digits)."
  type        = string
  default     = "tinyagent"
}

variable "environment" {
  description = "Environment name, e.g. dev or prod."
  type        = string
  default     = "prod"
}

variable "location" {
  description = "Azure region."
  type        = string
  default     = "centralindia"
}

variable "kubernetes_version" {
  description = "AKS Kubernetes version. Null uses the region default. Check: az aks get-versions -l <region>"
  type        = string
  default     = null
}

variable "aks_sku_tier" {
  description = "Free has no uptime SLA. Use Standard for production."
  type        = string
  default     = "Standard"
}

variable "node_vm_size" {
  description = "VM size for the node pool. Check availability: az vm list-skus -l <region> --size Standard_D2 -o table"
  type        = string
  default     = "Standard_D2ds_v5"
}

variable "node_min_count" {
  type    = number
  default = 2
}

variable "node_max_count" {
  type    = number
  default = 4
}

variable "availability_zones" {
  description = "Zones for the node pool. Set to [] if the VM size is not available in zones."
  type        = list(string)
  default     = ["1", "2"]
}

variable "vnet_address_space" {
  type    = list(string)
  default = ["10.20.0.0/16"]
}

variable "aks_subnet_prefix" {
  type    = string
  default = "10.20.0.0/22"
}

variable "k8s_namespace" {
  description = "Namespace the agent runs in. Must match k8s/ manifests."
  type        = string
  default     = "agent"
}

variable "k8s_service_account" {
  description = "ServiceAccount the agent runs as. Must match k8s/ manifests."
  type        = string
  default     = "agent-sa"
}

variable "admin_group_object_ids" {
  description = "Entra ID group object IDs granted cluster-admin through Azure RBAC. Leave empty to grant the deploying principal instead."
  type        = list(string)
  default     = []
}

variable "api_authorized_ip_ranges" {
  description = "CIDRs allowed to reach the Kubernetes API server. Empty means open to the internet (RBAC still applies). Strongly recommended to set, e.g. [\"203.0.113.4/32\"]."
  type        = list(string)
  default     = []
}

variable "tags" {
  type    = map(string)
  default = {}
}
