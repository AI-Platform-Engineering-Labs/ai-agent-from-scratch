data "azurerm_resource_group" "rg" {
  name = var.resource_group_name
}

resource "random_string" "suffix" {
  length  = 5
  upper   = false
  special = false
}

# ---------------------------------------------------------------- Optional registry
resource "azurerm_container_registry" "acr" {
  count               = var.enable_acr ? 1 : 0
  name                = "${var.name_prefix}${random_string.suffix.result}"
  resource_group_name = data.azurerm_resource_group.rg.name
  location            = data.azurerm_resource_group.rg.location
  sku                 = "Basic"
  admin_enabled       = false
}

# ---------------------------------------------------------------- AKS (minimal)
resource "azurerm_kubernetes_cluster" "aks" {
  name                = "aks-${var.name_prefix}-sandbox"
  location            = data.azurerm_resource_group.rg.location
  resource_group_name = data.azurerm_resource_group.rg.name
  dns_prefix          = "${var.name_prefix}-sandbox"
  sku_tier            = "Free"

  default_node_pool {
    name       = "system"
    vm_size    = var.node_vm_size
    node_count = var.node_count
  }

  identity {
    type = "SystemAssigned"
  }

  network_profile {
    network_plugin      = "azure"
    network_plugin_mode = "overlay"
    load_balancer_sku   = "standard"
  }

  # Deliberately omitted vs. the prod config because the sandbox restricts them:
  #   monitoring (oms_agent), Entra ID RBAC, workload identity, Key Vault CSI, autoscaling, zones.
}

resource "azurerm_role_assignment" "acr_pull" {
  count                            = var.enable_acr && var.acr_pull_role_assignment ? 1 : 0
  scope                            = azurerm_container_registry.acr[0].id
  role_definition_name             = "AcrPull"
  principal_id                     = azurerm_kubernetes_cluster.aks.kubelet_identity[0].object_id
  skip_service_principal_aad_check = true
}
