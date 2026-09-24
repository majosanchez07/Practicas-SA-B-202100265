#!/usr/bin/env bash
# ==============================================================================
# Prerrequisito de una sola vez: los recursos que NO pueden vivir en el estado
# de Terraform que protegen.
#
#   - Bucket S3 del estado de Terraform (versionado, cifrado, sin acceso publico)
#   - Tabla DynamoDB para el bloqueo del estado
#   - Bucket S3 de Velero (respaldos fuera del cluster)
#
# Es idempotente: si algo ya existe, lo deja como esta. No se destruye en la
# prueba de DR: es el "piso" desde el que se reconstruye todo lo demas.
# ==============================================================================
source "$(dirname "$0")/comun.sh"

crear_bucket() {
  local b="$1"
  if aws s3api head-bucket --bucket "$b" 2>/dev/null; then
    echo "bucket $b ya existe"
  else
    aws s3api create-bucket --bucket "$b" --region "$REGION" \
      --create-bucket-configuration LocationConstraint="$REGION" >/dev/null
    echo "bucket $b creado"
  fi
  aws s3api put-bucket-versioning --bucket "$b" --versioning-configuration Status=Enabled
  aws s3api put-bucket-encryption --bucket "$b" --server-side-encryption-configuration \
    '{"Rules":[{"ApplyServerSideEncryptionByDefault":{"SSEAlgorithm":"AES256"}}]}'
  aws s3api put-public-access-block --bucket "$b" --public-access-block-configuration \
    BlockPublicAcls=true,IgnorePublicAcls=true,BlockPublicPolicy=true,RestrictPublicBuckets=true
}

crear_bucket "$BUCKET_ESTADO"
crear_bucket "$BUCKET_VELERO"

if aws dynamodb describe-table --table-name "$TABLA_BLOQUEO" --region "$REGION" >/dev/null 2>&1; then
  echo "tabla $TABLA_BLOQUEO ya existe"
else
  aws dynamodb create-table --table-name "$TABLA_BLOQUEO" --region "$REGION" \
    --attribute-definitions AttributeName=LockID,AttributeType=S \
    --key-schema AttributeName=LockID,KeyType=HASH \
    --billing-mode PAY_PER_REQUEST >/dev/null
  aws dynamodb wait table-exists --table-name "$TABLA_BLOQUEO" --region "$REGION"
  echo "tabla $TABLA_BLOQUEO creada"
fi
