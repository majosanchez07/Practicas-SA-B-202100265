#!/usr/bin/env bash
# Despliega la plataforma en el clúster de la nube (requisitos 3, 4, 5 y 6).
#
# Las credenciales NO estan en el repositorio: se leen de variables de entorno,
# y si no existen se generan al vuelo. Helm las materializa en un Secret dentro
# del clúster (requisito 6).
set -euo pipefail
# pipefail ya cubre el caso "helm | tee": sin el, un fallo de helm quedaria oculto
# tras el exit 0 de tee.
cd "$(dirname "$0")/.."
source scripts/00-variables.sh

gen() { openssl rand -base64 24 | tr -d '\n/+=' | head -c 32; }
JWT="${JWT_SECRET_KEY:-$(gen)}"
AES="${AES_SECRET_KEY:-$(gen)}"
PGPASS="${PG_PASSWORD:-$(gen)}"
MQPASS="${MQ_PASSWORD:-$(gen)}"
COOKIE="${MQ_COOKIE:-$(gen)}"

SETS=""
for s in $SERVICES;  do SETS="$SETS --set services.$s.image.registry=$ECR"; done
for c in $CRONJOBS;  do SETS="$SETS --set cronjobs.$c.image.registry=$ECR"; done

echo ">> Desplegando release $RELEASE en el namespace $NAMESPACE"
helm upgrade --install "$RELEASE" charts/sa-platform \
  --namespace "$NAMESPACE" --create-namespace \
  -f charts/sa-platform/values-eks.yaml \
  $SETS \
  --set global.imageTag="$IMAGE_TAG" \
  --set namespace.name="$NAMESPACE" \
  --set secrets.jwtSecretKey="$JWT" \
  --set secrets.aesSecretKey="$AES" \
  --set postgresql.auth.username=biblioteca \
  --set postgresql.auth.password="$PGPASS" \
  --set postgresql.auth.postgresPassword="$PGPASS" \
  --set rabbitmq.auth.username=biblioteca \
  --set rabbitmq.auth.password="$MQPASS" \
  --set rabbitmq.auth.erlangCookie="$COOKIE" \
  --wait --timeout 15m

echo ">> Esperando la direccion publica del Network Load Balancer..."
# AWS tarda entre 2 y 4 minutos en aprovisionar el NLB y propagar su DNS.
for i in $(seq 1 60); do
  LB=$(kubectl get svc -n "$NAMESPACE" -l sa-platform.io/role=public-entrypoint \
       -o jsonpath='{.items[0].status.loadBalancer.ingress[0].hostname}' 2>/dev/null || true)
  [ -n "$LB" ] && break
  sleep 10
done

if [ -z "${LB:-}" ]; then
  echo "!! El LoadBalancer sigue sin direccion. Revisar: kubectl describe svc -n $NAMESPACE"
  exit 1
fi

echo ">> Direccion publica: http://$LB"
echo "$LB" > .direccion-publica
kubectl get pods -n "$NAMESPACE" -o wide
