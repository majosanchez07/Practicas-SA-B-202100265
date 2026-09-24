#!/usr/bin/env bash
# ==============================================================================
# Escenario de desastre: destruccion total del entorno.
#
# Practica 9 - Maria Jose Tebalan Sanchez - 202100265
#
# Destruye el grupo del cluster completo (AKS, nodos, discos en uso, red).
# Sobrevive solo lo que vive fuera: el repositorio Git y el grupo base con el
# estado de Terraform, los respaldos de Velero, sus snapshots y el Key Vault.
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

export ARM_SUBSCRIPTION_ID="$(az account show --query id -o tsv)"
log "$REG" "DESASTRE: terraform destroy de la capa cluster (grupo $RG_CLUSTER: AKS, nodos, discos en uso, red, identidad de Velero)"
terraform -chdir="$P9/terraform/cluster" init -input=false >/dev/null
terraform -chdir="$P9/terraform/cluster" destroy -input=false -auto-approve
log "$REG" "DESASTRE COMPLETO: cluster destruido. Desde esta marca corre el RTO."
log "$REG" "Sobrevive solo $RG_BASE: $(az resource list -g "$RG_BASE" --query "length(@)" -o tsv) recursos (estado, respaldos, snapshots, Key Vault)"
echo "Registro: $REG"
