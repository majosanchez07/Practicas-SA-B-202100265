#!/usr/bin/env bash
# ==============================================================================
# desplegar-local.sh — Reproduce la etapa 4 del pipeline en la maquina propia.
#
# Hace exactamente lo mismo que el job "desplegar" del workflow, con una sola
# diferencia: las imagenes se construyen aqui y se cargan en kind con
# "kind load" en lugar de descargarse de GHCR. Eso permite probar el despliegue
# completo sin depender de la red ni del registro.
#
# Uso:
#   ./P7/scripts/desplegar-local.sh              # crea el clus'ter y despliega
#   ./P7/scripts/desplegar-local.sh --eliminar   # borra el clus'ter
#
# Requisitos: docker, kind, kubectl y helm.
# ==============================================================================
set -euo pipefail

cd "$(dirname "$0")/.."
RAIZ="$(pwd)"

CLUSTER="p7-202100265"
NAMESPACE="sa-p7"
RELEASE="sa-platform"
TAG="local"

COMPONENTES=(
  "p7-api-gateway:services/api-gateway"
  "p7-auth-service:services/auth-service"
  "p7-books-service:services/books-service"
  "p7-loans-service:services/loans-service"
  "p7-notifications-service:services/notifications-service"
  "p7-cronjob-insert:cronjobs/cronjob-insert"
  "p7-cronjob-summary:cronjobs/cronjob-summary"
)

if [[ "${1:-}" == "--eliminar" ]]; then
  echo ">> Eliminando el clus'ter ${CLUSTER}"
  kind delete cluster --name "${CLUSTER}"
  exit 0
fi

# ------------------------------------------------------------------------------
# 1. Clus'ter
# ------------------------------------------------------------------------------
if kind get clusters 2>/dev/null | grep -qx "${CLUSTER}"; then
  echo ">> El clus'ter ${CLUSTER} ya existe, se reutiliza"
else
  echo ">> Creando el clus'ter ${CLUSTER}"
  kind create cluster --name "${CLUSTER}" --image kindest/node:v1.31.0
fi
kubectl config use-context "kind-${CLUSTER}"

# ------------------------------------------------------------------------------
# 2. Imagenes
#
# Se construyen con el mismo Dockerfile.prod y el mismo target que usa el
# pipeline, para que lo que se prueba aqui sea lo que se publica alla.
# ------------------------------------------------------------------------------
for entrada in "${COMPONENTES[@]}"; do
  nombre="${entrada%%:*}"
  contexto="${entrada#*:}"
  echo ">> Construyendo ${nombre}:${TAG}"
  docker build -f "${contexto}/Dockerfile.prod" --target prod \
    -t "${nombre}:${TAG}" "${contexto}"
  kind load docker-image "${nombre}:${TAG}" --name "${CLUSTER}"
done

# ------------------------------------------------------------------------------
# 3. Despliegue
#
# Sin imageRegistry: las imagenes ya estan dentro de los nodos y deben tomarse
# de ahi. pullPolicy se fuerza a Never para que el kubelet no intente ir a
# buscarlas a Docker Hub, donde no existen.
# ------------------------------------------------------------------------------
kubectl create namespace "${NAMESPACE}" --dry-run=client -o yaml | kubectl apply -f -

# Las contrasenas se generan al vuelo en cada ejecucion, pero los PVC de
# PostgreSQL y RabbitMQ sobreviven a un "helm uninstall": el disco conserva la
# base inicializada con la contrasena ANTERIOR y los servicios fallan con
# "password authentication failed". Por eso, si queda un release previo, se
# desinstala junto con sus volumenes antes de volver a instalar.
if helm status "${RELEASE}" -n "${NAMESPACE}" >/dev/null 2>&1; then
  echo ">> Se encontro un release previo: se elimina junto con sus volumenes"
  helm uninstall "${RELEASE}" -n "${NAMESPACE}"
  kubectl delete pvc --all -n "${NAMESPACE}" --timeout=120s || true
fi

echo ">> Desplegando con Helm"
helm upgrade --install "${RELEASE}" ./charts/sa-platform \
  --namespace "${NAMESPACE}" \
  --values ./charts/sa-platform/values-ci.yaml \
  --set imageRegistry="" \
  --set global.imageTag="${TAG}" \
  --set imagePullSecrets=null \
  --set services.api-gateway.image.pullPolicy=Never \
  --set services.auth-service.image.pullPolicy=Never \
  --set services.books-service.image.pullPolicy=Never \
  --set services.loans-service.image.pullPolicy=Never \
  --set services.notifications-service.image.pullPolicy=Never \
  --set cronjobs.insert.image.pullPolicy=Never \
  --set cronjobs.summary.image.pullPolicy=Never \
  --set postgresql.auth.username=biblioteca \
  --set postgresql.auth.database=biblioteca \
  --set postgresql.auth.password="$(openssl rand -hex 16)" \
  --set postgresql.auth.postgresPassword="$(openssl rand -hex 16)" \
  --set rabbitmq.auth.username=biblioteca \
  --set rabbitmq.auth.password="$(openssl rand -hex 16)" \
  --set rabbitmq.auth.erlangCookie="$(openssl rand -hex 32)" \
  --set secrets.jwtSecretKey="$(openssl rand -hex 32)" \
  --set secrets.aesSecretKey="$(openssl rand -hex 16)" \
  --wait --timeout 15m

# ------------------------------------------------------------------------------
# 4. Verificacion — el mismo script que corre el pipeline.
# ------------------------------------------------------------------------------
bash ./scripts/verificar-despliegue.sh "${NAMESPACE}"

echo ""
echo "Para consultar el gateway desde el navegador:"
echo "  kubectl port-forward -n ${NAMESPACE} svc/${RELEASE}-api-gateway 8080:8080"
echo "Para eliminar el clus'ter:"
echo "  ./scripts/desplegar-local.sh --eliminar"
