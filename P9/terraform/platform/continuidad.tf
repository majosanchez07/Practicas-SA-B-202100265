# ==============================================================================
# Continuidad operativa - Practica 9
#
# Practica 9 - Maria Jose Tebalan Sanchez - 202100265
#
# Este archivo convierte la plataforma de la Practica 8 en una plataforma
# recuperable. En la P8 ArgoCD, Sealed Secrets, Kyverno y Argo Rollouts se
# instalaban con "helm install" a mano, siguiendo docs/despliegue.md. Eso es
# justo lo que falla bajo presion: una persona, desde una maquina y de memoria.
#
# Aqui Terraform instala solo lo imprescindible para que el resto se levante
# solo, en este orden:
#
#   1. La llave de Sealed Secrets, leida de AWS Secrets Manager (fuera del
#      cluster), ANTES que el controlador.
#   2. El controlador de Sealed Secrets, que arranca con esa llave y por lo
#      tanto puede descifrar los SealedSecret que ya estan en el repositorio.
#   3. Velero, apuntando al bucket de S3 externo, para poder restaurar datos.
#   4. ArgoCD.
#   5. La aplicacion raiz (app-of-apps), que levanta todo lo demas desde el
#      repositorio GitOps: Argo Rollouts, Kyverno, politicas, secretos, el
#      schedule de Velero y la plataforma de microservicios.
#
# El paso 5 se controla con var.crear_app_raiz para que bootstrap.sh pueda
# restaurar los volumenes (paso intermedio automatico) antes de que ArgoCD
# cree la base de datos: si ArgoCD llegara primero, crearia un volumen vacio
# con el mismo nombre y Velero no lo sobrescribiria.
# ==============================================================================

# ------------------------------------------------------------------------------
# 1. Llave de Sealed Secrets
#
# Clasificacion de estado (clase de 17/09): esta llave es IRRECUPERABLE. Si se
# pierde, todo SealedSecret del repositorio queda ilegible y hay que rotar cada
# credencial. Por eso su copia vive en Secrets Manager, fuera del cluster, y
# el cluster nuevo la recibe antes de que el controlador arranque.
#
# El controlador reconoce como propia cualquier Secret de tipo TLS con la
# etiqueta sealedsecrets.bitnami.com/sealed-secrets-key=active en su namespace.
# ------------------------------------------------------------------------------

data "aws_secretsmanager_secret_version" "llave_sealed" {
  secret_id = var.secreto_llave_sealed
}

locals {
  llave_sealed = jsondecode(data.aws_secretsmanager_secret_version.llave_sealed.secret_string)
}

resource "kubernetes_secret" "llave_sealed" {
  metadata {
    name      = "sealed-secrets-key-respaldada"
    namespace = kubernetes_namespace.plataforma["sealed-secrets"].metadata[0].name
    labels = merge(local.etiquetas, {
      "sealedsecrets.bitnami.com/sealed-secrets-key" = "active"
    })
  }

  type = "kubernetes.io/tls"

  # Secrets Manager guarda los valores tal como los entrega kubectl (base64);
  # el provider espera el contenido en claro, de ahi el base64decode.
  data = {
    "tls.crt" = base64decode(local.llave_sealed["tls.crt"])
    "tls.key" = base64decode(local.llave_sealed["tls.key"])
  }
}

# ------------------------------------------------------------------------------
# 2. Controlador de Sealed Secrets
# ------------------------------------------------------------------------------

resource "helm_release" "sealed_secrets" {
  name       = "sealed-secrets"
  namespace  = kubernetes_namespace.plataforma["sealed-secrets"].metadata[0].name
  repository = "https://bitnami.github.io/sealed-secrets"
  chart      = "sealed-secrets"
  version    = "2.20.0"

  # Mismo nombre que en la P8: kubeseal y los SealedSecret existentes lo usan.
  set {
    name  = "fullnameOverride"
    value = "sealed-secrets-controller"
  }

  # Sin rotacion automatica: una llave nueva que no este en Secrets Manager
  # romperia la continuidad. La rotacion se hace a proposito con
  # scripts/respaldar-llave-sealed.sh.
  set {
    name  = "keyrenewperiod"
    value = "0"
  }

  depends_on = [kubernetes_secret.llave_sealed]
}

# ------------------------------------------------------------------------------
# 3. Velero
#
# Destino: bucket S3 (objetos de Kubernetes) y snapshots EBS (volumenes). Los
# dos viven en la cuenta de AWS, fuera del cluster: sobreviven a su perdida.
# Credenciales: IRSA, el rol lo crea la capa cluster/. Nada estatico.
# ------------------------------------------------------------------------------

resource "helm_release" "velero" {
  name       = "velero"
  namespace  = kubernetes_namespace.plataforma["velero"].metadata[0].name
  repository = "https://vmware-tanzu.github.io/helm-charts"
  chart      = "velero"
  version    = "12.2.0" # Velero 1.18.2

  wait    = true
  timeout = 600

  values = [yamlencode({
    # El plugin de AWS se versiona junto con Velero (1.18.x <-> 1.14.x).
    initContainers = [{
      name            = "velero-plugin-for-aws"
      image           = "velero/velero-plugin-for-aws:v1.14.3"
      imagePullPolicy = "IfNotPresent"
      volumeMounts    = [{ mountPath = "/target", name = "plugins" }]
    }]

    credentials = { useSecret = false }

    serviceAccount = {
      server = {
        create = true
        name   = "velero-server"
        annotations = {
          "eks.amazonaws.com/role-arn" = "arn:aws:iam::${data.aws_caller_identity.actual.account_id}:role/${var.nombre_cluster}-velero"
        }
      }
    }

    configuration = {
      backupStorageLocation = [{
        name     = "default"
        provider = "aws"
        bucket   = var.bucket_respaldos
        default  = true
        config   = { region = var.region }
      }]
      volumeSnapshotLocation = [{
        name     = "default"
        provider = "aws"
        config   = { region = var.region }
      }]
    }

    # El schedule no se declara aqui: vive en el repositorio GitOps
    # (platform/velero/) y lo aplica ArgoCD, igual que el resto de la
    # configuracion de la aplicacion.
    schedules        = {}
    snapshotsEnabled = true
    deployNodeAgent  = false

    resources = {
      requests = { cpu = "100m", memory = "128Mi" }
      limits   = { cpu = "500m", memory = "512Mi" }
    }
  })]
}

data "aws_caller_identity" "actual" {}

# ------------------------------------------------------------------------------
# 4. ArgoCD
# ------------------------------------------------------------------------------

resource "helm_release" "argocd" {
  name       = "argocd"
  namespace  = kubernetes_namespace.plataforma["argocd"].metadata[0].name
  repository = "https://argoproj.github.io/argo-helm"
  chart      = "argo-cd"
  version    = "7.7.5"

  wait    = true
  timeout = 600

  set {
    name  = "configs.params.server\\.insecure"
    value = "true"
  }

  depends_on = [helm_release.sealed_secrets]
}

# ------------------------------------------------------------------------------
# 5. Aplicacion raiz (app-of-apps)
#
# Una sola Application que apunta a la carpeta apps/ del repositorio GitOps.
# Cada archivo de esa carpeta es a su vez una Application. A partir de aqui
# Terraform ya no instala nada: el repositorio es la fuente de verdad.
# ------------------------------------------------------------------------------

resource "helm_release" "app_raiz" {
  count = var.crear_app_raiz ? 1 : 0

  name       = "app-raiz"
  namespace  = kubernetes_namespace.plataforma["argocd"].metadata[0].name
  repository = "https://argoproj.github.io/argo-helm"
  chart      = "argocd-apps"
  version    = "2.0.5"

  values = [yamlencode({
    applications = {
      (var.nombre_app_raiz) = {
        namespace  = "argocd"
        project    = "default"
        finalizers = ["resources-finalizer.argocd.argoproj.io"]
        source = {
          repoURL        = var.repo_gitops
          targetRevision = "main"
          path           = "apps"
        }
        destination = {
          server    = "https://kubernetes.default.svc"
          namespace = "argocd"
        }
        syncPolicy = {
          automated = { prune = true, selfHeal = true }
          retry = {
            limit   = 10
            backoff = { duration = "15s", factor = 2, maxDuration = "5m" }
          }
        }
      }
    }
  })]

  depends_on = [helm_release.argocd, helm_release.velero]
}
