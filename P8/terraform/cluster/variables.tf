# ==============================================================================
# Variables de la capa de cluster
#
# Los valores por defecto reproducen el dimensionamiento de la Practica 6, que
# ya se comprobo suficiente para los siete componentes de la plataforma.
# ==============================================================================

variable "carne" {
  description = "Carne del estudiante; forma parte del nombre del cluster."
  type        = string
  default     = "202100265"
}

variable "region" {
  description = "Region de AWS donde se crea toda la infraestructura."
  type        = string
  default     = "us-east-2"
}

variable "version_kubernetes" {
  description = "Version del plano de control de EKS."
  type        = string
  default     = "1.31"
}

variable "tipo_nodo" {
  description = <<-DESC
    Tipo de instancia de los nodos trabajadores.

    t3.small (2 GiB) fue suficiente en la Practica 6, pero la Practica 8 agrega
    ArgoCD, Argo Rollouts, Kyverno y Sealed Secrets sobre la misma plataforma.
    t3.medium (4 GiB) da el margen que esos componentes necesitan; con t3.small
    los pods del sistema compiten por memoria con los de la aplicacion.
  DESC
  type        = string
  default     = "t3.medium"
}

variable "nodos" {
  description = "Cantidad de nodos deseada."
  type        = number
  default     = 2
}

variable "nodos_min" {
  description = "Minimo de nodos del grupo gestionado."
  type        = number
  default     = 2
}

variable "nodos_max" {
  description = "Maximo de nodos; deja margen al autoescalado durante la prueba de carga."
  type        = number
  default     = 4
}
