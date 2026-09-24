#!/usr/bin/env bash
# ==============================================================================
# Copia la llave privada de Sealed Secrets del cluster a AWS Secrets Manager.
#
# Se ejecuta una vez (y despues de cualquier rotacion deliberada). A partir de
# ahi la llave vive FUERA del cluster y Terraform la reinyecta en cada
# reconstruccion antes de instalar el controlador (platform/continuidad.tf).
# ==============================================================================
source "$(dirname "$0")/comun.sh"

# La llave activa mas reciente del controlador.
LLAVE_JSON=$(kubectl -n sealed-secrets get secret \
  -l sealedsecrets.bitnami.com/sealed-secrets-key=active \
  --sort-by=.metadata.creationTimestamp -o json | jq -c '.items[-1].data | {"tls.crt": .["tls.crt"], "tls.key": .["tls.key"]}')

[ "$(echo "$LLAVE_JSON" | jq -r '.["tls.key"]')" != "null" ] || { echo "No se encontro la llave"; exit 1; }

if aws secretsmanager describe-secret --secret-id "$SECRETO_LLAVE" --region "$REGION" >/dev/null 2>&1; then
  aws secretsmanager put-secret-value --secret-id "$SECRETO_LLAVE" --region "$REGION" \
    --secret-string "$LLAVE_JSON" >/dev/null
else
  aws secretsmanager create-secret --name "$SECRETO_LLAVE" --region "$REGION" \
    --description "Llave privada de Sealed Secrets (P9 SA 202100265)" \
    --secret-string "$LLAVE_JSON" >/dev/null
fi

# Huella del certificado, para comparar despues de la reconstruccion.
echo "$LLAVE_JSON" | jq -r '.["tls.crt"]' | base64 -d | openssl x509 -noout -fingerprint -sha256
echo "Llave respaldada en Secrets Manager: $SECRETO_LLAVE"
