#!/usr/bin/env bash
# Variables y funciones compartidas por los scripts de la Practica 9.
# Practica 9 - Maria Jose Tebalan Sanchez - 202100265
set -euo pipefail

RAIZ_REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
P9="$RAIZ_REPO/P9"
REGION="us-east-2"
CLUSTER="sa-p8-202100265"          # nombre heredado de la P8: SealedSecrets y values lo referencian
NS_APP="sa-p8"
BUCKET_ESTADO="sa-p9-tfstate-202100265"
TABLA_BLOQUEO="sa-p9-tfstate-lock"
BUCKET_VELERO="sa-p9-velero-202100265"
SECRETO_LLAVE="sa-p9/sealed-secrets-key"
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
