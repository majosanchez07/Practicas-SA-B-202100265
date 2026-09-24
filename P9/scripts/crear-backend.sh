#!/usr/bin/env bash
# ==============================================================================
# Prerrequisito de una sola vez: lo que NO puede vivir en el estado de
# Terraform que protege, ni morir junto con el cluster.
#
#   Grupo rg-sa-p9-base-202100265 (centralus), que la prueba de DR no toca:
#   - Cuenta sap9tfstate202100265 / contenedor tfstate -> estado de Terraform.
#     El backend azurerm bloquea el estado con un lease sobre el blob.
#   - Cuenta sap9velero202100265 / contenedor velero   -> respaldos de Velero.
#     Los snapshots de disco tambien se guardan en este grupo.
#   - Key Vault kv-sa-p9-202100265                     -> llave de Sealed Secrets.
#
# Es idempotente: si algo ya existe, lo deja como esta.
# ==============================================================================
source "$(dirname "$0")/comun.sh"

YO=$(az ad signed-in-user show --query id -o tsv)
SUB=$(az account show --query id -o tsv)

az group create -n "$RG_BASE" -l "$REGION" --tags practica=p9 carne=202100265 -o none

for sa in "$SA_ESTADO" "$SA_VELERO"; do
  if ! az storage account show -n "$sa" -g "$RG_BASE" -o none 2>/dev/null; then
    az storage account create -n "$sa" -g "$RG_BASE" -l "$REGION" --sku Standard_LRS \
      --kind StorageV2 --min-tls-version TLS1_2 --allow-blob-public-access false -o none
  fi
  # Versionado + borrado suave: protegen el estado y los respaldos de un borrado accidental.
  az storage account blob-service-properties update --account-name "$sa" -g "$RG_BASE" \
    --enable-versioning true --enable-delete-retention true --delete-retention-days 7 -o none
done
az storage container create -n tfstate --account-name "$SA_ESTADO" --auth-mode login -o none 2>/dev/null \
  || az storage container create -n tfstate --account-name "$SA_ESTADO" -o none
az storage container create -n velero --account-name "$SA_VELERO" --auth-mode login -o none 2>/dev/null \
  || az storage container create -n velero --account-name "$SA_VELERO" -o none

if ! az keyvault show -n "$KEYVAULT" -o none 2>/dev/null; then
  az keyvault create -n "$KEYVAULT" -g "$RG_BASE" -l "$REGION" --enable-rbac-authorization true -o none
fi
# El operador necesita leer y escribir secretos del vault (modelo RBAC).
az role assignment create --assignee-object-id "$YO" --assignee-principal-type User \
  --role "Key Vault Secrets Officer" \
  --scope "/subscriptions/$SUB/resourceGroups/$RG_BASE/providers/Microsoft.KeyVault/vaults/$KEYVAULT" -o none 2>/dev/null || true
az role assignment create --assignee-object-id "$YO" --assignee-principal-type User \
  --role "Storage Blob Data Contributor" \
  --scope "/subscriptions/$SUB/resourceGroups/$RG_BASE" -o none 2>/dev/null || true

az resource list -g "$RG_BASE" -o table
