# ==============================================================================
# Salidas de la capa de cluster
#
# Son la interfaz con el resto de la practica: la capa platform/ las consulta y
# el estudiante las usa para configurar kubectl.
# ==============================================================================

output "nombre_cluster" {
  description = "Nombre del cluster EKS."
  value       = module.eks.cluster_name
}

output "region" {
  description = "Region donde vive el cluster."
  value       = var.region
}

output "endpoint" {
  description = "Endpoint del servidor de la API de Kubernetes."
  value       = module.eks.cluster_endpoint
}

output "version_kubernetes" {
  description = "Version del plano de control efectivamente desplegada."
  value       = module.eks.cluster_version
}

output "oidc_provider_arn" {
  description = "ARN del proveedor OIDC; lo necesita cualquier rol IRSA posterior."
  value       = module.eks.oidc_provider_arn
}

output "vpc_id" {
  description = "Identificador de la VPC creada."
  value       = module.vpc.vpc_id
}

# El comando exacto para apuntar kubectl a este cluster. Se emite como salida
# para que quede en la evidencia y nadie tenga que recordar la sintaxis.
output "comando_kubeconfig" {
  description = "Comando que configura kubectl contra este cluster."
  value       = "aws eks update-kubeconfig --region ${var.region} --name ${module.eks.cluster_name}"
}
