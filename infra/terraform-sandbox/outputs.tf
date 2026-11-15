output "resource_group" {
  value = data.azurerm_resource_group.rg.name
}

output "aks_name" {
  value = azurerm_kubernetes_cluster.aks.name
}

output "acr_name" {
  description = "Empty when enable_acr is false."
  value       = try(azurerm_container_registry.acr[0].name, "")
}

output "acr_login_server" {
  description = "Empty when enable_acr is false."
  value       = try(azurerm_container_registry.acr[0].login_server, "")
}

output "get_credentials_command" {
  value = "az aks get-credentials --resource-group ${data.azurerm_resource_group.rg.name} --name ${azurerm_kubernetes_cluster.aks.name} --overwrite-existing"
}
