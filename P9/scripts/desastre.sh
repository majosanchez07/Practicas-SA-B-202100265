#!/usr/bin/env bash
# ==============================================================================
# Escenario de desastre: destruccion total del entorno.
#
# Practica 9 - Maria Jose Tebalan Sanchez - 202100265
#
# Destruye el cluster EKS completo (nodos, plano de control, volumenes en uso,
# red). Sobrevive solo lo que vive fuera: el repositorio Git, el estado remoto
# de Terraform, el bucket de Velero con sus snapshots EBS y la llave en
# Secrets Manager.
#
# Uso: ./P9/scripts/desastre.sh   (pide escribir DESTRUIR para continuar)
# ==============================================================================
source "$(dirname "$0")/comun.sh"

read -r -p "Esto destruye el cluster $CLUSTER. Escriba DESTRUIR: " ok
[ "$ok" = "DESTRUIR" ] || exit 1

mkdir -p "$EVID/reconstruccion"
REG="$EVID/reconstruccion/desastre-$(date -u +%Y%m%dT%H%M%SZ).log"

log "$REG" "ESTADO PREVIO: ultimo respaldo completado = $(velero backup get -o json | jq -r '(if .items then .items else [.] end) | map(select(.status.phase=="Completed")) | sort_by(.status.completionTimestamp) | last | "\(.metadata.name) @ \(.status.completionTimestamp)"')"
log "$REG" "ESTADO PREVIO: filas en cronjobs.ejecuciones = $(psql_app 'SELECT count(*) FROM cronjobs.ejecuciones' || echo '?')"
log "$REG" "ESTADO PREVIO: ultima fila = $(psql_app 'SELECT max(ejecutado_en) FROM cronjobs.ejecuciones' || echo '?')"

log "$REG" "DESASTRE 1: se detiene ArgoCD y se eliminan los Service LoadBalancer (evita balanceadores huerfanos que bloqueen el borrado de la VPC)"
kubectl -n argocd scale statefulset argocd-application-controller --replicas=0 || true
kubectl get svc -A -o json | jq -r '.items[] | select(.spec.type=="LoadBalancer") | "\(.metadata.namespace) \(.metadata.name)"' \
  | while read -r ns n; do kubectl -n "$ns" delete svc "$n" --wait=true; done

log "$REG" "DESASTRE 2: terraform destroy del cluster (EKS, nodos, VPC, roles IRSA)"
terraform -chdir="$P9/terraform/cluster" init -input=false >/dev/null
terraform -chdir="$P9/terraform/cluster" destroy -input=false -auto-approve
log "$REG" "DESASTRE COMPLETO: cluster destruido. Desde esta marca corre el RTO."

# Los volumenes EBS que estaban montados quedan huerfanos (estado available).
# Se eliminan para no pagar por ellos: la copia valida es el snapshot de Velero.
for v in $(aws ec2 describe-volumes --region "$REGION" \
    --filters Name=status,Values=available Name=tag:kubernetes.io/created-for/pvc/namespace,Values="$NS_APP" \
    --query 'Volumes[].VolumeId' --output text); do
  aws ec2 delete-volume --region "$REGION" --volume-id "$v" && log "$REG" "volumen huerfano eliminado: $v"
done
echo "Registro: $REG"
