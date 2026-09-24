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

    IMPORTANTE: la cuenta esta restringida a la capa gratuita y RECHAZA todo
    tipo que no sea elegible. El error no es evidente: el grupo de nodos queda
    en estado "CREATING" indefinidamente mientras el grupo de autoescalado
    reintenta lanzar instancias que EC2 rechaza una y otra vez con
    "The specified instance type is not eligible for Free Tier". Ni el grupo de
    nodos ni Terraform reportan el fallo; hay que consultar el historial de
    actividad del grupo de autoescalado para verlo.

    El primer intento uso t3.medium y se perdieron 23 minutos asi.

    Los tipos elegibles en us-east-2 se consultan con:
      aws ec2 describe-instance-types --region us-east-2 \
        --filters "Name=free-tier-eligible,Values=true" \
        --query 'InstanceTypes[].{tipo:InstanceType,memoriaMiB:MemoryInfo.SizeInMiB}'

    Se elige m7i-flex.large: es elegible y ofrece 8 GiB por nodo, el doble que
    t3.medium. Con dos nodos son 16 GiB, holgado para la plataforma mas el
    operador de despliegue, el controlador de promocion, el motor de admision y
    el controlador de secretos.

    La Practica 6 uso t3.small (2 GiB), que tambien es elegible pero se queda
    corto aqui: aquella practica no desplegaba estos cuatro componentes
    adicionales.
  DESC
  type        = string
  default     = "m7i-flex.large"
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

variable "bucket_respaldos" {
  description = "Bucket de S3, externo al cluster, donde Velero guarda los respaldos."
  type        = string
  default     = "sa-p9-velero-202100265"
}
