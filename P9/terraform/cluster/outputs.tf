output "nombre_cluster" {
  description = "Nombre del cluster AKS."
  value       = azurerm_kubernetes_cluster.este.name
}

output "grupo_cluster" {
  description = "Grupo de recursos del cluster."
  value       = azurerm_resource_group.cluster.name
}

output "grupo_nodos" {
  description = "Grupo de recursos de los nodos y discos (donde Velero restaura)."
  value       = azurerm_kubernetes_cluster.este.node_resource_group
}

output "velero_client_id" {
  description = "Client ID de la identidad de Velero (anotacion del ServiceAccount)."
  value       = azurerm_user_assigned_identity.velero.client_id
}

output "comando_kubeconfig" {
  description = "Comando para configurar kubectl."
  value       = "az aks get-credentials -g ${azurerm_resource_group.cluster.name} -n ${azurerm_kubernetes_cluster.este.name} --overwrite-existing"
}
