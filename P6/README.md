# Práctica 6 — Despliegue de la plataforma en un clúster de Kubernetes en la nube

**María José Tebalán Sánchez — 202100265**
Software Avanzado, Segundo Semestre 2026

Esta práctica lleva la plataforma de microservicios construida en la P5 desde un
clúster local (kind) hasta **Amazon EKS**, un clúster de Kubernetes administrado,
exponiéndola en una dirección pública alcanzable desde internet.

## Contenido

| Ruta | Descripción |
|---|---|
| [`charts/sa-platform/`](charts/sa-platform/) | Chart de Helm heredado de la P5 |
| [`charts/sa-platform/values-eks.yaml`](charts/sa-platform/values-eks.yaml) | **Adaptación a la nube** — el archivo central de esta práctica |
| [`charts/sa-platform/templates/loadbalancer.yaml`](charts/sa-platform/templates/loadbalancer.yaml) | Service de tipo LoadBalancer (punto de entrada público) |
| [`scripts/`](scripts/) | Procedimiento completo, automatizado y reproducible |
| [`docs/preguntas-teoricas.md`](docs/preguntas-teoricas.md) | Respuestas a las 5 preguntas del enunciado |
| [`docs/costos.md`](docs/costos.md) | Costo del despliegue y procedimiento de eliminación |
| [`docs/evidencias/`](docs/evidencias/) | Evidencias de funcionamiento |

## Arquitectura desplegada

```
                        internet
                            │
                            ▼
          ┌──────────────────────────────────┐
          │   Network Load Balancer (AWS)    │  ← dirección pública
          └──────────────────────────────────┘
                            │
  ══════════════════════════│══════════════════ clúster EKS (2 nodos t3.small)
                            ▼
                    ┌───────────────┐
                    │  api-gateway  │           única puerta de entrada
                    └───────┬───────┘
            ┌───────────────┼───────────────┐
            ▼               ▼               ▼
      ┌──────────┐   ┌──────────┐   ┌──────────────┐
      │   auth   │   │  books   │   │    loans     │
      └────┬─────┘   └────┬─────┘   └──────┬───────┘
           │              │                │ publica evento
           │              │                ▼
           │              │        ┌───────────────┐
           │              │        │   RabbitMQ    │  comunicación asíncrona
           │              │        └───────┬───────┘
           │              │                │ consume
           │              │                ▼
           │              │        ┌────────────────┐
           │              │        │ notifications  │
           │              │        └───────┬────────┘
           ▼              ▼                ▼
      ┌────────────────────────────────────────┐
      │        PostgreSQL (EBS gp3)            │
      └────────────────────────────────────────┘
```

Los microservicios, la base de datos y el broker conservan su `ClusterIP`: no son
alcanzables desde internet. La única superficie expuesta es el balanceador.

## Qué cambió respecto a la P5

Sólo tres cosas, todas concentradas en `values-eks.yaml`:

| Aspecto | P5 (kind, local) | P6 (EKS, nube) |
|---|---|---|
| **Imágenes** | `kind load` desde el Docker local | Publicadas en Amazon ECR |
| **Almacenamiento** | `standard` (`rancher.io/local-path`) | `gp3` (EBS vía driver CSI) |
| **Exposición** | Ingress nginx, host `sa-p5.local` en `/etc/hosts` | Service LoadBalancer → NLB público |

El resto del chart —réplicas, probes, HPA, PDB, NetworkPolicies,
`securityContext`, cuotas— se hereda **sin modificar**, que era justamente el
objetivo: la portabilidad de un chart bien parametrizado.

## Requisitos previos

```bash
aws --version      # AWS CLI v2
eksctl version     # >= 0.190
kubectl version --client
helm version
docker --version
aws configure      # credenciales con permisos sobre EKS, EC2, ECR e IAM
                   # region: us-east-2 (Ohio)
```

## Procedimiento de despliegue

Los scripts son idempotentes y llevan la configuración en
[`scripts/00-variables.sh`](scripts/00-variables.sh).

```bash
cd P6

# 1. Crear el clúster administrado con 2 nodos (~20 min)
#    Incluye el driver CSI de EBS y la StorageClass gp3.
./scripts/01-crear-cluster.sh

# 2. Construir y publicar las 7 imágenes en ECR (~5 min)
./scripts/02-publicar-imagenes.sh

# 3. Desplegar la plataforma y obtener la dirección pública (~8 min)
./scripts/03-desplegar.sh

# 4. Recolectar las evidencias de funcionamiento
./scripts/04-evidencias.sh

# 5. IMPORTANTE: eliminar todo al terminar
./scripts/99-eliminar.sh
```

### Verificación manual

```bash
LB=$(cat .direccion-publica)
curl -i "http://$LB/health/ready"
curl -s "http://$LB/books" | head
```

## Gestión de credenciales

**Ninguna credencial está versionada en el repositorio.** Los campos sensibles
de `values.yaml` están vacíos y el chart los valida con `required`, de modo que
la instalación falla con un mensaje claro si no se informan.

`03-desplegar.sh` las toma de variables de entorno y, si no existen, genera
valores aleatorios con `openssl rand`. Helm las materializa en un Secret dentro
del clúster. El archivo `values.secret.yaml` está excluido en `.gitignore`.

## Dirección pública verificada

El sistema quedó accesible desde internet en:

```
http://a071e29918d89451b86249687b6aca56-bf52d25269a5103b.elb.us-east-2.amazonaws.com
```

Las cinco rutas probadas (`/health/live`, `/health/ready`, `/`, `/books`,
`/auth/docs`) respondieron **HTTP 200** desde fuera del clúster. El detalle está
en [`docs/evidencias/02-peticiones-desde-internet.md`](docs/evidencias/02-peticiones-desde-internet.md).

> Esta dirección dejó de existir al eliminar los recursos, tal como pide el
> enunciado. Las evidencias documentan su funcionamiento mientras estuvo activa.

## Imágenes de contenedor

Cada servicio se construye con su `Dockerfile.prod`, una construcción
**multietapa en tres fases** (`deps` → `build` → `prod`): las herramientas de
compilación y las dependencias de desarrollo quedan en las etapas intermedias y
nunca llegan a la imagen publicada. Ver
[`services/api-gateway/Dockerfile.prod`](services/api-gateway/Dockerfile.prod)
como referencia.

## Costo

≈ **$0.17 por hora**, unos **$0.68** por las 4 horas que duró la práctica. Un mes
de olvido costaría ~$122. El desglose y las vías de reducción están en
[`docs/costos.md`](docs/costos.md).

## Eliminación de recursos

```bash
./scripts/99-eliminar.sh
```

El orden importa: el release de Helm se desinstala **antes** de destruir el
clúster, para que AWS retire el balanceador. Al revés quedaría huérfano,
facturándose e impidiendo borrar la VPC. Ver
[`docs/costos.md`](docs/costos.md#4-procedimiento-de-eliminación).
