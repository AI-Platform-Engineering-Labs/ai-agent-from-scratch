terraform {
  required_version = ">= 1.6.0"

  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 6.0"
    }
  }

  # Local state on purpose: sandbox sessions are temporary.
}

provider "google" {
  project = var.project_id
  region  = var.region
}
