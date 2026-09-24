# Práctica 9: continuidad operativa y recuperación ante desastres

María José Tebalán Sánchez · 202100265 · Software Avanzado, sección B

Esta práctica toma el sistema de la Práctica 8 (microservicios con
GitOps, entrega progresiva y políticas de admisión) y lo vuelve **recuperable**:
se puede destruir por completo y reconstruir desde un solo comando, con los
datos y los secretos intactos y con los tiempos medidos.

## Tabla de enlaces obligatoria

| Ítem | Enlace o dato requerido |
|---|---|
| Repositorio GitOps | https://github.com/majosanchez07/Practicas-SA-B-202100265-gitops |
| Aplicación raíz en ArgoCD | Aplicación **`raiz-sa-p9`**, namespace **`argocd`** (apunta a `apps/` del repositorio GitOps) |
| Punto de entrada del bootstrap | [`P9/scripts/bootstrap.sh`](scripts/bootstrap.sh) |
| Backend remoto de Terraform | Tipo **`azurerm`** (Azure Blob Storage) con bloqueo por *lease* del blob. Grupo `rg-sa-p9-base-202100265`, cuenta `sap9tfstate202100265`, contenedor `tfstate`, claves `cluster/terraform.tfstate` y `platform/terraform.tfstate` (región `centralus`). Autenticación con Azure AD; sin llaves de la cuenta. Declarado en [`terraform/cluster/main.tf`](terraform/cluster/main.tf) y [`terraform/platform/main.tf`](terraform/platform/main.tf) |
| Schedule de Velero | **`respaldo-sa-p9`** (namespace `velero`), cada 30 min, retención 7 días. Destino: Azure Blob, cuenta **`sap9velero202100265`**, contenedor `velero`, y snapshots de disco en `rg-sa-p9-base-202100265` (centralus, fuera del clúster). Manifiesto: [`platform/velero/schedule.yaml`](https://github.com/majosanchez07/Practicas-SA-B-202100265-gitops/blob/main/platform/velero/schedule.yaml) |
| Reconstrucción cronometrada | [`docs/evidencias/reconstruccion/`](docs/evidencias/reconstruccion/) (`desastre-*.log` + `registro-*.log`) |
| Restauración de datos | [`docs/evidencias/restauracion/`](docs/evidencias/restauracion/) |
| Prueba de pérdida de nodo | [`docs/evidencias/perdida-nodo/`](docs/evidencias/perdida-nodo/) |
| RTO y RPO declarados | Declarados: **RTO 45 min · RPO 30 min** ([rto-rpo-declarados.md](docs/rto-rpo-declarados.md)). Medidos: ver [informe-prueba-dr.md](docs/informe-prueba-dr.md) |
| Video demostrativo | _(URL)_. Minutaje en la [sección Video](#video-demostrativo) |

## Documentos

| Documento | Contenido |
|---|---|
| [docs/runbook-recuperacion.md](docs/runbook-recuperacion.md) | Procedimiento paso a paso que puede seguir un tercero |
| [docs/informe-prueba-dr.md](docs/informe-prueba-dr.md) | Informe de la prueba de DR (los seis campos de la plantilla 4.2) |
| [docs/diagrama-bootstrap.md](docs/diagrama-bootstrap.md) | Orden de reconstrucción y dependencias; distingue lo manual de lo automático |
| [docs/rto-rpo-declarados.md](docs/rto-rpo-declarados.md) | Objetivos declarados antes de las pruebas y clasificación del estado |

## Qué cambió respecto de la Práctica 8

| Debilidad del enunciado | Solución | Dónde |
|---|---|---|
| Nadie respalda los volúmenes | Velero con schedule cada 30 min, snapshots de disco, hook `pg_dump` previo y retención de 7 días. Destino: Azure Blob, fuera del clúster | `terraform/platform/continuidad.tf`, GitOps `platform/velero/`, GitOps `environments/prod/values.yaml` |
| Estado de Terraform en la máquina de la estudiante | Backend `azurerm` versionado, con bloqueo por lease. No hay `.tfstate` en el repositorio | `backend "azurerm"` en las dos capas; `.gitignore` |
| La llave de Sealed Secrets vive solo en el clúster | La llave vive en Azure Key Vault `kv-sa-p9-202100265`. Terraform la inyecta **antes** de instalar el controlador. El certificado público está en `docs/sealed-secrets-cert.pem`, para cifrar sin acceso al clúster | `scripts/respaldar-llave-sealed.sh`, `terraform/platform/continuidad.tf` |
| ArgoCD, Rollouts, Kyverno y Sealed Secrets se instalaban a mano con `helm install` | Terraform instala ArgoCD, Sealed Secrets y Velero; el app-of-apps `raiz-sa-p9` instala el resto | `continuidad.tf`, GitOps `apps/` |
| Pérdida de nodo | Anti-afinidad por nodo, PDB en gateway, auth, books y loans, ≥2 réplicas | `charts/sa-platform/templates/{rollouts,deployments}.yaml`, GitOps `values.yaml` |

**Plataforma:** la P8 corría en EKS (AWS). La P9 corre en **AKS (Azure)**, región
**`centralus`**. Se eligió una región distinta de la del proyecto
(`eastus`/`eastus2`), que comparte la suscripción, para que la prueba de
desastre no pueda tocar sus recursos y para que cada uno tenga su propia cuota
regional de vCPU.

El flujo de la P8 se conserva: el pipeline sigue cambiando solo `imageTag` en el
repositorio GitOps, ArgoCD sincroniza, Argo Rollouts promueve con canary y
Kyverno admite o rechaza. Lo único que cambió en la Application `sa-platform` es
la ruta del chart (`P9/charts/sa-platform`) y su ola de sincronización.

## Uso rápido

```bash
./P9/scripts/crear-backend.sh             # una vez: grupo base, almacenamiento de estado y de respaldos, Key Vault
./P9/scripts/respaldar-llave-sealed.sh generar  # una vez: llave de Sealed Secrets en Key Vault
./P9/scripts/bootstrap.sh                 # PUNTO DE ENTRADA ÚNICO: reconstruye todo
./P9/scripts/prueba-restauracion-datos.sh # borra datos, los restaura y mide el RPO
./P9/scripts/prueba-perdida-nodo.sh       # drena un nodo mientras una sonda consulta el servicio
./P9/scripts/desastre.sh                  # destruye el clúster (escenario de DR)
```

Comprobaciones de los requisitos para calificar:

```bash
kubectl -n argocd get applications                          # todas Synced / Healthy
velero backup get                                           # al menos un respaldo Completed
az storage blob list --account-name sap9tfstate202100265 -c tfstate --auth-mode login -o table  # el estado vive en Azure
git ls-files | grep -c tfstate                              # 0: no hay estado en el repositorio
```

## Video demostrativo

URL: _(pendiente)_

| Minuto | Punto demostrado |
|---|---|
| 0:00 | Estado inicial: ArgoCD con `raiz-sa-p9` y sus hijas en Synced/Healthy; `velero backup get` |
| 1:00 | Estado remoto: blobs del contenedor `tfstate` y el lease durante un `plan`; `git ls-files \| grep tfstate` vacío |
| 1:45 | Restauración de datos: marca A, respaldo, marca B, borrado, restauración y verificación del contenido |
| 3:30 | Pérdida de nodo: drenaje con la sonda respondiendo 200 |
| 4:45 | Desastre: `desastre.sh` y la marca de destrucción |
| 5:30 | `bootstrap.sh` (acelerado) hasta Synced/Healthy; secretos descifrados; datos presentes; RTO medido |
| 7:00 | Flujo de la P8 intacto: rollout, políticas activas |
