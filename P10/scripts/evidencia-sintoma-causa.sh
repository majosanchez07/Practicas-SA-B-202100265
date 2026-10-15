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
T_INICIO_RECORRIDO=$(epoch)
registro "RECORRIDO: alerta abierta (runbook_url: $(jq -r '.[0].annotations.runbook_url' "${EVID}/sintoma-causa/alerta-${SELLO}.json"))"

if [ "${RECORRIDO_AUTO:-0}" = "1" ]; then
  # Modo automatico: el recorrido lo hacen las mismas APIs que consulta
  # Grafana (Prometheus, Tempo y Loki), en el mismo orden que el runbook.
  kubectl -n "${NS_OBS}" port-forward svc/tempo 3200:3100 >/dev/null 2>&1 &
  PF_TEMPO=$!
  kubectl -n "${NS_OBS}" port-forward svc/loki 3100:3100 >/dev/null 2>&1 &
  PF_LOKI=$!
  trap 'kill ${PF_PROM} ${PF_AM} ${PF_TEMPO} ${PF_LOKI} 2>/dev/null || true' EXIT
  # Esperar a que Tempo responda y tenga trazas con error (tras un reinicio
  # tarda en estar listo; con 3 s fijos el recorrido se corto en la prueba).
  until [ -n "$(curl -s --get http://127.0.0.1:3200/api/search --data-urlencode "q={ status = error }" --data-urlencode limit=1 | jq -r ".traces[0].traceID // empty" 2>/dev/null)" ]; do sleep 2; done

  # 1. Metricas: que ruta falla en el gateway y que servicio interno la origina.
  RUTA=$(curl -s --get "http://127.0.0.1:9090/api/v1/query" --data-urlencode \
    'query=topk(1, sum by (route) (rate(sa_http_requests_total{service_name="api-gateway",status_code=~"5.."}[5m])))' \
    | jq -r '.data.result[0].metric.route')
  SVC=$(curl -s --get "http://127.0.0.1:9090/api/v1/query" --data-urlencode \
    'query=topk(1, sum by (service_name) (rate(sa_http_requests_total{service_name!="api-gateway",status_code=~"5.."}[5m])))' \
    | jq -r '.data.result[0].metric.service_name')
  registro "PASO 1 (metricas): el gateway falla en la ruta ${RUTA}; el servicio interno con errores 5xx es ${SVC} (t+$(( $(epoch) - T_INICIO_RECORRIDO ))s)"

  # 2. Trazas: una peticion fallida de ese servicio y su span en error.
  AHORA=$(epoch)
  TID=$(curl -s --get "http://127.0.0.1:3200/api/search" \
    --data-urlencode "q={ resource.service.name = \"${SVC}\" && status = error }" \
    --data-urlencode limit=1 \
    | jq -r '.traces[0].traceID')
  # Tempo omite los ceros iniciales del ID; los registros guardan los 32 digitos.
  TID=$(printf '%32s' "${TID}" | tr ' ' '0')
  curl -s -H 'Accept: application/json' "http://127.0.0.1:3200/api/traces/${TID}" > "${EVID}/sintoma-causa/traza-${TID}.json"
  SPAN=$(jq -r --arg s "${SVC}" '[.batches[] | select(any(.resource.attributes[]; .key=="service.name" and .value.stringValue==$s))
          | .scopeSpans[].spans[] | select(.status.code=="STATUS_CODE_ERROR" and .kind=="SPAN_KIND_SERVER")] | first
          | "\(.name) duracion=\(((.endTimeUnixNano|tonumber)-(.startTimeUnixNano|tonumber))/1000000|floor)ms codigo=\([.attributes[] | select(.key|test("status_code")) | .value.intValue] | first)"' \
          "${EVID}/sintoma-causa/traza-${TID}.json")
  SERVICIOS=$(jq -r '[.batches[].resource.attributes[] | select(.key=="service.name") | .value.stringValue] | unique | join(" -> ")' "${EVID}/sintoma-causa/traza-${TID}.json")
  registro "PASO 2 (trazas): traza ${TID} [${SERVICIOS}]; span en error de ${SVC}: ${SPAN} (t+$(( $(epoch) - T_INICIO_RECORRIDO ))s)"

  # 3. Registros: el error de esa traza, consultado por campo en Loki.
  LINEA=$(curl -s --get "http://127.0.0.1:3100/loki/api/v1/query_range" \
    --data-urlencode "query={namespace=\"${NS_APP}\", container=\"${SVC}\"} | json | trace_id=\"${TID}\" | level=\"error\"" \
    --data-urlencode "start=$(( AHORA - 7200 ))000000000" | jq -r '.data.result[0].values[0][1]')
  echo "${LINEA}" > "${EVID}/sintoma-causa/registro-${TID}.json"
  registro "PASO 3 (registros): ${LINEA} (t+$(( $(epoch) - T_INICIO_RECORRIDO ))s)"
else
  echo "Pulsar Enter EN EL MOMENTO en que se completa cada paso."
  paso() {
    read -r -p "$1 > " _
    registro "PASO: $1 (t+$(( $(epoch) - T_INICIO_RECORRIDO ))s)"
  }
  paso "1. Runbook abierto y tablero de operacion en la fila Errores (servicio y ruta identificados)"
  paso "2. Traza de una peticion fallida abierta en Tempo (span con error identificado)"
  paso "3. Registro del error en Loki abierto desde la traza (mensaje y causa leidos)"
fi
T_FIN_RECORRIDO=$(epoch)
registro "RECORRIDO COMPLETO alerta -> registro: $(( T_FIN_RECORRIDO - T_INICIO_RECORRIDO )) s"

# Recuperacion: se espera a que la correccion llegue por GitOps (nueva
# generacion del Deployment), igual que se espero al fallo.
GEN_FALLO="$(kubectl -n "${NS_APP}" get deploy sa-platform-books-service -o jsonpath='{.metadata.generation}')"
registro "Esperando la correccion por GitOps (fault.enabled: false)..."
until [ "$(kubectl -n "${NS_APP}" get deploy sa-platform-books-service -o jsonpath='{.metadata.generation}')" != "${GEN_FALLO}" ]; do
  sleep 2
done
T_REVERSION=$(epoch)
registro "Correccion aplicada por ArgoCD (nueva generacion de books-service)"
until [ "$(promql 'slo:sli_errores:ratio_rate5m{slo="disponibilidad"}')" != "sin-datos" ] \
   && awk "BEGIN{exit !($(promql 'slo:sli_errores:ratio_rate5m{slo="disponibilidad"}') < 0.005)}"; do
  sleep 15
done
registro "ESTADO ESTABLE (error 5m < 0.5%): $(( $(epoch) - T_REVERSION )) s desde la correccion, $(( $(epoch) - T_FALLO )) s desde el inicio del fallo"
while [ "$(alerta_activa "${ALERTA}")" != "0" ]; do sleep 15; done
registro "Alerta resuelta: $(( $(epoch) - T_FALLO )) s desde el inicio del fallo"
registro "Evidencia en ${EVID}/sintoma-causa/"
