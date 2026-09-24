#!/usr/bin/env bash
# ==============================================================================
# Prueba de perdida de nodo: drenaje con el servicio respondiendo
#
# Practica 9 - Maria Jose Tebalan Sanchez - 202100265
#
# Un pod sonda (fuera de sa-p8) consulta el API Gateway cada segundo mientras
# se drena el nodo que aloja mas replicas. Los PodDisruptionBudget hacen que el
# drenaje espere a que haya reemplazos listos antes de desalojar la siguiente
# replica; la anti-afinidad garantiza que el otro nodo ya tenia replicas.
# ==============================================================================
source "$(dirname "$0")/comun.sh"

mkdir -p "$EVID/perdida-nodo"
REG="$EVID/perdida-nodo/drenaje-$(date -u +%Y%m%dT%H%M%SZ).log"
SONDEO="$EVID/perdida-nodo/sondeo-$(date -u +%Y%m%dT%H%M%SZ).log"
URL="http://sa-platform-api-gateway.$NS_APP.svc.cluster.local:8080/health/ready"

log "$REG" "=== PRUEBA DE PERDIDA DE NODO ==="
kubectl get pdb -n "$NS_APP" | tee -a "$REG"
kubectl get pods -n "$NS_APP" -o wide --no-headers | awk '{print $1, $7}' | tee -a "$REG"

NODO=$(kubectl get pods -n "$NS_APP" -o jsonpath='{range .items[*]}{.spec.nodeName}{"\n"}{end}' | sort | uniq -c | sort -rn | head -1 | awk '{print $2}')
log "$REG" "Nodo a drenar (el que aloja mas pods): $NODO"

kubectl delete pod sonda-dr -n default --ignore-not-found >/dev/null
kubectl run sonda-dr -n default --image=curlimages/curl:8.10.1 --restart=Never \
  --overrides='{"spec":{"affinity":{"nodeAffinity":{"requiredDuringSchedulingIgnoredDuringExecution":{"nodeSelectorTerms":[{"matchExpressions":[{"key":"kubernetes.io/hostname","operator":"NotIn","values":["'"$NODO"'"]}]}]}}}}}' \
  --command -- sh -c "while true; do echo \"\$(date -u +%H:%M:%S) \$(curl -s -o /dev/null -m 2 -w '%{http_code}' $URL)\"; sleep 1; done"
kubectl wait --for=condition=Ready pod/sonda-dr -n default --timeout=120s
sleep 10

log "$REG" "INICIO del drenaje de $NODO"
kubectl drain "$NODO" --ignore-daemonsets --delete-emptydir-data --timeout=600s 2>&1 | tee -a "$REG"
log "$REG" "FIN del drenaje"
sleep 30
kubectl get pods -n "$NS_APP" -o wide --no-headers | awk '{print $1, $3, $7}' | tee -a "$REG"

kubectl logs sonda-dr -n default > "$SONDEO"
TOTAL=$(wc -l < "$SONDEO"); OK=$(grep -c ' 200$' "$SONDEO" || true)
log "$REG" "Sondeo: $OK de $TOTAL peticiones con HTTP 200 durante la prueba ($(awk -v o="$OK" -v t="$TOTAL" 'BEGIN{printf "%.2f", 100*o/t}')%)"
grep -v ' 200$' "$SONDEO" | head -20 | sed 's/^/  no-200: /' | tee -a "$REG" || true

kubectl uncordon "$NODO"
kubectl delete pod sonda-dr -n default --wait=false
log "$REG" "Nodo $NODO devuelto al servicio (uncordon). Sondeo completo: $SONDEO"
