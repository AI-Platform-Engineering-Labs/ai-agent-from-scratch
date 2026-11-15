variable "project_id" {
  description = "The project the playground created for you (its name starts with clgcporg)."
  type        = string
}

variable "region" {
  description = "The playground only allows us-west1 and us-central1."
  type        = string
  default     = "us-central1"
}

variable "zone" {
  description = "A zone inside the region. The cluster is zonal on purpose: a regional cluster multiplies nodes and disk."
  type        = string
  default     = "us-central1-a"
}

variable "name_prefix" {
  type    = string
  default = "tinyagent"
}

variable "machine_type" {
  description = "Playground allows e2-medium or smaller, or n1-standard-2 or smaller."
  type        = string
  default     = "e2-medium"
}

variable "node_count" {
  type    = number
  default = 1
}

variable "disk_size_gb" {
  description = "Playground allows 50 GB of disk in total, standard persistent disks only."
  type        = number
  default     = 30
}

variable "enable_artifact_registry" {
  description = "Create an Artifact Registry repository. Off by default because the playground documents Container Registry, not Artifact Registry. Otherwise push to a public registry."
  type        = bool
  default     = false
}
