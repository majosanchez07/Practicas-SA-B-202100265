#!/usr/bin/env bash
# ==============================================================================
# recolectar-evidencia.sh — Guarda el estado del clus'ter como evidencia.
#
# El clus'ter kind del pipeline se destruye al terminar el job, de modo que sin
# esto no quedaria rastro de lo que se desplegó. Los archivos que genera se
# publican como artefacto de la ejecucion y sirven de evidencia verificable de
# que el despliegue automatico ocurrio.
#
# Se invoca con if: always(), asi que tambien corre cuando el despliegue fallo:
# ahi es cuando la evidencia mas sirve. Por eso ningun comando interrumpe el
# script si falla —se usa "|| true"— y no se activa "set -e".
#
# Uso: recolectar-evidencia.sh [namespace] [directorio-destino]
# ==============================================================================
set -uo pipefail

NAMESPACE="${1:-sa-p7}"
DESTINO="${2:-evidencia-despliegue}"

mkdir -p "${DESTINO}"

echo "Recolectando evidencia del namespace ${NAMESPACE} en ${DESTINO}/"

{
  echo "# Evidencia del despliegue automatico — Practica 7"
  echo ""
  echo "- Namespace: \`${NAMESPACE}\`"
  echo "- Fecha (UTC): $(date -u '+%Y-%m-%d %H:%M:%S')"
  echo "- Commit: \`${GITHUB_SHA:-local}\`"
  echo "- Ejecucion: \`${GITHUB_RUN_ID:-local}\`"
  echo ""
} > "${DESTINO}/00-resumen.md"

# Estado general de todos los objetos del namespace.
kubectl get all -n "${NAMESPACE}" -o wide > "${DESTINO}/01-objetos.txt" 2>&1 || true

# Imagenes desplegadas: la prueba de que el despliegue usa lo que el pipeline
# acaba de construir y publicar.
# Los Deployments y los CronJobs se consultan por separado a proposito: el pod
# template de un CronJob cuelga un nivel mas abajo (bajo jobTemplate), de modo
# que una sola consulta para ambos dejaria la columna de imagen vacia en los
# cronjobs.
{
  echo "TIPO         NOMBRE                              IMAGEN"
  kubectl get deployments -n "${NAMESPACE}" \
    -o custom-columns='TIPO:.kind,NOMBRE:.metadata.name,IMAGEN:.spec.template.spec.containers[0].image' \
    --no-headers 2>&1
  kubectl get cronjobs -n "${NAMESPACE}" \
    -o custom-columns='TIPO:.kind,NOMBRE:.metadata.name,IMAGEN:.spec.jobTemplate.spec.template.spec.containers[0].image' \
    --no-headers 2>&1
} > "${DESTINO}/02-imagenes-desplegadas.txt" 2>&1 || true

# Detalle de los pods, con sus contenedores y el estado de cada probe.
kubectl get pods -n "${NAMESPACE}" -o wide > "${DESTINO}/03-pods.txt" 2>&1 || true
kubectl describe pods -n "${NAMESPACE}" > "${DESTINO}/04-pods-detalle.txt" 2>&1 || true

# Eventos: la fuente mas util cuando algo no arranco.
kubectl get events -n "${NAMESPACE}" --sort-by=.lastTimestamp \
  > "${DESTINO}/05-eventos.txt" 2>&1 || true

# Objetos que demuestran los requisitos heredados de las practicas anteriores.
{
  echo "===== ConfigMap ====="
  kubectl get configmaps -n "${NAMESPACE}" 2>&1
  echo ""
  echo "===== Secrets (solo nombres; el contenido NO se registra) ====="
  kubectl get secrets -n "${NAMESPACE}" 2>&1
  echo ""
  echo "===== HPA ====="
  kubectl get hpa -n "${NAMESPACE}" 2>&1
  echo ""
  echo "===== NetworkPolicies ====="
  kubectl get networkpolicies -n "${NAMESPACE}" 2>&1
  echo ""
  echo "===== ResourceQuota ====="
  kubectl describe resourcequota -n "${NAMESPACE}" 2>&1
  echo ""
  echo "===== PersistentVolumeClaims ====="
  kubectl get pvc -n "${NAMESPACE}" 2>&1
} > "${DESTINO}/06-objetos-kubernetes.txt" 2>&1 || true

# Logs de cada pod. Se limitan a 200 lineas: interesa el arranque, no todo.
mkdir -p "${DESTINO}/logs"
for pod in $(kubectl get pods -n "${NAMESPACE}" -o name 2>/dev/null); do
  nombre="${pod#pod/}"
  kubectl logs "${pod}" -n "${NAMESPACE}" --all-containers --tail=200 \
    > "${DESTINO}/logs/${nombre}.log" 2>&1 || true
done

# Release de Helm: version desplegada y estado.
helm list -n "${NAMESPACE}" > "${DESTINO}/07-release-helm.txt" 2>&1 || true

# Se agrega al resumen lo mas relevante, para poder leer el artefacto de un
# vistazo sin abrir cada archivo.
{
  echo "## Pods"
  echo ""
  echo '```'
  cat "${DESTINO}/03-pods.txt" 2>/dev/null
  echo '```'
  echo ""
  echo "## Imagenes desplegadas"
  echo ""
  echo '```'
  cat "${DESTINO}/02-imagenes-desplegadas.txt" 2>/dev/null
  echo '```'
} >> "${DESTINO}/00-resumen.md"

echo "Evidencia recolectada:"
ls -la "${DESTINO}"
