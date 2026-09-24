# ==============================================================================
# Capa 2 - Plataforma: namespaces, cuotas, limites y RBAC
#
# Practica 9 - Maria Jose Tebalan Sanchez - 202100265
#
# El enunciado lo pide con estas palabras:
#
#   "Infraestructura como codigo: namespaces, cuotas de recursos, limites y
#    RBAC del cluster definidos y aplicados con Terraform. No se acepta
#    infraestructura creada manualmente."
#
# Una consecuencia que conviene explicar, porque no es evidente
# --------------------------------------------------------------
# El chart sa-platform de las Practicas 5 a 7 ya creaba el namespace, la
# ResourceQuota, el LimitRange y el RBAC (templates/namespace.yaml,
# quotas.yaml y rbac.yaml). Esa responsabilidad se traslada aqui y se apaga en
# el chart mediante los values de la P8.
#
# No es una duplicacion que se pueda dejar pasar: si Terraform y ArgoCD
# declararan ambos el mismo ResourceQuota, cada uno lo reclamaria como propio y
# la aplicacion de ArgoCD oscilaria entre Synced y OutOfSync sin estabilizarse.
# El requisito de calificacion exige que este Synced y Healthy, de modo que
# cada objeto tiene un unico dueno:
#
#   Terraform -> namespace, ResourceQuota, LimitRange, RBAC del namespace
#   ArgoCD    -> cargas de trabajo (Rollout, Service, ConfigMap, HPA...)
# ==============================================================================

terraform {
  required_version = ">= 1.5"

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 4.14"
    }
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 2.33"
    }
    helm = {
      source  = "hashicorp/helm"
      version = "~> 2.16"
    }
  }

  # Estado remoto con bloqueo (ver la explicacion en ../cluster/main.tf).
  backend "azurerm" {
    resource_group_name  = "rg-sa-p9-base-202100265"
    storage_account_name = "sap9tfstate202100265"
    container_name       = "tfstate"
    key                  = "platform/terraform.tfstate"
    use_azuread_auth     = true
  }
}

provider "azurerm" {
  features {}
}

# ------------------------------------------------------------------------------
# Conexion con el cluster creado por la capa anterior
#
# Se consulta por nombre en lugar de leer el estado de la otra capa: la unica
# dependencia entre ambas es el nombre del cluster, y queda explicita.
# ------------------------------------------------------------------------------

data "azurerm_kubernetes_cluster" "este" {
  name                = var.nombre_cluster
  resource_group_name = var.grupo_cluster
}

locals {
  # Si el cluster no expone credenciales de administrador, se usa la del usuario.
  kube_cfg = length(data.azurerm_kubernetes_cluster.este.kube_admin_config) > 0 ? data.azurerm_kubernetes_cluster.este.kube_admin_config[0] : data.azurerm_kubernetes_cluster.este.kube_config[0]
}

provider "kubernetes" {
  host                   = local.kube_cfg.host
  client_certificate     = base64decode(local.kube_cfg.client_certificate)
  client_key             = base64decode(local.kube_cfg.client_key)
  cluster_ca_certificate = base64decode(local.kube_cfg.cluster_ca_certificate)
}

provider "helm" {
  kubernetes {
    host                   = local.kube_cfg.host
    client_certificate     = base64decode(local.kube_cfg.client_certificate)
    client_key             = base64decode(local.kube_cfg.client_key)
    cluster_ca_certificate = base64decode(local.kube_cfg.cluster_ca_certificate)
  }
}

# ------------------------------------------------------------------------------
# Namespaces
#
# Cuatro, con responsabilidades separadas. La separacion no es cosmetica: cada
# namespace tiene su propia cuota y sus propias politicas, de modo que una
# prueba de carga sobre la aplicacion no puede dejar sin recursos al operador
# que vigila los despliegues.
# ------------------------------------------------------------------------------

locals {
  # Etiquetas comunes a todo lo que crea esta capa. La etiqueta gestionado-por
  # permite demostrar en la evidencia que ningun objeto se creo a mano:
  #   kubectl get ns -l gestionado-por=terraform
  etiquetas = {
    "app.kubernetes.io/managed-by" = "terraform"
    "gestionado-por"               = "terraform"
    "practica"                     = "p9"
    "carne"                        = var.carne
  }

  namespaces = {
    # Namespace de la aplicacion.
    (var.namespace_app) = {
      componente = "aplicacion"
      # La etiqueta que las NetworkPolicies del chart usan para reconocer el
      # trafico propio del namespace; se conserva de la Practica 5.
      extra = { "nombre" = var.namespace_app }
    }
    # El operador GitOps.
    "argocd" = {
      componente = "gitops"
      extra      = {}
    }
    # El motor de politicas de admision.
    "kyverno" = {
      componente = "politicas"
      extra      = {}
    }
    # El controlador de secretos cifrados.
    "sealed-secrets" = {
      componente = "secretos"
      extra      = {}
    }
    # Respaldo y recuperacion (Practica 9).
    "velero" = {
      componente = "respaldos"
      extra      = {}
    }
  }
}

resource "kubernetes_namespace" "plataforma" {
  for_each = local.namespaces

  metadata {
    name = each.key
    labels = merge(
      local.etiquetas,
      { "app.kubernetes.io/component" = each.value.componente },
      each.value.extra,
    )
  }
}

# ------------------------------------------------------------------------------
# Cuota de recursos del namespace de la aplicacion
#
# ResourceQuota acota el consumo TOTAL del namespace. Los valores se heredan de
# la Practica 5, con un aumento deliberado: durante un despliegue canary
# conviven la version estable y la candidata, de modo que el pico de replicas
# es mayor que en un Deployment normal. Si la cuota se quedara corta, el rollout
# se detendria contra la cuota y no contra el analisis, y la evidencia de
# reversion automatica quedaria falseada: el rollout habria fallado por falta
# de recursos, no por haber detectado el defecto.
# ------------------------------------------------------------------------------

resource "kubernetes_resource_quota" "app" {
  metadata {
    name      = "${var.namespace_app}-quota"
    namespace = kubernetes_namespace.plataforma[var.namespace_app].metadata[0].name
    labels    = local.etiquetas
  }

  spec {
    hard = {
      "requests.cpu"           = var.cuota.requests_cpu
      "requests.memory"        = var.cuota.requests_memoria
      "limits.cpu"             = var.cuota.limits_cpu
      "limits.memory"          = var.cuota.limits_memoria
      "pods"                   = var.cuota.pods
      "persistentvolumeclaims" = var.cuota.pvcs
    }
  }
}

# ------------------------------------------------------------------------------
# Limites por contenedor
#
# LimitRange actua sobre CADA contenedor por separado. Cumple dos funciones:
#
#   1. Fija un techo que ningun contenedor puede superar.
#   2. Da valores por defecto a los que no declaren recursos.
#
# El segundo punto es el que importa aqui: en un namespace con ResourceQuota de
# cpu o memoria, Kubernetes RECHAZA todo pod que no declare requests y limits.
# Sin este LimitRange, cualquier pod auxiliar -un Job de analisis del rollout,
# por ejemplo- seria rechazado.
#
# Notese que esto NO sustituye a la politica de Kyverno que exige limites: el
# LimitRange los inyecta silenciosamente, mientras que la politica rechaza el
# manifiesto y deja constancia de por que. Se complementan.
# ------------------------------------------------------------------------------

resource "kubernetes_limit_range" "app" {
  metadata {
    name      = "${var.namespace_app}-limits"
    namespace = kubernetes_namespace.plataforma[var.namespace_app].metadata[0].name
    labels    = local.etiquetas
  }

  spec {
    limit {
      type = "Container"

      default = {
        cpu    = var.limites.default_cpu
        memory = var.limites.default_memoria
      }

      default_request = {
        cpu    = var.limites.request_cpu
        memory = var.limites.request_memoria
      }

      max = {
        cpu    = var.limites.max_cpu
        memory = var.limites.max_memoria
      }
    }
  }
}

# ------------------------------------------------------------------------------
# RBAC - Identidad de ArgoCD dentro del namespace de la aplicacion
#
# Aqui esta el corazon del modelo de seguridad de la practica.
#
# En la Practica 7 el pipeline tenia credenciales de administrador del cluster:
# comprometer el repositorio implicaba comprometer la infraestructura. En la
# Practica 8 el pipeline no tiene ninguna credencial del cluster; quien aplica
# los cambios es ArgoCD, que vive DENTRO del cluster y solo puede tocar lo que
# este Role le permite, y solo en este namespace.
#
# El permiso es amplio dentro de sa-p8 -ArgoCD necesita poder crear y borrar
# las cargas de trabajo que gestiona- pero termina en la frontera del
# namespace: no puede tocar kube-system, ni los nodos, ni crear
# ClusterRoleBindings que le darian mas permisos de los que tiene.
# ------------------------------------------------------------------------------

resource "kubernetes_role" "argocd_app" {
  metadata {
    name      = "argocd-gestor-aplicacion"
    namespace = kubernetes_namespace.plataforma[var.namespace_app].metadata[0].name
    labels    = local.etiquetas
  }

  # Objetos basicos de una carga de trabajo.
  rule {
    api_groups = [""]
    resources  = ["configmaps", "secrets", "services", "serviceaccounts", "persistentvolumeclaims", "pods"]
    verbs      = ["get", "list", "watch", "create", "update", "patch", "delete"]
  }

  rule {
    api_groups = ["apps"]
    resources  = ["deployments", "statefulsets", "replicasets", "daemonsets"]
    verbs      = ["get", "list", "watch", "create", "update", "patch", "delete"]
  }

  rule {
    api_groups = ["batch"]
    resources  = ["jobs", "cronjobs"]
    verbs      = ["get", "list", "watch", "create", "update", "patch", "delete"]
  }

  # Argo Rollouts: sin estos permisos ArgoCD no puede crear el Rollout ni el
  # AnalysisTemplate, que son el nucleo de la entrega progresiva.
  rule {
    api_groups = ["argoproj.io"]
    resources  = ["rollouts", "analysistemplates", "analysisruns", "experiments"]
    verbs      = ["get", "list", "watch", "create", "update", "patch", "delete"]
  }

  rule {
    api_groups = ["autoscaling"]
    resources  = ["horizontalpodautoscalers"]
    verbs      = ["get", "list", "watch", "create", "update", "patch", "delete"]
  }

  rule {
    api_groups = ["networking.k8s.io"]
    resources  = ["ingresses", "networkpolicies"]
    verbs      = ["get", "list", "watch", "create", "update", "patch", "delete"]
  }

  rule {
    api_groups = ["policy"]
    resources  = ["poddisruptionbudgets"]
    verbs      = ["get", "list", "watch", "create", "update", "patch", "delete"]
  }

  # Secretos cifrados: ArgoCD aplica el SealedSecret; el controlador de
  # Sealed Secrets es quien lo descifra. ArgoCD nunca ve el valor en claro.
  rule {
    api_groups = ["bitnami.com"]
    resources  = ["sealedsecrets"]
    verbs      = ["get", "list", "watch", "create", "update", "patch", "delete"]
  }
}

resource "kubernetes_role_binding" "argocd_app" {
  metadata {
    name      = "argocd-gestor-aplicacion"
    namespace = kubernetes_namespace.plataforma[var.namespace_app].metadata[0].name
    labels    = local.etiquetas
  }

  role_ref {
    api_group = "rbac.authorization.k8s.io"
    kind      = "Role"
    name      = kubernetes_role.argocd_app.metadata[0].name
  }

  # El controlador es quien reconcilia el estado; el servidor de aplicaciones
  # necesita leer para mostrar el arbol de recursos en la interfaz.
  subject {
    kind      = "ServiceAccount"
    name      = "argocd-application-controller"
    namespace = "argocd"
  }

  subject {
    kind      = "ServiceAccount"
    name      = "argocd-server"
    namespace = "argocd"
  }
}

# ------------------------------------------------------------------------------
# RBAC - Rol de solo lectura para auditoria
#
# Un rol que permite mirar sin tocar. Es el que se le daria a un companero que
# necesita diagnosticar un incidente sin poder alterar el estado, y demuestra
# el principio de minimo privilegio con un caso concreto.
#
# Notese que excluye "secrets" deliberadamente: leer un Secret es equivalente a
# conocer la contrasena. Un rol de lectura que incluya secretos no es un rol de
# lectura.
# ------------------------------------------------------------------------------

resource "kubernetes_role" "auditor" {
  metadata {
    name      = "auditor-solo-lectura"
    namespace = kubernetes_namespace.plataforma[var.namespace_app].metadata[0].name
    labels    = local.etiquetas
  }

  rule {
    api_groups = [""]
    resources  = ["pods", "pods/log", "services", "configmaps", "events", "persistentvolumeclaims"]
    verbs      = ["get", "list", "watch"]
  }

  rule {
    api_groups = ["apps"]
    resources  = ["deployments", "statefulsets", "replicasets"]
    verbs      = ["get", "list", "watch"]
  }

  rule {
    api_groups = ["argoproj.io"]
    resources  = ["rollouts", "analysisruns", "analysistemplates"]
    verbs      = ["get", "list", "watch"]
  }
}

# ------------------------------------------------------------------------------
# Clase de almacenamiento
#
# En EKS (P8) habia que declarar la clase gp3 del driver EBS. AKS ya trae
# managed-csi (driver disk.csi.azure.com, discos administrados), que es la que
# usan los values de produccion y la que Velero sabe respaldar con snapshots.
# ------------------------------------------------------------------------------
