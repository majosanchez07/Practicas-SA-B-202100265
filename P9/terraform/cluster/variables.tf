# ==============================================================================
# Variables de la capa de cluster (Practica 9 - Azure)
# ==============================================================================

variable "carne" {
  description = "Carne de la estudiante; forma parte de los nombres."
  type        = string
  default     = "202100265"
}

variable "region" {
  description = "Region de Azure. centralus: distinta de la que usa el proyecto (eastus/eastus2)."
  type        = string
  default     = "centralus"
}

variable "grupo_base" {
  description = "Grupo que sobrevive al desastre (estado, respaldos, Key Vault). Lo crea crear-backend.sh."
  type        = string
  default     = "rg-sa-p9-base-202100265"
}

variable "version_kubernetes" {
  description = "Version de Kubernetes de AKS."
  type        = string
  default     = "1.34"
}

variable "tipo_nodo" {
  description = "Tamano de VM de los nodos. 2 vCPU / 8 GiB; dos nodos caben en la cuota regional de 4 vCPU."
  type        = string
  default     = "Standard_D2s_v5"
}

variable "nodos" {
  description = "Cantidad de nodos."
  type        = number
  default     = 2
}
