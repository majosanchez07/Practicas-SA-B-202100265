# ==============================================================================
# Capa 1 - El cluster EKS
#
# Practica 9 - Maria Jose Tebalan Sanchez - 202100265
#
# Esta capa crea la infraestructura de AWS: la red, el plano de control de EKS
# y el grupo de nodos. En la Practica 6 lo mismo se hacia con "eksctl create
# cluster", un comando imperativo cuyo resultado no queda declarado en ninguna
# parte. Aqui el cluster es codigo: lo que dice este archivo es lo que existe,
# terraform plan muestra cualquier diferencia y terraform destroy lo revierte
# por completo.
#
# Por que dos capas separadas (cluster/ y platform/)
# --------------------------------------------------
# Terraform resuelve los providers al comenzar el plan, antes de crear nada.
# Si los recursos de Kubernetes vivieran en este mismo estado, el provider
# kubernetes tendria que apuntar a un endpoint que todavia no existe durante el
# primer apply, y el plan fallaria. Separarlas hace que cada capa tenga un
# unico proveedor con sus datos ya disponibles:
#
#   cluster/   -> provider aws        -> crea el EKS
#   platform/  -> provider kubernetes -> namespaces, cuotas, limites y RBAC
#
# La segunda lee la salida de la primera con un data source, de modo que la
# dependencia entre ambas es explicita y no una coincidencia de nombres.
# ==============================================================================

terraform {
  required_version = ">= 1.5"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }

  # Practica 9: el estado ya no vive en la maquina del estudiante. Reside en
  # S3 (versionado y cifrado) y el bloqueo lo da una tabla de DynamoDB, de modo
  # que dos operadores no pueden aplicar a la vez y cualquier persona con
  # credenciales de la cuenta puede reconstruir la infraestructura desde otro
  # equipo. El bucket y la tabla los crea P9/scripts/crear-backend.sh, una sola
  # vez: el backend no puede declararse dentro del mismo estado que guarda.
  backend "s3" {
    bucket         = "sa-p9-tfstate-202100265"
    key            = "cluster/terraform.tfstate"
    region         = "us-east-2"
    dynamodb_table = "sa-p9-tfstate-lock"
    encrypt        = true
  }
}

provider "aws" {
  region = var.region

  default_tags {
    tags = {
      Practica  = "P9"
      Carne     = var.carne
      Curso     = "Software Avanzado B"
      ManagedBy = "Terraform"
    }
  }
}

# ------------------------------------------------------------------------------
# Datos del entorno
# ------------------------------------------------------------------------------

# Las zonas de disponibilidad no se escriben a mano: se consultan. Asi el
# codigo funciona en cualquier region sin editarlo.
data "aws_availability_zones" "disponibles" {
  state = "available"

  filter {
    name   = "opt-in-status"
    values = ["opt-in-not-required"]
  }
}

locals {
  nombre = "sa-p8-${var.carne}"

  # Dos zonas: EKS exige un minimo de dos para el plano de control, y con dos
  # basta para esta practica. Mas zonas multiplicarian los NAT Gateway, que son
  # el renglon mas caro de la factura.
  azs = slice(data.aws_availability_zones.disponibles.names, 0, 2)
}

# ------------------------------------------------------------------------------
# Red
#
# Se usa el modulo oficial de la comunidad en lugar de declarar a mano la VPC,
# las subredes, las tablas de rutas y el gateway: son cerca de treinta recursos
# cuya unica particularidad son las etiquetas que EKS necesita para descubrir
# donde colocar los balanceadores.
# ------------------------------------------------------------------------------

module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "~> 5.13"

  name = "${local.nombre}-vpc"
  cidr = "10.0.0.0/16"

  azs = local.azs
  # Subredes publicas: alojan el balanceador de entrada.
  public_subnets = ["10.0.0.0/20", "10.0.16.0/20"]
  # Subredes privadas: alojan los nodos. Los pods no son alcanzables desde
  # Internet salvo a traves del balanceador.
  private_subnets = ["10.0.128.0/20", "10.0.144.0/20"]

  # Un solo NAT Gateway compartido por ambas zonas en lugar de uno por zona.
  # Sacrifica tolerancia a la caida de una zona -algo irrelevante en una
  # practica- y ahorra unos 32 USD al mes.
  enable_nat_gateway     = true
  single_nat_gateway     = true
  one_nat_gateway_per_az = false

  enable_dns_hostnames = true
  enable_dns_support   = true

  # Estas dos etiquetas no son decorativas: el controlador de balanceadores de
  # AWS las busca para decidir en que subredes puede crear un Load Balancer.
  # Sin ellas, un Service de tipo LoadBalancer se queda en estado <pending>.
  public_subnet_tags = {
    "kubernetes.io/role/elb"                = "1"
    "kubernetes.io/cluster/${local.nombre}" = "shared"
  }

  private_subnet_tags = {
    "kubernetes.io/role/internal-elb"       = "1"
    "kubernetes.io/cluster/${local.nombre}" = "shared"
  }
}

# ------------------------------------------------------------------------------
# Cluster EKS
# ------------------------------------------------------------------------------

module "eks" {
  source  = "terraform-aws-modules/eks/aws"
  version = "~> 20.31"

  cluster_name    = local.nombre
  cluster_version = var.version_kubernetes

  vpc_id     = module.vpc.vpc_id
  subnet_ids = module.vpc.private_subnets

  # El endpoint publico permite administrar el cluster desde la maquina del
  # estudiante sin montar una VPN ni un bastion. El acceso sigue exigiendo
  # credenciales de AWS y autorizacion por RBAC.
  cluster_endpoint_public_access = true

  # Quien ejecuta terraform apply queda como administrador del cluster. Sin
  # esto habria que editar a mano el aws-auth ConfigMap despues de crearlo, que
  # es justamente el tipo de paso manual que la practica prohibe.
  enable_cluster_creator_admin_permissions = true

  # Addons gestionados por AWS. El driver de EBS es imprescindible: sin el, los
  # PersistentVolumeClaim de PostgreSQL y RabbitMQ se quedan en Pending para
  # siempre, tal como se documento en la Practica 6.
  cluster_addons = {
    coredns    = { most_recent = true }
    kube-proxy = { most_recent = true }
    vpc-cni    = { most_recent = true }
    aws-ebs-csi-driver = {
      most_recent              = true
      service_account_role_arn = module.irsa_ebs_csi.iam_role_arn
    }
  }

  eks_managed_node_groups = {
    workers = {
      min_size     = var.nodos_min
      max_size     = var.nodos_max
      desired_size = var.nodos

      instance_types = [var.tipo_nodo]
      capacity_type  = "ON_DEMAND"

      disk_size = 20

      labels = {
        rol = "workers"
      }
    }
  }

  tags = {
    Practica = "P9"
  }
}

# ------------------------------------------------------------------------------
# Rol IAM para el driver CSI de EBS (IRSA)
#
# IRSA asocia un ServiceAccount de Kubernetes con un rol de IAM a traves del
# proveedor OIDC del cluster. Es el mecanismo que permite que un pod tenga
# permisos de AWS sin credenciales estaticas dentro de la imagen.
# ------------------------------------------------------------------------------

module "irsa_ebs_csi" {
  source  = "terraform-aws-modules/iam/aws//modules/iam-role-for-service-accounts-eks"
  version = "~> 5.48"

  role_name             = "${local.nombre}-ebs-csi"
  attach_ebs_csi_policy = true

  oidc_providers = {
    principal = {
      provider_arn               = module.eks.oidc_provider_arn
      namespace_service_accounts = ["kube-system:ebs-csi-controller-sa"]
    }
  }
}

# ------------------------------------------------------------------------------
# Rol IAM para Velero (IRSA) - Practica 9
#
# Velero escribe los respaldos en un bucket de S3 y toma snapshots de los
# volumenes EBS. Ambos destinos viven fuera del cluster: si el cluster se
# destruye, los respaldos sobreviven. El permiso llega por IRSA, sin llaves de
# acceso estaticas dentro del cluster ni en el repositorio.
#
# El bucket NO se declara aqui: si viviera en este estado, un terraform destroy
# del cluster se llevaria tambien los respaldos, que es exactamente el fallo de
# Code Spaces (2014) visto en clase. Lo crea crear-backend.sh.
# ------------------------------------------------------------------------------

module "irsa_velero" {
  source  = "terraform-aws-modules/iam/aws//modules/iam-role-for-service-accounts-eks"
  version = "~> 5.48"

  role_name             = "${local.nombre}-velero"
  attach_velero_policy  = true
  velero_s3_bucket_arns = ["arn:aws:s3:::${var.bucket_respaldos}"]

  oidc_providers = {
    principal = {
      provider_arn               = module.eks.oidc_provider_arn
      namespace_service_accounts = ["velero:velero-server"]
    }
  }
}
