#!/usr/bin/env bash
# ==============================================================================
# Evidencia: del sintoma a la causa, cronometrado — Practica 10
# Maria Jose Tebalan Sanchez — 202100265
#
# Mide dos tiempos distintos y los deja en un registro con marcas UTC:
#
#   Deteccion   inicio del fallo  -> la alerta pasa a firing en Alertmanager
#   Recorrido   la alerta se abre -> se llega al registro del error
#               (alerta -> tablero -> traza en Tempo -> registro en Loki)
#
# El primero lo mide el script solo. El segundo lo hace una persona en
# Grafana; el script solo pone las marcas cuando se pulsa Enter en cada paso,
# de modo que el tiempo registrado es el real y no una estimacion.
#
# Uso:
#   1. ./P10/scripts/evidencia-sintoma-causa.sh
#   2. Cuando lo pida, en el repositorio GitOps:
#        services.books-service.fault.enabled: true   (commit + push)
#   3. Seguir las instrucciones en pantalla.
#   4. Al terminar, fault.enabled: false (commit + push) y Enter para medir la
#      recuperacion.
# ==============================================================================
source "$(dirname "$0")/comun.sh"

SELLO="$(date -u +%Y%m%dT%H%M%SZ)"
mkdir -p "${EVID}/sintoma-causa"
LOG="${EVID}/sintoma-causa/recorrido-${SELLO}.log"
ALERTA="${ALERTA:-SLODisponibilidadConsumoRapido}"

abrir_puertos

GEN_INICIAL="$(kubectl -n "${NS_APP}" get deploy sa-platform-books-service -o jsonpath='{.metadata.generation}')"
registro "Esperando el despliegue del fallo en books-service (generation actual ${GEN_INICIAL})..."
until [ "$(kubectl -n "${NS_APP}" get deploy sa-platform-books-service -o jsonpath='{.metadata.generation}')" != "${GEN_INICIAL}" ]; do
  sleep 2
done
kubectl -n "${NS_APP}" rollout status deploy/sa-platform-books-service --timeout=5m >/dev/null
T_FALLO=$(epoch)
registro "INICIO DEL FALLO: todas las replicas de books-service tienen el fallo inducido"

# Primera senal: el primer 5xx que ve el gateway (lo que ve el usuario).
until [ "$(promql 'sum(increase(sa_http_requests_total{service_name="api-gateway",status_code=~"5.."}[1m]))')" != "0" ] \
   && [ "$(promql 'sum(increase(sa_http_requests_total{service_name="api-gateway",status_code=~"5.."}[1m]))')" != "sin-datos" ]; do
  sleep 5
done
registro "PRIMERA SENAL en metricas (errores 5xx en el gateway): t+$(( $(epoch) - T_FALLO ))s"

while [ "$(alerta_activa "${ALERTA}")" = "0" ]; do
  registro "  esperando alerta... error_1h=$(promql 'slo:sli_errores:ratio_rate1h{slo="disponibilidad"}') error_5m=$(promql 'slo:sli_errores:ratio_rate5m{slo="disponibilidad"}')"
  sleep 30
done
T_ALERTA=$(epoch)
registro "ALERTA ${ALERTA} FIRING: deteccion en $(( T_ALERTA - T_FALLO )) s ($(( (T_ALERTA - T_FALLO) / 60 )) min) desde el inicio del fallo"
curl -s "http://127.0.0.1:9093/api/v2/alerts?active=true&filter=alertname%3D%22${ALERTA}%22" \
  > "${EVID}/sintoma-causa/alerta-${SELLO}.json"

echo
echo "================ RECORRIDO CRONOMETRADO ================"
echo "Pulsar Enter EN EL MOMENTO en que se completa cada paso."
paso() {
  read -r -p "$1 > " _
  registro "PASO: $1 (t+$(( $(epoch) - T_INICIO_RECORRIDO ))s)"
}
read -r -p "Enter al ABRIR la alerta en Alertmanager/Grafana > " _
T_INICIO_RECORRIDO=$(epoch)
registro "RECORRIDO: alerta abierta"
paso "1. Runbook abierto y tablero de operacion en la fila Errores (servicio y ruta identificados)"
paso "2. Traza de una peticion fallida abierta en Tempo (span con error identificado)"
paso "3. Registro del error en Loki abierto desde la traza (mensaje y causa leidos)"
T_FIN_RECORRIDO=$(epoch)
registro "RECORRIDO COMPLETO alerta -> registro: $(( T_FIN_RECORRIDO - T_INICIO_RECORRIDO )) s"

read -r -p "Revertir el fallo por GitOps (fault.enabled: false, commit + push) y pulsar Enter al hacer push > " _
T_REVERSION=$(epoch)
registro "Correccion empujada al repositorio GitOps"
until [ "$(promql 'slo:sli_errores:ratio_rate5m{slo="disponibilidad"}')" != "sin-datos" ] \
   && awk "BEGIN{exit !($(promql 'slo:sli_errores:ratio_rate5m{slo="disponibilidad"}') < 0.005)}"; do
  sleep 15
done
registro "ESTADO ESTABLE (error 5m < 0.5%): $(( $(epoch) - T_REVERSION )) s desde la correccion, $(( $(epoch) - T_FALLO )) s desde el inicio del fallo"
while [ "$(alerta_activa "${ALERTA}")" != "0" ]; do sleep 15; done
registro "Alerta resuelta: $(( $(epoch) - T_FALLO )) s desde el inicio del fallo"
registro "Evidencia en ${EVID}/sintoma-causa/"
