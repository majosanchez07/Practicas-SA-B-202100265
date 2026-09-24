# ==============================================================================
# Variables de la capa de plataforma
# ==============================================================================

variable "carne" {
  description = "Carne del estudiante."
  type        = string
  default     = "202100265"
}

variable "nombre_cluster" {
  description = "Nombre del cluster AKS (salida nombre_cluster de la capa cluster/)."
  type        = string
  default     = "aks-sa-p9-202100265"
}

variable "grupo_cluster" {
  description = "Grupo de recursos del cluster (salida grupo_cluster de la capa cluster/)."
  type        = string
  default     = "rg-sa-p9-202100265"
}

variable "grupo_base" {
  description = "Grupo que sobrevive al desastre: estado, respaldos y Key Vault."
  type        = string
  default     = "rg-sa-p9-base-202100265"
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

# ------------------------------------------------------------------------------
# Continuidad operativa (Practica 9)
# ------------------------------------------------------------------------------

variable "key_vault" {
  description = "Key Vault (grupo base) con la llave de Sealed Secrets."
  type        = string
  default     = "kv-sa-p9-202100265"
}

variable "secreto_llave_sealed" {
  description = "Secreto del Key Vault con la llave de Sealed Secrets (JSON con tls.crt y tls.key en base64)."
  type        = string
  default     = "sealed-secrets-key"
}

variable "cuenta_respaldos" {
  description = "Cuenta de almacenamiento, externa al cluster, donde Velero guarda los respaldos (contenedor velero)."
  type        = string
  default     = "sap9velero202100265"
}

variable "repo_gitops" {
  description = "Repositorio GitOps del que la aplicacion raiz toma las Applications hijas."
  type        = string
  default     = "https://github.com/majosanchez07/Practicas-SA-B-202100265-gitops.git"
}

variable "nombre_app_raiz" {
  description = "Nombre de la aplicacion raiz (app-of-apps) en ArgoCD."
  type        = string
  default     = "raiz-sa-p9"
}

variable "crear_app_raiz" {
  description = "false durante la primera pasada de bootstrap.sh, para restaurar los volumenes antes de que ArgoCD cree la base de datos."
  type        = bool
  default     = true
}
