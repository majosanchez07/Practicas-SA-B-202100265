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
export IMAGE_TAG="${IMAGE_TAG:-$(git rev-parse --short HEAD 2>/dev/null || echo v1)}"
# El id de cuenta se consulta, nunca se escribe en el repositorio.
if command -v aws >/dev/null 2>&1; then
  export ACCOUNT_ID="${ACCOUNT_ID:-$(aws sts get-caller-identity --query Account --output text 2>/dev/null)}"
  export ECR="${ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com"
fi
