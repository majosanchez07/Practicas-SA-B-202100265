#!/usr/bin/env bash
# ==============================================================================
# PUNTO DE ENTRADA UNICO - reconstruccion completa desde cero
#
# Practica 9 - Maria Jose Tebalan Sanchez - 202100265
#
# Uso:   ./P9/scripts/bootstrap.sh
# Requiere: credenciales de AWS de la cuenta, terraform, kubectl, velero, jq.
#
# Orden (ver docs/diagrama-bootstrap.md):
#   1. Terraform cluster/  -> VPC, EKS, nodos, roles IRSA (EBS CSI, Velero)
#   2. Terraform platform/ -> namespaces, cuotas, RBAC, StorageClass,
#                             llave de Sealed Secrets (desde Secrets Manager),
#                             Sealed Secrets, Velero, ArgoCD
#   3. Velero              -> restaura los volumenes del ultimo respaldo
#   4. Terraform platform/ -> aplicacion raiz (app-of-apps)
#   5. ArgoCD              -> Rollouts, Kyverno, politicas, secretos, schedule,
#                             sa-platform (que adopta los volumenes restaurados)
#
# Ningun paso pide intervencion. Cada paso deja una marca de tiempo en el
# registro, del que se calcula el RTO real.
# ==============================================================================
source "$(dirname "$0")/comun.sh"

mkdir -p "$EVID/reconstruccion"
REG="$EVID/reconstruccion/registro-$(date -u +%Y%m%dT%H%M%SZ).log"
T0=$(epoch)
log "$REG" "INICIO bootstrap (operador: $(aws sts get-caller-identity --query Arn --output text))"

# --- 0. Prerrequisitos que viven fuera del cluster ----------------------------
aws s3api head-bucket --bucket "$BUCKET_ESTADO"
aws s3api head-bucket --bucket "$BUCKET_VELERO"
aws secretsmanager describe-secret --secret-id "$SECRETO_LLAVE" --region "$REGION" >/dev/null
log "$REG" "PASO 0 OK: backend remoto, bucket de respaldos y llave externa disponibles"

# --- 1. Cluster ----------------------------------------------------------------
terraform -chdir="$P9/terraform/cluster" init -input=false -reconfigure >/dev/null
terraform -chdir="$P9/terraform/cluster" apply -input=false -auto-approve
aws eks update-kubeconfig --region "$REGION" --name "$CLUSTER" >/dev/null
kubectl wait --for=condition=Ready nodes --all --timeout=600s
log "$REG" "PASO 1 OK: cluster EKS y nodos listos ($(kubectl get nodes --no-headers | wc -l) nodos)"

# --- 2. Plataforma sin la aplicacion raiz ------------------------------------
terraform -chdir="$P9/terraform/platform" init -input=false -reconfigure >/dev/null
terraform -chdir="$P9/terraform/platform" apply -input=false -auto-approve -var crear_app_raiz=false
log "$REG" "PASO 2 OK: Sealed Secrets (llave restaurada), Velero y ArgoCD instalados"

# --- 3. Restauracion de volumenes ----------------------------------------------
# Velero sincroniza el catalogo del bucket al arrancar; se espera a que aparezca.
ULTIMO=""
for _ in $(seq 1 30); do
  ULTIMO=$(velero backup get -o json 2>/dev/null | jq -r '
      (if .items then .items else [.] end)
      | map(select(.status.phase=="Completed"))
      | sort_by(.status.completionTimestamp) | last | .metadata.name // empty')
  [ -n "$ULTIMO" ] && break
  sleep 10
done
if [ -n "$ULTIMO" ]; then
  log "$REG" "PASO 3: restaurando volumenes desde el respaldo $ULTIMO"
  velero restore create "bootstrap-$(date -u +%Y%m%d%H%M%S)" --from-backup "$ULTIMO" \
    --include-namespaces "$NS_APP" \
    --include-resources persistentvolumeclaims,persistentvolumes \
    --restore-volumes=true --wait
  log "$REG" "PASO 3 OK: volumenes restaurados ($(kubectl -n "$NS_APP" get pvc --no-headers | wc -l) PVC)"
else
  log "$REG" "PASO 3 OMITIDO: no hay respaldos completados en el bucket (instalacion inicial)"
fi

# --- 4. Aplicacion raiz --------------------------------------------------------
terraform -chdir="$P9/terraform/platform" apply -input=false -auto-approve -var crear_app_raiz=true
log "$REG" "PASO 4 OK: aplicacion raiz $APP_RAIZ creada"

# --- 5. Esperar a que GitOps levante todo -------------------------------------
esperar_app() {
  local app="$1"
  for _ in $(seq 1 90); do
    local s h
    s=$(kubectl -n argocd get application "$app" -o jsonpath='{.status.sync.status}' 2>/dev/null || true)
    h=$(kubectl -n argocd get application "$app" -o jsonpath='{.status.health.status}' 2>/dev/null || true)
    [ "$s" = "Synced" ] && [ "$h" = "Healthy" ] && return 0
    sleep 10
  done
  return 1
}
for app in "$APP_RAIZ" argo-rollouts kyverno secretos-cifrados politicas-admision respaldos-velero sa-platform; do
  if esperar_app "$app"; then log "$REG" "PASO 5: $app Synced/Healthy"
  else log "$REG" "PASO 5 ALERTA: $app no alcanzo Synced/Healthy en 15 min"; fi
done

# --- 6. Verificaciones de continuidad -----------------------------------------
kubectl -n "$NS_APP" get secret sa-platform-secret >/dev/null \
  && log "$REG" "VERIFICACION: SealedSecret descifrado (Secret sa-platform-secret presente)"
kubectl -n "$NS_APP" wait --for=condition=Ready pod/sa-platform-postgresql-0 --timeout=300s >/dev/null
FILAS=$(psql_app "SELECT count(*) FROM cronjobs.ejecuciones" || echo "error")
log "$REG" "VERIFICACION: filas en cronjobs.ejecuciones tras reconstruir = $FILAS"
VER=$(psql_app "SELECT string_agg(nota, ', ') FROM dr.verificacion" 2>/dev/null || echo "sin tabla")
log "$REG" "VERIFICACION: marcas de verificacion restauradas = $VER"
log "$REG" "VERIFICACION: politicas activas = $(kubectl get clusterpolicy --no-headers 2>/dev/null | wc -l)"
log "$REG" "VERIFICACION: schedule = $(kubectl -n velero get schedule "$SCHEDULE" -o jsonpath='{.status.phase}' 2>/dev/null)"

T1=$(epoch)
log "$REG" "FIN bootstrap. Duracion del bootstrap = $(( (T1-T0)/60 )) min $(( (T1-T0)%60 )) s"
echo "Registro: $REG"
