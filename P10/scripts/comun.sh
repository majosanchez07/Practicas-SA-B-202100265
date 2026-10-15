#!/usr/bin/env bash
# ==============================================================================
# Funciones comunes de los scripts de evidencia — Practica 10
# Maria Jose Tebalan Sanchez — 202100265
# ==============================================================================
set -euo pipefail

NS_APP="${NS_APP:-sa-p8}"
NS_OBS="${NS_OBS:-observabilidad}"
ROLLOUT="${ROLLOUT:-sa-platform-api-gateway}"
RAIZ="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
EVID="${RAIZ}/docs/evidencias"

# jq.exe en Windows termina cada linea con \r. Pegado a un trace_id, ese
# caracter invisible hace que ninguna busqueda en Loki coincida (se descubrio
# asi en la prueba del 15/10). Se elimina siempre.
jq() { command jq "$@" | tr -d '\r'; }

ahora() { date -u +%Y-%m-%dT%H:%M:%SZ; }
epoch() { date -u +%s; }

# Registro con marca de tiempo en pantalla y en el archivo de evidencia.
registro() { echo "[$(ahora)] $*" | tee -a "${LOG}"; }

# Prometheus y Alertmanager se consultan por port-forward: no se expone nada
# fuera del cluster para tomar evidencia.
abrir_puertos() {
  kubectl -n "${NS_OBS}" port-forward svc/monitoreo-prometheus 9090:9090 >/dev/null 2>&1 &
  PF_PROM=$!
  kubectl -n "${NS_OBS}" port-forward svc/monitoreo-alertmanager 9093:9093 >/dev/null 2>&1 &
  PF_AM=$!
  trap 'kill ${PF_PROM} ${PF_AM} 2>/dev/null || true' EXIT
  sleep 3
}

# Valor escalar de una consulta PromQL (o "sin-datos").
promql() {
  curl -s --get "http://127.0.0.1:9090/api/v1/query" --data-urlencode "query=$1" \
    | jq -r '.data.result[0].value[1] // "sin-datos"'
}

# Alertas activas en Alertmanager con un nombre dado.
alerta_activa() {
  curl -s "http://127.0.0.1:9093/api/v2/alerts?active=true&filter=alertname%3D%22$1%22" | jq 'length'
}
