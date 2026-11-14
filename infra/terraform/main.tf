data "azurerm_client_config" "current" {}

resource "random_string" "suffix" {
  length  = 5
  upper   = false
  special = false
}

locals {
  base_name = "${var.project}-${var.environment}"
  # ACR names: 5-50 chars, alphanumeric only. Key Vault names: 3-24 chars.
  acr_name = "${var.project}${var.environment}${random_string.suffix.result}"
  kv_name  = substr("${var.project}-${var.environment}-${random_string.suffix.result}", 0, 24)

  tags = merge({
    project     = var.project
    environment = var.environment
    managed_by  = "terraform"
  }, var.tags)

  admin_object_ids = length(var.admin_group_object_ids) > 0 ? var.admin_group_object_ids : [data.azurerm_client_config.current.object_id]
}

resource "azurerm_resource_group" "rg" {
  name     = "rg-${local.base_name}"
  location = var.location
  tags     = local.tags
}

# ---------------------------------------------------------------- Network
resource "azurerm_virtual_network" "vnet" {
  name                = "vnet-${local.base_name}"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
  address_space       = var.vnet_address_space
  tags                = local.tags
}

resource "azurerm_subnet" "aks" {
  name                 = "snet-aks"
  resource_group_name  = azurerm_resource_group.rg.name
  virtual_network_name = azurerm_virtual_network.vnet.name
  address_prefixes     = [var.aks_subnet_prefix]
}

# ---------------------------------------------------------------- Observability
resource "azurerm_log_analytics_workspace" "logs" {
  name                = "log-${local.base_name}"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
  sku                 = "PerGB2018"
  retention_in_days   = 30
  tags                = local.tags
}

# ---------------------------------------------------------------- Registry
resource "azurerm_container_registry" "acr" {
  name                = local.acr_name
  resource_group_name = azurerm_resource_group.rg.name
  location            = azurerm_resource_group.rg.location
  sku                 = "Standard"
  admin_enabled       = false
  tags                = local.tags
}

# ---------------------------------------------------------------- AKS
resource "azurerm_kubernetes_cluster" "aks" {
  name                = "aks-${local.base_name}"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
  dns_prefix          = local.base_name
  kubernetes_version  = var.kubernetes_version
  sku_tier            = var.aks_sku_tier

  # Workload identity lets pods use Entra ID without stored credentials.
  oidc_issuer_enabled       = true
  workload_identity_enabled = true

  # Humans authenticate with Entra ID; local (static) admin accounts are off.
  local_account_disabled = true

  automatic_upgrade_channel = "patch"

  default_node_pool {
    name                 = "system"
    vm_size              = var.node_vm_size
    vnet_subnet_id       = azurerm_subnet.aks.id
    auto_scaling_enabled = true
    min_count            = var.node_min_count
    max_count            = var.node_max_count
    zones                = var.availability_zones
    os_disk_type         = "Managed"
    os_disk_size_gb      = 64
    upgrade_settings {
      max_surge = "33%"
    }
  }

  identity {
    type = "SystemAssigned"
  }

  azure_active_directory_role_based_access_control {
    azure_rbac_enabled = true
    tenant_id          = data.azurerm_client_config.current.tenant_id
  }

  network_profile {
    network_plugin      = "azure"
    network_plugin_mode = "overlay"
    network_data_plane  = "cilium"
    network_policy      = "cilium"
    load_balancer_sku   = "standard"
    outbound_type       = "loadBalancer"
  }

  dynamic "api_server_access_profile" {
    for_each = length(var.api_authorized_ip_ranges) > 0 ? [1] : []
    content {
      authorized_ip_ranges = var.api_authorized_ip_ranges
    }
  }

  # Mounts Key Vault secrets into pods via the Secrets Store CSI driver.
  key_vault_secrets_provider {
    secret_rotation_enabled  = true
    secret_rotation_interval = "2m"
  }

  oms_agent {
    log_analytics_workspace_id      = azurerm_log_analytics_workspace.logs.id
    msi_auth_for_monitoring_enabled = true
  }

  tags = local.tags

  lifecycle {
    ignore_changes = [
      # The autoscaler manages the node count.
      default_node_pool[0].node_count,
    ]
  }
}

# Nodes pull images from ACR with the kubelet identity.
resource "azurerm_role_assignment" "kubelet_acr_pull" {
  scope                            = azurerm_container_registry.acr.id
  role_definition_name             = "AcrPull"
  principal_id                     = azurerm_kubernetes_cluster.aks.kubelet_identity[0].object_id
  skip_service_principal_aad_check = true
}

# Cluster admin through Azure RBAC for the chosen admins.
resource "azurerm_role_assignment" "aks_cluster_admin" {
  for_each             = toset(local.admin_object_ids)
  scope                = azurerm_kubernetes_cluster.aks.id
  role_definition_name = "Azure Kubernetes Service RBAC Cluster Admin"
  principal_id         = each.value
}

# ---------------------------------------------------------------- Key Vault
resource "azurerm_key_vault" "kv" {
  name                       = local.kv_name
  location                   = azurerm_resource_group.rg.location
  resource_group_name        = azurerm_resource_group.rg.name
  tenant_id                  = data.azurerm_client_config.current.tenant_id
  sku_name                   = "standard"
  enable_rbac_authorization  = true
  soft_delete_retention_days = 7
  purge_protection_enabled   = true
  tags                       = local.tags
}

# The deployer can create secrets (done by hand so values never enter Terraform state).
resource "azurerm_role_assignment" "deployer_kv_officer" {
  scope                = azurerm_key_vault.kv.id
  role_definition_name = "Key Vault Secrets Officer"
  principal_id         = data.azurerm_client_config.current.object_id
}

# ---------------------------------------------------------------- Workload identity for the agent pod
resource "azurerm_user_assigned_identity" "agent" {
  name                = "id-${local.base_name}-agent"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
  tags                = local.tags
}

resource "azurerm_federated_identity_credential" "agent" {
  name                = "aks-${var.k8s_namespace}-${var.k8s_service_account}"
  resource_group_name = azurerm_resource_group.rg.name
  parent_id           = azurerm_user_assigned_identity.agent.id
  audience            = ["api://AzureADTokenExchange"]
  issuer              = azurerm_kubernetes_cluster.aks.oidc_issuer_url
  subject             = "system:serviceaccount:${var.k8s_namespace}:${var.k8s_service_account}"
}

resource "azurerm_role_assignment" "agent_kv_reader" {
  scope                = azurerm_key_vault.kv.id
  role_definition_name = "Key Vault Secrets User"
  principal_id         = azurerm_user_assigned_identity.agent.principal_id
}
