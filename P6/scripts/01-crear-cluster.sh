#!/usr/bin/env bash
# Crea el clúster EKS con 2 nodos (requisito 1 del enunciado).
#
# eksctl levanta detras: una VPC con subredes publicas y privadas, el plano de
# control administrado por AWS, un grupo de nodos gestionado, y los roles IAM
# necesarios. Tarda entre 15 y 20 minutos: el plano de control es lo mas lento.
set -euo pipefail
cd "$(dirname "$0")/.."
source scripts/00-variables.sh

echo ">> Creando clúster $CLUSTER_NAME en $AWS_REGION ($NODE_COUNT x $NODE_TYPE)"
eksctl create cluster \
  --name "$CLUSTER_NAME" \
  --region "$AWS_REGION" \
  --version 1.31 \
  --nodegroup-name workers \
  --node-type "$NODE_TYPE" \
  --nodes "$NODE_COUNT" \
  --nodes-min "$NODE_COUNT" \
  --nodes-max 3 \
  --managed \
  --with-oidc \
  --node-volume-size 20

# El driver CSI de EBS ya no viene incluido: sin el, los PVC de postgresql y
# rabbitmq quedan en Pending para siempre. Se instala como addon con su rol IAM.
echo ">> Instalando el driver CSI de EBS"
eksctl create iamserviceaccount \
  --name ebs-csi-controller-sa --namespace kube-system \
  --cluster "$CLUSTER_NAME" --region "$AWS_REGION" \
  --attach-policy-arn arn:aws:iam::aws:policy/service-role/AmazonEBSCSIDriverPolicy \
  --approve --role-only --role-name "AmazonEKS_EBS_CSI_${CLUSTER_NAME}"

eksctl create addon --name aws-ebs-csi-driver \
  --cluster "$CLUSTER_NAME" --region "$AWS_REGION" \
  --service-account-role-arn "arn:aws:iam::${ACCOUNT_ID}:role/AmazonEKS_EBS_CSI_${CLUSTER_NAME}" \
  --force

# La StorageClass gp3 no existe por defecto (EKS trae gp2 sin WaitForFirstConsumer).
echo ">> Creando la StorageClass gp3"
kubectl apply -f - <<'YAML'
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
  name: gp3
  annotations:
    storageclass.kubernetes.io/is-default-class: "true"
provisioner: ebs.csi.aws.com
parameters:
  type: gp3
  encrypted: "true"
# El volumen se crea solo cuando el pod ya tiene nodo asignado, de modo que
# quede en la misma zona de disponibilidad. Sin esto un PVC puede provisionarse
# en una zona donde el pod no cabe y quedar bloqueado.
volumeBindingMode: WaitForFirstConsumer
reclaimPolicy: Delete
allowVolumeExpansion: true
YAML

kubectl get nodes -o wide
echo ">> Clúster listo."
