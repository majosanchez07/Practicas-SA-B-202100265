#!/usr/bin/env bash
# Elimina TODOS los recursos creados (requisito 9 del enunciado).
#
# El orden importa: primero el release de Helm, para que el controlador de AWS
# borre el Network Load Balancer. Si se destruye el clúster antes, el NLB y sus
# security groups quedan huerfanos, bloquean el borrado de la VPC y siguen
# generando costo.
set -euo pipefail
cd "$(dirname "$0")/.."
source scripts/00-variables.sh

echo ">> 1/4 Desinstalando el release (libera el Network Load Balancer)"
helm uninstall "$RELEASE" -n "$NAMESPACE" 2>/dev/null || echo "   (ya no existe)"

echo ">> 2/4 Esperando a que AWS retire el balanceador..."
for i in $(seq 1 30); do
  kubectl get svc -n "$NAMESPACE" -l sa-platform.io/role=public-entrypoint 2>/dev/null | grep -q . || break
  sleep 10
done

echo ">> 3/4 Borrando los volumenes EBS (los PVC no se eliminan con el release)"
kubectl delete pvc --all -n "$NAMESPACE" 2>/dev/null || true
kubectl delete namespace "$NAMESPACE" 2>/dev/null || true

echo ">> 4/4 Destruyendo el clúster, su VPC y el grupo de nodos"
eksctl delete cluster --name "$CLUSTER_NAME" --region "$AWS_REGION" --wait

echo ">> Borrando los repositorios de ECR"
for s in $SERVICES; do
  aws ecr delete-repository --repository-name "sa-p6/$s" --region "$AWS_REGION" --force 2>/dev/null || true
done
for c in $CRONJOBS; do
  aws ecr delete-repository --repository-name "sa-p6/cronjob-$c" --region "$AWS_REGION" --force 2>/dev/null || true
done

echo ">> Verificacion final (no debe quedar nada):"
eksctl get cluster --region "$AWS_REGION" 2>&1 | grep -i "$CLUSTER_NAME" || echo "   clúster eliminado"
aws elbv2 describe-load-balancers --region "$AWS_REGION" \
  --query 'LoadBalancers[].LoadBalancerName' --output text 2>/dev/null || true
