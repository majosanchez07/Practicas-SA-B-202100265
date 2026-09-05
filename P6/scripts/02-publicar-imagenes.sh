#!/usr/bin/env bash
# Construye y publica las 7 imagenes en Amazon ECR (requisito 2 del enunciado).
set -euo pipefail
cd "$(dirname "$0")/.."
source scripts/00-variables.sh

echo ">> Autenticando Docker contra ECR"
aws ecr get-login-password --region "$AWS_REGION" \
  | docker login --username AWS --password-stdin "$ECR"

build_push() {
  local repo="$1" ctx="$2"
  aws ecr describe-repositories --repository-names "$repo" --region "$AWS_REGION" >/dev/null 2>&1 \
    || aws ecr create-repository --repository-name "$repo" --region "$AWS_REGION" \
         --image-scanning-configuration scanOnPush=true >/dev/null
  echo ">> $repo:$IMAGE_TAG"
  # --platform linux/amd64 es obligatorio: los nodos t3.small son x86_64 y una
  # imagen construida en otra arquitectura fallaria con "exec format error".
  # Dockerfile.prod es la construccion multietapa de produccion (deps -> build
  # -> prod). --target prod es explicito para no depender de que sea la ultima.
  docker build --platform linux/amd64 \
    -f "$ctx/Dockerfile.prod" --target prod \
    -t "$ECR/$repo:$IMAGE_TAG" "$ctx"
  docker push "$ECR/$repo:$IMAGE_TAG"
}

for s in $SERVICES;  do build_push "sa-p6/$s" "services/$s"; done
for c in $CRONJOBS;  do build_push "sa-p6/cronjob-$c" "cronjobs/cronjob-$c"; done

# Se anota el tag publicado para que 03-desplegar.sh pida exactamente estas
# imagenes aunque entretanto se haya hecho un commit.
echo "$IMAGE_TAG" > .image-tag
echo ">> Imagenes publicadas con el tag $IMAGE_TAG"
aws ecr describe-repositories --region "$AWS_REGION" \
  --query 'repositories[?starts_with(repositoryName,`sa-p6/`)].repositoryUri' --output table
