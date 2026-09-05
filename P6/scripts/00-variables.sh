#!/usr/bin/env bash
# Variables compartidas por todos los scripts de la practica 6.
# Se cargan con:  source scripts/00-variables.sh
export AWS_REGION="${AWS_REGION:-us-east-2}"
export CLUSTER_NAME="${CLUSTER_NAME:-sa-p6-202100265}"
export NAMESPACE="${NAMESPACE:-sa-p6}"
export RELEASE="${RELEASE:-sa-p6}"
export NODE_TYPE="${NODE_TYPE:-t3.small}"
export NODE_COUNT="${NODE_COUNT:-2}"
export SERVICES="api-gateway auth-service books-service loans-service notifications-service"
export CRONJOBS="insert summary"
# El tag se fija la PRIMERA vez y queda anotado en .image-tag.
#
# Antes se derivaba directamente de "git rev-parse HEAD", pero eso ata el tag al
# commit actual: basta con hacer un commit entre publicar las imagenes y
# desplegar para que el chart pida un tag que nunca se construyo, y los pods
# quedan en ImagePullBackOff. El archivo .image-tag mantiene la correspondencia
# entre lo que hay en ECR y lo que el chart solicita.
if [ -z "${IMAGE_TAG:-}" ]; then
  if [ -f "$(dirname "${BASH_SOURCE[0]}")/../.image-tag" ]; then
    IMAGE_TAG="$(cat "$(dirname "${BASH_SOURCE[0]}")/../.image-tag")"
  else
    IMAGE_TAG="$(git rev-parse --short HEAD 2>/dev/null || echo v1)"
  fi
fi
export IMAGE_TAG
# El id de cuenta se consulta, nunca se escribe en el repositorio.
if command -v aws >/dev/null 2>&1; then
  export ACCOUNT_ID="${ACCOUNT_ID:-$(aws sts get-caller-identity --query Account --output text 2>/dev/null)}"
  export ECR="${ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com"
fi
