#!/usr/bin/env bash
# Variables y funciones compartidas por los scripts de la Practica 9 (Azure).
# Practica 9 - Maria Jose Tebalan Sanchez - 202100265
set -euo pipefail

RAIZ_REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
P9="$RAIZ_REPO/P9"
REGION="centralus"                      # region distinta de la del proyecto (eastus / eastus2)
RG_BASE="rg-sa-p9-base-202100265"       # lo que sobrevive al desastre: estado, respaldos, llave
RG_CLUSTER="rg-sa-p9-202100265"         # lo que se destruye y se reconstruye
CLUSTER="aks-sa-p9-202100265"
SA_ESTADO="sap9tfstate202100265"
SA_VELERO="sap9velero202100265"
KEYVAULT="kv-sa-p9-202100265"
SECRETO_LLAVE="sealed-secrets-key"
NS_APP="sa-p8"                          # namespace heredado de la P8 (chart y SealedSecrets lo usan)
SCHEDULE="respaldo-sa-p9"
APP_RAIZ="raiz-sa-p9"
EVID="$P9/docs/evidencias"

ahora() { date -u +%Y-%m-%dT%H:%M:%SZ; }
epoch() { date -u +%s; }
# log <archivo> <mensaje>: imprime y agrega al registro con marca de tiempo UTC.
log() { local f="$1"; shift; echo "$(ahora) | $*" | tee -a "$f"; }

psql_app() {
  # Ejecuta SQL dentro del pod de PostgreSQL con el usuario de la aplicacion.
  kubectl -n "$NS_APP" exec sa-platform-postgresql-0 -c postgresql -- \
    bash -c "PGPASSWORD=\"\$POSTGRES_PASSWORD\" psql -h 127.0.0.1 -U biblioteca -d biblioteca -v ON_ERROR_STOP=1 -At -c \"$1\""
}
