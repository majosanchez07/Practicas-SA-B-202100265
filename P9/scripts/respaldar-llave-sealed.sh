#!/usr/bin/env bash
# ==============================================================================
# Llave de Sealed Secrets: fuera del cluster, en Azure Key Vault.
#
#   ./respaldar-llave-sealed.sh generar  -> crea un par nuevo (solo la primera vez
#                                           o en una rotacion deliberada)
#   ./respaldar-llave-sealed.sh          -> copia al vault la llave activa del cluster
#
# Clasificacion (clase 17/09): esta llave es IRRECUPERABLE. Terraform la lee
# del vault y la instala antes que el controlador (platform/continuidad.tf).
# El certificado publico queda en P9/docs/sealed-secrets-cert.pem para cifrar
# sin acceso al cluster: kubeseal --cert P9/docs/sealed-secrets-cert.pem
# ==============================================================================
source "$(dirname "$0")/comun.sh"
TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT

if [ "${1:-}" = "generar" ]; then
  openssl req -x509 -nodes -newkey rsa:4096 -days 3650 \
    -keyout "$TMP/tls.key" -out "$TMP/tls.crt" -subj "/CN=sealed-secret/O=sealed-secret" 2>/dev/null
  CRT=$(base64 -w0 < "$TMP/tls.crt"); KEY=$(base64 -w0 < "$TMP/tls.key")
else
  J=$(kubectl -n sealed-secrets get secret -l sealedsecrets.bitnami.com/sealed-secrets-key=active \
      --sort-by=.metadata.creationTimestamp -o json | jq '.items[-1].data')
  CRT=$(echo "$J" | jq -r '.["tls.crt"]'); KEY=$(echo "$J" | jq -r '.["tls.key"]')
fi

jq -nc --arg c "$CRT" --arg k "$KEY" '{"tls.crt":$c,"tls.key":$k}' > "$TMP/llave.json"
az keyvault secret set --vault-name "$KEYVAULT" --name "$SECRETO_LLAVE" \
  --file "$TMP/llave.json" --content-type application/json -o none
echo "$CRT" | base64 -d > "$P9/docs/sealed-secrets-cert.pem"
openssl x509 -in "$P9/docs/sealed-secrets-cert.pem" -noout -fingerprint -sha256
echo "Llave guardada en Key Vault $KEYVAULT/$SECRETO_LLAVE; certificado publico en P9/docs/sealed-secrets-cert.pem"
