# ==============================================================================
# Salidas de la capa de plataforma
#
# Sirven de evidencia: al terminar el apply, estas salidas enumeran exactamente
# que se creo y con que comando se comprueba en el cluster.
# ==============================================================================

output "namespaces" {
  description = "Namespaces creados por Terraform."
  value       = sort([for ns in kubernetes_namespace.plataforma : ns.metadata[0].name])
}

output "cuota_aplicada" {
  description = "Limites totales efectivos del namespace de la aplicacion."
  value       = kubernetes_resource_quota.app.spec[0].hard
}

output "roles_creados" {
  description = "Roles de RBAC definidos en el namespace de la aplicacion."
  value = [
    kubernetes_role.argocd_app.metadata[0].name,
    kubernetes_role.auditor.metadata[0].name,
  ]
}

# Comandos de verificacion. Se emiten como salida para que la evidencia del
# apply incluya la forma de comprobarla de forma independiente.
output "comandos_verificacion" {
  description = "Comandos que demuestran que la infraestructura la creo Terraform."
  value = {
    namespaces = "kubectl get namespaces -l gestionado-por=terraform"
    cuota      = "kubectl describe resourcequota -n ${var.namespace_app}"
    limites    = "kubectl describe limitrange -n ${var.namespace_app}"
    rbac       = "kubectl get roles,rolebindings -n ${var.namespace_app}"
  }
}
