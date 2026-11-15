terraform {
  required_version = ">= 1.6.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 5.60, < 7.0"
    }
  }

  # Local state on purpose: sandbox sessions are temporary.
}

provider "aws" {
  region = var.region
}
