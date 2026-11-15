variable "resource_group_name" {
  description = "The resource group the playground already created for you. You usually cannot create new resource groups."
  type        = string
}

variable "subscription_id" {
  description = "Subscription ID. Leave null and export ARM_SUBSCRIPTION_ID instead if you prefer."
  type        = string
  default     = null
}

variable "name_prefix" {
  type    = string
  default = "tinyagent"
}

variable "node_vm_size" {
  description = "The playground only allows Standard_B2s for AKS nodes."
  type        = string
  default     = "Standard_B2s"
}

variable "node_count" {
  description = "Fixed node count (no autoscaler in the sandbox). Raise to 2 only if the playground allows it."
  type        = number
  default     = 1
}

variable "enable_acr" {
  description = "Create a container registry. Set false if the playground blocks ACR, then push the image to a public registry instead."
  type        = bool
  default     = false
}

variable "acr_pull_role_assignment" {
  description = "Let the nodes pull from ACR via a role assignment. Set false if the playground blocks role assignments."
  type        = bool
  default     = true
}
