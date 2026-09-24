# ==============================================================================
# Capa 1 - El cluster AKS
#
# Practica 9 - Maria Jose Tebalan Sanchez - 202100265
#
# La Practica 8 corria en EKS (AWS). La Practica 9 se traslada a Azure (AKS),
# en la region centralus: distinta de la del proyecto (eastus / eastus2), de
# modo que la prueba de desastre nunca puede tocar sus recursos y cada uno
# dispone de su propia cuota regional de vCPU.
#
# Que vive aqui y que no
# ----------------------
# Esta capa crea SOLO lo que la prueba de DR destruye y reconstruye:
#   - grupo rg-sa-p9-202100265, el cluster AKS y su grupo de nodos
#   - la identidad administrada de Velero y sus permisos
#
# Lo que tiene que sobrevivir al desastre vive en rg-sa-p9-base-202100265 y lo
# crea scripts/crear-backend.sh, fuera de este estado: el estado de Terraform,
# el almacenamiento de respaldos y el Key Vault con la llave de Sealed Secrets.
# Si vivieran aqui, un terraform destroy se llevaria tambien los respaldos
# (el caso de Code Spaces, 2014, visto en clase).
# ==============================================================================

terraform {
  required_version = ">= 1.5"

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 4.14"
    }
  }

  # Estado remoto. El backend azurerm bloquea el estado con un lease sobre el
  # blob: dos operadores no pueden aplicar a la vez. Cualquier persona con
  # acceso a la suscripcion puede reconstruir desde otro equipo.
  backend "azurerm" {
    resource_group_name  = "rg-sa-p9-base-202100265"
    storage_account_name = "sap9tfstate202100265"
    container_name       = "tfstate"
    key                  = "cluster/terraform.tfstate"
    use_azuread_auth     = true
  }
}

provider "azurerm" {
  features {
    resource_group {
      # El grupo del cluster se destruye completo en la prueba de DR.
      prevent_deletion_if_contains_resources = false
    }
  }
}

data "azurerm_client_config" "actual" {}

data "azurerm_resource_group" "base" {
  name = var.grupo_base
}

locals {
  nombre = "aks-sa-p9-${var.carne}"
  etiquetas = {
    practica  = "p9"
    carne     = var.carne
    curso     = "software-avanzado-b"
    managedby = "terraform"
  }
}

resource "azurerm_resource_group" "cluster" {
  name     = "rg-sa-p9-${var.carne}"
  location = var.region
  tags     = local.etiquetas
}

# ------------------------------------------------------------------------------
# Cluster AKS
# ------------------------------------------------------------------------------

resource "azurerm_kubernetes_cluster" "este" {
  name                = local.nombre
  location            = azurerm_resource_group.cluster.location
  resource_group_name = azurerm_resource_group.cluster.name
  dns_prefix          = local.nombre
  kubernetes_version  = var.version_kubernetes

  # Nombre fijo del grupo de nodos: Velero crea ahi los discos restaurados y
  # su identidad necesita permisos sobre el. Con el nombre automatico (MC_...)
  # habria que descubrirlo despues de crear el cluster.
  node_resource_group = "rg-sa-p9-nodos-${var.carne}"

  # Workload identity: los pods obtienen identidad de Azure a traves del
  # emisor OIDC del cluster, sin secretos estaticos. Es el equivalente de IRSA.
  oidc_issuer_enabled       = true
  workload_identity_enabled = true

  default_node_pool {
    name       = "workers"
    vm_size    = var.tipo_nodo
    node_count = var.nodos
    # Dos nodos: el minimo para que el drenaje de uno deje replicas vivas.
    # La cuota de la region es de 4 vCPU; 2 x Standard_D2s_v7 la ocupan justa.
    os_disk_size_gb = 64
    node_labels     = { rol = "workers" }

    upgrade_settings {
      max_surge = "10%"
    }
  }

  identity {
    type = "SystemAssigned"
  }

  tags = local.etiquetas
}

# ------------------------------------------------------------------------------
# Identidad de Velero (workload identity)
#
# Velero escribe los respaldos en la cuenta sap9velero202100265 y crea
# snapshots de los discos en el grupo base (fuera del cluster). Al restaurar,
# crea discos en el grupo de nodos. Esos son exactamente sus permisos.
# ------------------------------------------------------------------------------

resource "azurerm_user_assigned_identity" "velero" {
  name                = "id-velero-sa-p9"
  location            = azurerm_resource_group.cluster.location
  resource_group_name = azurerm_resource_group.cluster.name
  tags                = local.etiquetas
}

resource "azurerm_federated_identity_credential" "velero" {
  name                = "velero-server"
  resource_group_name = azurerm_resource_group.cluster.name
  parent_id           = azurerm_user_assigned_identity.velero.id
  audience            = ["api://AzureADTokenExchange"]
  issuer              = azurerm_kubernetes_cluster.este.oidc_issuer_url
  subject             = "system:serviceaccount:velero:velero-server"
}

# Snapshots de disco en el grupo base y lectura de su cuenta de almacenamiento.
resource "azurerm_role_assignment" "velero_base" {
  scope                = data.azurerm_resource_group.base.id
  role_definition_name = "Contributor"
  principal_id         = azurerm_user_assigned_identity.velero.principal_id
}

# Escritura de blobs de respaldo con Azure AD (sin llaves de la cuenta).
resource "azurerm_role_assignment" "velero_blobs" {
  scope                = data.azurerm_resource_group.base.id
  role_definition_name = "Storage Blob Data Contributor"
  principal_id         = azurerm_user_assigned_identity.velero.principal_id
}

# Discos del cluster: leerlos para el snapshot y crearlos al restaurar.
resource "azurerm_role_assignment" "velero_nodos" {
  scope                = "/subscriptions/${data.azurerm_client_config.actual.subscription_id}/resourceGroups/${azurerm_kubernetes_cluster.este.node_resource_group}"
  role_definition_name = "Contributor"
  principal_id         = azurerm_user_assigned_identity.velero.principal_id
}
