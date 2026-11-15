terraform {
  required_version = ">= 1.6.0"

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 4.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.6"
    }
  }

  # Local state on purpose: sandbox sessions are temporary, so there is nothing worth keeping remotely.
}

provider "azurerm" {
  features {}

  # The sandbox user usually cannot register resource providers. Use the ones already registered.
  resource_provider_registrations = "none"

  # Optional. If null, set ARM_SUBSCRIPTION_ID instead (see docs/deploy-kodekloud-sandbox.md).
  subscription_id = var.subscription_id
}
