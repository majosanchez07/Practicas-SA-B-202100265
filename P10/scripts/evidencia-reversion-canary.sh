#!/usr/bin/env bash
# ==============================================================================
# Evidencia: reversion del canary provocada por metricas — Practica 10
# Maria Jose Tebalan Sanchez — 202100265
#
# El script NO provoca el fallo: el fallo entra por GitOps, como cualquier
# cambio. Lo que hace es observar y dejar constancia con marcas de tiempo:
#
#   1. Espera a que el Rollout empiece una revision nueva (canary).
#   2. Registra en cada ciclo el peso, el estado y lo que Prometheus mide de la
#      version candidata (las MISMAS consultas que usa el AnalysisTemplate).
#   3. Al abortarse, guarda el AnalysisRun completo (con sus mediciones) y el
#      estado final del Rollout.
#
# Uso:
#   1. ./P10/scripts/evidencia-reversion-canary.sh      (en una terminal)
#   2. En el repositorio GitOps, environments/prod/values.yaml:
#        services.api-gateway.fault.enabled: true
#      commit + push. ArgoCD sincroniza y el Rollout crea la revision nueva.
#   3. Al terminar, devolver fault.enabled a false (commit + push).
# ==============================================================================
source "$(dirname "$0")/comun.sh"

SELLO="$(date -u +%Y%m%dT%H%M%SZ)"
mkdir -p "${EVID}/canary"
LOG="${EVID}/canary/reversion-${SELLO}.log"

abrir_puertos

REV_INICIAL="$(kubectl -n "${NS_APP}" get rollout "${ROLLOUT}" -o jsonpath='{.status.currentPodHash}')"
registro "Rollout ${ROLLOUT}: revision estable actual ${REV_INICIAL}"
registro "Esperando una revision nueva (empujar el fallo al repositorio GitOps)..."

until [ "$(kubectl -n "${NS_APP}" get rollout "${ROLLOUT}" -o jsonpath='{.status.currentPodHash}')" != "${REV_INICIAL}" ]; do
  sleep 2
done
CANARY="$(kubectl -n "${NS_APP}" get rollout "${ROLLOUT}" -o jsonpath='{.status.currentPodHash}')"
T0=$(epoch)
registro "INICIO del canary: hash candidato ${CANARY}"

Q_ERR="(sum(rate(sa_http_requests_total{service_name=\"api-gateway\",rollout_hash=\"${CANARY}\",status_code=~\"5..\"}[1m])) or vector(0)) / sum(rate(sa_http_requests_total{service_name=\"api-gateway\",rollout_hash=\"${CANARY}\"}[1m]))"
Q_P95="histogram_quantile(0.95, sum by (le) (rate(sa_http_request_duration_seconds_bucket{service_name=\"api-gateway\",rollout_hash=\"${CANARY}\"}[1m])))"

while true; do
  FASE="$(kubectl -n "${NS_APP}" get rollout "${ROLLOUT}" -o jsonpath='{.status.phase}')"
  ABORT="$(kubectl -n "${NS_APP}" get rollout "${ROLLOUT}" -o jsonpath='{.status.abort}')"
  PESO="$(kubectl -n "${NS_APP}" get rollout "${ROLLOUT}" -o jsonpath='{.status.canary.weights.canary.weight}' 2>/dev/null || echo '?')"
  registro "t+$(( $(epoch) - T0 ))s fase=${FASE} abort=${ABORT:-false} peso_canary=${PESO:-?} error_candidata=$(promql "${Q_ERR}") p95_candidata_s=$(promql "${Q_P95}")"
  if [ "${ABORT}" = "true" ] || [ "${FASE}" = "Degraded" ]; then
    break
  fi
  if [ "${FASE}" = "Healthy" ] && [ "$(kubectl -n "${NS_APP}" get rollout "${ROLLOUT}" -o jsonpath='{.status.stableRS}')" = "${CANARY}" ]; then
    registro "ATENCION: la candidata fue PROMOVIDA. El analisis no detecto el fallo."
    exit 1
  fi
  sleep 10
done
T_ABORT=$(epoch)
registro "ABORTADO a los $(( T_ABORT - T0 )) s del inicio del canary"

until [ "$(kubectl -n "${NS_APP}" get rollout "${ROLLOUT}" -o jsonpath='{.status.canary.weights.canary.weight}' 2>/dev/null || echo 0)" = "0" ]; do
  sleep 2
done
registro "Trafico del canary en 0%: 100% en la version estable ${REV_INICIAL} a los $(( $(epoch) - T0 )) s"

AR="$(kubectl -n "${NS_APP}" get analysisrun -l rollouts-pod-template-hash="${CANARY}" \
      --sort-by=.metadata.creationTimestamp -o jsonpath='{.items[-1].metadata.name}')"
registro "AnalysisRun que origino la reversion: ${AR}"
kubectl -n "${NS_APP}" get analysisrun "${AR}" -o yaml > "${EVID}/canary/analysisrun-${AR}.yaml"
kubectl -n "${NS_APP}" get analysisrun "${AR}" -o json \
  | jq -r '.status.metricResults[] | "\(.name): fase=\(.phase) fallos=\(.failed // 0) ultimas=\([.measurements[-3:][] | .value] | join(","))"' \
  | tee -a "${LOG}"
kubectl argo rollouts get rollout "${ROLLOUT}" -n "${NS_APP}" --no-color > "${EVID}/canary/rollout-final-${SELLO}.txt" 2>&1 || \
  kubectl -n "${NS_APP}" describe rollout "${ROLLOUT}" > "${EVID}/canary/rollout-final-${SELLO}.txt"
registro "Evidencia en ${EVID}/canary/"
