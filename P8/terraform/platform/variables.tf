# ==============================================================================
# Variables de la capa de plataforma
# ==============================================================================

variable "carne" {
  description = "Carne del estudiante."
  type        = string
  default     = "202100265"
}

variable "region" {
  description = "Region de AWS donde vive el cluster."
  type        = string
  default     = "us-east-2"
}

variable "nombre_cluster" {
  description = <<-DESC
    Nombre del cluster EKS sobre el que se aplica esta capa.

    Debe coincidir con la salida nombre_cluster de la capa cluster/:
      terraform -chdir=../cluster output -raw nombre_cluster
  DESC
  type        = string
  default     = "sa-p8-202100265"
}

variable "namespace_app" {
  description = "Namespace donde vive la plataforma de microservicios."
  type        = string
  default     = "sa-p8"
}

# ------------------------------------------------------------------------------
# Cuota del namespace de la aplicacion
#
# Los valores parten de los de la Practica 5 y se amplian para el canary: con
# la version estable y la candidata conviviendo, el pico de replicas simultaneas
# es mayor. Ver la explicacion en main.tf.
# ------------------------------------------------------------------------------

variable "cuota" {
  description = "Limites totales del namespace de la aplicacion."
  type = object({
    requests_cpu     = string
    requests_memoria = string
    limits_cpu       = string
    limits_memoria   = string
    pods             = string
    pvcs             = string
  })

  default = {
    # P5 usaba 4 CPU / 6Gi de requests. El canary duplica transitoriamente las
    # replicas del servicio en despliegue, de ahi el margen adicional.
    requests_cpu     = "6"
    requests_memoria = "8Gi"
    limits_cpu       = "12"
    limits_memoria   = "14Gi"
    pods             = "60"
    pvcs             = "5"
  }
}

# ------------------------------------------------------------------------------
# Limites por contenedor
#
# Identicos a los de la Practica 5: ese dimensionamiento ya se comprobo
# adecuado para estos siete componentes.
# ------------------------------------------------------------------------------

variable "limites" {
  description = "Valores por defecto y maximos aplicados a cada contenedor."
  type = object({
    default_cpu     = string
    default_memoria = string
    request_cpu     = string
    request_memoria = string
    max_cpu         = string
    max_memoria     = string
  })

  default = {
    default_cpu     = "300m"
    default_memoria = "256Mi"
    request_cpu     = "50m"
    request_memoria = "64Mi"
    max_cpu         = "2"
    max_memoria     = "2Gi"
  }
}
