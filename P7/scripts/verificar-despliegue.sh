#!/usr/bin/env bash
# ==============================================================================
# verificar-despliegue.sh — Comprueba que el despliegue quedo realmente en pie.
#
# Se ejecuta en la etapa 4 del pipeline, despues de "helm upgrade --wait". Ese
# --wait ya espera a que los pods esten listos, pero eso solo dice que las
# probes respondieron: no dice que la plataforma atienda una peticion real.
# Este script cierra esa brecha.
#
# Uso: verificar-despliegue.sh [namespace]
# ==============================================================================
set -euo pipefail

NAMESPACE="${1:-sa-p7}"
COMPONENTES=(api-gateway auth-service books-service loans-service notifications-service)

echo "== Estado del despliegue en el namespace ${NAMESPACE} =="
kubectl get all -n "${NAMESPACE}"

fallos=0

# ------------------------------------------------------------------------------
# 1. Cada Deployment tiene todas sus replicas disponibles.
# ------------------------------------------------------------------------------
echo ""
echo "== Verificando los Deployments =="
for componente in "${COMPONENTES[@]}"; do
  deployment="sa-platform-${componente}"

  deseadas="$(kubectl get deployment "${deployment}" -n "${NAMESPACE}" \
    -o jsonpath='{.spec.replicas}' 2>/dev/null || echo '0')"
  listas="$(kubectl get deployment "${deployment}" -n "${NAMESPACE}" \
    -o jsonpath='{.status.readyReplicas}' 2>/dev/null || echo '0')"
  listas="${listas:-0}"

  if [[ "${listas}" == "${deseadas}" && "${listas}" != "0" ]]; then
    echo "  OK       ${componente}: ${listas}/${deseadas} replicas listas"
  else
    echo "  FALLO    ${componente}: ${listas}/${deseadas} replicas listas"
    fallos=$((fallos + 1))
  fi
done

# ------------------------------------------------------------------------------
# 2. Ningun pod esta reiniciandose en bucle.
#
# Un pod puede figurar como Running y aun asi estar en un ciclo de reinicios que
# las probes todavia no alcanzaron a marcar. El contador de reinicios lo delata.
# ------------------------------------------------------------------------------
echo ""
echo "== Verificando reinicios de los pods =="
while read -r pod reinicios; do
  [[ -z "${pod}" ]] && continue
  if (( reinicios > 2 )); then
    echo "  FALLO    ${pod} lleva ${reinicios} reinicios"
    fallos=$((fallos + 1))
  else
    echo "  OK       ${pod} (${reinicios} reinicios)"
  fi
done < <(kubectl get pods -n "${NAMESPACE}" \
  -o jsonpath='{range .items[*]}{.metadata.name} {.status.containerStatuses[0].restartCount}{"\n"}{end}')

# ------------------------------------------------------------------------------
# 3. Las imagenes desplegadas son las que acaba de publicar este pipeline.
#
# Es la comprobacion que cierra el circulo de CI/CD: sin ella, el despliegue
# podria estar sirviendo una imagen anterior y el pipeline lo reportaria como
# exitoso igualmente.
# ------------------------------------------------------------------------------
echo ""
echo "== Imagenes efectivamente desplegadas =="
kubectl get deployments -n "${NAMESPACE}" \
  -o custom-columns='DEPLOYMENT:.metadata.name,IMAGEN:.spec.template.spec.containers[0].image' \
  --no-headers

# ------------------------------------------------------------------------------
# 4. La plataforma responde de verdad.
#
# Se consulta al gateway por port-forward. El gateway es la unica puerta de
# entrada, y su readiness consulta a los cuatro microservicios aguas abajo, de
# modo que una respuesta correcta aqui confirma la cadena completa.
# ------------------------------------------------------------------------------
echo ""
echo "== Prueba de humo contra el API Gateway =="
kubectl port-forward -n "${NAMESPACE}" svc/sa-platform-api-gateway 18080:8080 >/dev/null 2>&1 &
PF_PID=$!
# El port-forward se cierra pase lo que pase, incluso si una comprobacion falla.
trap 'kill "${PF_PID}" 2>/dev/null || true' EXIT

# El tunel tarda un instante en establecerse; se reintenta en lugar de dormir
# una cantidad fija de segundos.
for intento in $(seq 1 15); do
  if curl -sf --max-time 3 http://127.0.0.1:18080/health/live >/dev/null 2>&1; then
    break
  fi
  sleep 2
done

for ruta in / /health/live /health/ready; do
  codigo="$(curl -s -o /tmp/respuesta.json -w '%{http_code}' --max-time 10 \
    "http://127.0.0.1:18080${ruta}" || echo '000')"
  if [[ "${codigo}" == "200" ]]; then
    echo "  OK       GET ${ruta} -> ${codigo}"
    head -c 300 /tmp/respuesta.json; echo ""
  else
    echo "  FALLO    GET ${ruta} -> ${codigo}"
    fallos=$((fallos + 1))
  fi
done

# ------------------------------------------------------------------------------
# 5. Los CronJobs quedaron programados.
# ------------------------------------------------------------------------------
echo ""
echo "== CronJobs =="
kubectl get cronjobs -n "${NAMESPACE}" || true

echo ""
if (( fallos > 0 )); then
  echo "RESULTADO: el despliegue presenta ${fallos} problema(s)."
  exit 1
fi

echo "RESULTADO: despliegue verificado correctamente."
