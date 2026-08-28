#!/usr/bin/env bash
# =============================================================================
# levantar.sh — De un cluster vacio a la plataforma funcionando, en un comando.
#
#   ./levantar.sh            instala (perfil dev)
#   ./levantar.sh prod       instala con values-prod.yaml
#   ./levantar.sh --limpiar  destruye el cluster y sale
#
# Practica 5 — Software Avanzado, Seccion B
# Maria Jose Tebalan Sanchez — Carne 202100265
# =============================================================================
set -euo pipefail

PERFIL=sa-p5
NS=sa-p5
RELEASE=sa-platform
CHART_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/charts/sa-platform"
AMBIENTE="${1:-dev}"

log() { printf '\n\033[1;34m==> %s\033[0m\n' "$*"; }

if [[ "$AMBIENTE" == "--limpiar" ]]; then
  log "Destruyendo el cluster $PERFIL"
  minikube delete --profile="$PERFIL"
  exit 0
fi

VALUES_AMB="$CHART_DIR/values-${AMBIENTE}.yaml"
[[ -f "$VALUES_AMB" ]] || { echo "No existe $VALUES_AMB"; exit 1; }

# --- 0. Verificar herramientas -----------------------------------------------
log "Verificando herramientas"
for t in docker kubectl helm minikube; do
  command -v "$t" >/dev/null || { echo "Falta '$t' en el PATH."; exit 1; }
done
docker info >/dev/null 2>&1 || { echo "El demonio de Docker no responde."; exit 1; }
echo "docker, kubectl, helm y minikube disponibles."

# --- 1. Cluster ---------------------------------------------------------------
# Calico es obligatorio: el CNI por defecto de minikube acepta las
# NetworkPolicies pero las ignora en silencio, y el aislamiento no se aplicaria.
if minikube status --profile="$PERFIL" 2>/dev/null | grep -q 'host: Running'; then
  log "El cluster '$PERFIL' ya esta corriendo, se reutiliza"
else
  log "Creando el cluster '$PERFIL' con CNI Calico"
  minikube start --driver=docker --cpus=4 --memory=6144 \
    --kubernetes-version=v1.31.0 --cni=calico --profile="$PERFIL"
fi

log "Habilitando addons (ingress y metrics-server)"
minikube addons enable ingress        --profile="$PERFIL"
minikube addons enable metrics-server --profile="$PERFIL"

log "Esperando a que Calico y el Ingress Controller esten listos"
kubectl wait --for=condition=Ready pod -l k8s-app=calico-node \
  -n kube-system --timeout=300s
kubectl wait --for=condition=Ready pod \
  -l app.kubernetes.io/component=controller \
  -n ingress-nginx --timeout=300s

# --- 2. Imagenes --------------------------------------------------------------
# El tag va por imagen: 'minikube image load' no reemplaza un tag que ya existe
# en el nodo, y con IfNotPresent los pods seguirian usando la version anterior.
log "Construyendo las 7 imagenes (multi-stage)"
IMAGENES=(
  "api-gateway:v1:services/api-gateway"
  "auth-service:v1:services/auth-service"
  "books-service:v1:services/books-service"
  "loans-service:v2:services/loans-service"
  "notifications-service:v2:services/notifications-service"
  "cronjob-insert:v1:cronjobs/cronjob-insert"
  "cronjob-summary:v1:cronjobs/cronjob-summary"
)
cd "$(dirname "$CHART_DIR")/.."
for spec in "${IMAGENES[@]}"; do
  IFS=':' read -r nombre tag ruta <<< "$spec"
  echo "  -> sa-p5/$nombre:$tag"
  docker build -q -t "sa-p5/$nombre:$tag" "$ruta" >/dev/null
done

log "Cargando las imagenes en el cluster"
for spec in "${IMAGENES[@]}"; do
  IFS=':' read -r nombre tag _ <<< "$spec"
  echo "  -> sa-p5/$nombre:$tag"
  minikube image load "sa-p5/$nombre:$tag" --profile="$PERFIL"
done

# --- 3. Dependencias del chart ------------------------------------------------
log "Resolviendo dependencias del chart (PostgreSQL y RabbitMQ)"
helm repo add bitnami https://charts.bitnami.com/bitnami >/dev/null 2>&1 || true
helm repo update >/dev/null
helm dependency build "$CHART_DIR" >/dev/null

# --- 4. Credenciales ----------------------------------------------------------
# Ninguna credencial se versiona: values.secret.yaml esta en .gitignore y se
# genera aqui con openssl si aun no existe.
SECRETOS="$CHART_DIR/values.secret.yaml"
if [[ -f "$SECRETOS" ]]; then
  log "Reutilizando las credenciales existentes (values.secret.yaml)"
else
  log "Generando credenciales nuevas en values.secret.yaml (no versionado)"
  cat > "$SECRETOS" <<EOF
# Generado por levantar.sh. NO versionar (excluido en .gitignore).
postgresql:
  auth:
    username: biblioteca
    password: $(openssl rand -hex 16)
    database: biblioteca
    postgresPassword: $(openssl rand -hex 16)

rabbitmq:
  auth:
    username: biblioteca
    password: $(openssl rand -hex 16)
    erlangCookie: $(openssl rand -hex 32)

secrets:
  jwtSecretKey: $(openssl rand -hex 32)
  aesSecretKey: $(openssl rand -hex 16)
EOF
fi

# --- 5. Instalar --------------------------------------------------------------
# 'upgrade --install' hace el script idempotente: instala la primera vez y
# actualiza en las siguientes, sin fallar si el release ya existe.
log "Desplegando la plataforma (ambiente: $AMBIENTE)"
helm upgrade --install "$RELEASE" "$CHART_DIR" \
  --namespace "$NS" --create-namespace \
  -f "$VALUES_AMB" -f "$SECRETOS" \
  --timeout 10m --wait

# --- 6. Resultado -------------------------------------------------------------
IP="$(minikube ip --profile="$PERFIL")"
log "Estado del despliegue"
kubectl get pods -n "$NS"
helm history "$RELEASE" -n "$NS"

log "Comprobando el Ingress"
curl -fsS -m 20 -H "Host: sa-p5.local" "http://$IP/health/ready" && echo

cat <<FIN

-------------------------------------------------------------------
 Plataforma lista.

   Gateway:  curl -H "Host: sa-p5.local" http://$IP/

   Para usarlo en el navegador, agrega a /etc/hosts:
     $IP  sa-p5.local

   Destruir todo:  ./levantar.sh --limpiar
-------------------------------------------------------------------
FIN
